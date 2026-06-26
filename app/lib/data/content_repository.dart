import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/exercise.dart';
import 'content_overlay.dart';

/// Загружает все наборы заданий по манифесту index.json.
/// Источник байтов: OTA-кеш (если есть свежая версия) → вшитый ассет.
class ContentRepository {
  final Map<String, ExerciseSet> _sets = {};
  final ContentOverlay _overlay;

  ContentRepository({ContentOverlay? overlay})
      : _overlay = overlay ?? createContentOverlay();

  /// Читает файл контента по плоскому имени ('index.json', '01_find_error.json'):
  /// сначала OTA-кеш, при промахе — вшитый ассет.
  Future<String> _loadString(String relPath) async {
    final fresh = await _overlay.tryLoadString(relPath);
    if (fresh != null) return fresh;
    return rootBundle.loadString('assets/content/$relPath');
  }

  Future<void> load() async {
    final indexStr = await _loadString('index.json');
    final index = jsonDecode(indexStr) as Map<String, dynamic>;
    final types = (index['types'] as List).cast<dynamic>();
    for (final t in types) {
      final m = Map<String, dynamic>.from(t as Map);
      final file = (m['file'] ?? '').toString(); // напр. "json/01_find_error.json"
      final base = file.contains('/') ? file.split('/').last : file;
      if (base.isEmpty) continue;
      final raw = await _loadString(base);
      final set = ExerciseSet.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _sets[set.type] = set;
    }
  }

  ExerciseSet? operator [](String type) => _sets[type];
  bool has(String type) => _sets.containsKey(type);
  Iterable<String> get types => _sets.keys;
  int get total => _sets.values.fold(0, (a, s) => a + s.items.length);
}
