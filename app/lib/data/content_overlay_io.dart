import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show ImageProvider, FileImage;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/exercise.dart';
import 'content_overlay.dart';
import 'ota_config.dart';

ContentOverlay createContentOverlay() => IoContentOverlay();

/// OTA-кеш на устройстве. Раскладка под appSupportDir/ota:
///   active/     — применённый контент (index.json, NN_*.json, manifest.json, img/)
///   staging/    — скачивается обновление (до валидации и свопа)
///   active_old/ — прежний active на время свопа (last-good при крахе)
class IoContentOverlay implements ContentOverlay {
  Directory? _root;
  Directory? _active;
  Map<String, dynamic>? _manifest; // применённый манифест (для ленивых картинок)

  @override
  Future<void> init() async {
    try {
      final support = await getApplicationSupportDirectory();
      final root = Directory('${support.path}/ota');
      final active = Directory('${root.path}/active');
      final old = Directory('${root.path}/active_old');
      // Краш во время свопа: active не успел появиться — вернуть last-good.
      if (!active.existsSync() && old.existsSync()) {
        old.renameSync(active.path);
      }
      // Хвост от прерванного свопа.
      if (old.existsSync()) old.deleteSync(recursive: true);
      _root = root;
      _active = active;
      _manifest = _readActiveManifest();
    } catch (e) {
      debugPrint('OTA init failed: $e'); // ФС недоступна — остаёмся на ассетах
      _root = null;
      _active = null;
    }
  }

  Map<String, dynamic>? _readActiveManifest() {
    final a = _active;
    if (a == null) return null;
    final f = File('${a.path}/manifest.json');
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  int get _activeVersion {
    final v = _manifest?['content_version'];
    return v is int ? v : 0;
  }

  @override
  Future<String?> tryLoadString(String relName) async {
    final a = _active;
    if (a == null) return null;
    final f = File('${a.path}/$relName');
    if (!f.existsSync()) return null;
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  ImageProvider? cachedImage(String fileName) {
    final a = _active;
    if (a == null) return null;
    final f = File('${a.path}/img/$fileName');
    return f.existsSync() ? FileImage(f) : null;
  }

  @override
  Future<ImageProvider?> ensureImage(String fileName) async {
    final a = _active;
    final m = _manifest;
    if (a == null || m == null) return null;
    final f = File('${a.path}/img/$fileName');
    if (f.existsSync()) return FileImage(f);
    final entry = _fileEntry(m, 'img/$fileName');
    if (entry == null) return null; // картинки нет в манифесте — не наша
    try {
      final bytes = await _download('img/$fileName');
      if (!_sha256ok(bytes, entry['sha256'] as String?)) return null;
      f.parent.createSync(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return FileImage(f);
    } catch (e) {
      debugPrint('OTA ensureImage($fileName) failed: $e');
      return null;
    }
  }

  @override
  Future<OtaResult> checkForUpdate() async {
    final root = _root;
    final active = _active;
    if (root == null || active == null) {
      return const OtaResult(OtaStatus.skipped, message: 'нет файловой системы');
    }

    Map<String, dynamic> remote;
    try {
      final bytes = await _download('manifest.json');
      remote = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      return OtaResult(OtaStatus.offline, message: '$e');
    }

    final remoteVersion = (remote['content_version'] as int?) ?? 0;
    final minApp = (remote['min_app_version'] as int?) ?? 0;
    if (minApp > kAppOtaVersion) {
      return OtaResult(OtaStatus.skipped,
          message: 'требуется новая версия приложения (min $minApp)');
    }

    // Базовый локальный уровень: применённый кеш, иначе вшитый ассет.
    final localBaseline =
        _activeVersion > 0 ? _activeVersion : await _bundledVersion();
    if (remoteVersion <= localBaseline) {
      return OtaResult(OtaStatus.upToDate, version: localBaseline);
    }

    // Качаем ВЕСЬ JSON (мелкий) — так active всегда полный. Картинки — лениво.
    final staging = Directory('${root.path}/staging');
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);

      final files = (remote['files'] as List?) ?? const [];
      for (final f in files) {
        if (f is! Map) continue;
        final path = (f['path'] ?? '').toString();
        if (!path.endsWith('.json')) continue; // картинки тянем по требованию
        final bytes = await _download(path);
        if (!_sha256ok(bytes, f['sha256'] as String?)) {
          throw FormatException('sha256 не сходится: $path');
        }
        final out = File('${staging.path}/$path');
        out.parent.createSync(recursive: true);
        await out.writeAsBytes(bytes, flush: true);
      }
      File('${staging.path}/manifest.json').writeAsStringSync(jsonEncode(remote));

      _validate(staging); // index + все наборы должны распарситься

      // Атомарный своп: active -> active_old -> staging -> active.
      final old = Directory('${root.path}/active_old');
      if (old.existsSync()) old.deleteSync(recursive: true);
      if (active.existsSync()) active.renameSync(old.path);
      staging.renameSync(active.path);
      if (old.existsSync()) old.deleteSync(recursive: true);

      _manifest = remote;
      return OtaResult(OtaStatus.updated, version: remoteVersion);
    } catch (e) {
      try {
        if (staging.existsSync()) staging.deleteSync(recursive: true);
      } catch (_) {}
      return OtaResult(OtaStatus.error, message: '$e'); // active не тронут
    }
  }

  /// Проверка целостности скачанного: index.json + каждый набор парсятся.
  void _validate(Directory staging) {
    final index = jsonDecode(
        File('${staging.path}/index.json').readAsStringSync()) as Map<String, dynamic>;
    final types = (index['types'] as List?) ?? const [];
    if (types.isEmpty) throw const FormatException('index.json без types');
    for (final t in types) {
      final m = Map<String, dynamic>.from(t as Map);
      final file = (m['file'] ?? '').toString();
      final base = file.contains('/') ? file.split('/').last : file;
      if (base.isEmpty) continue;
      final raw = File('${staging.path}/$base').readAsStringSync();
      final set = ExerciseSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (set.type.isEmpty) throw FormatException('битый набор: $base');
    }
  }

  Future<int> _bundledVersion() async {
    try {
      final s = await rootBundle.loadString('assets/content/index.json');
      final v = (jsonDecode(s) as Map<String, dynamic>)['content_version'];
      return v is int ? v : 0;
    } catch (_) {
      return 0;
    }
  }

  Map<String, dynamic>? _fileEntry(Map<String, dynamic> m, String path) {
    for (final f in (m['files'] as List?) ?? const []) {
      if (f is Map && f['path'] == path) return Map<String, dynamic>.from(f);
    }
    return null;
  }

  bool _sha256ok(List<int> bytes, String? expected) =>
      expected != null && sha256.convert(bytes).toString() == expected;

  // cache-busting: уникальный ts снимает CDN-кеш GitHub Pages (до ~10 мин).
  Future<List<int>> _download(String relPath) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse('$kOtaBaseUrl/$relPath?ts=$ts');
    final resp = await http.get(url).timeout(kOtaTimeout);
    if (resp.statusCode != 200) {
      throw HttpException('GET $relPath -> ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }
}
