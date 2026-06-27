import 'package:flutter_tts/flutter_tts.dart';

/// Озвучка (русский), медленно и чётко — для пожилого пользователя.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Доступен ли русский голос на устройстве. Если нет — вся озвучка молча
  /// не работает, поэтому главный экран показывает подсказку об установке.
  bool ruAvailable = true;

  /// Словарь ударений: чистое слово (нижний регистр) -> форма со знаком U+0301
  /// после ударной гласной. Движок Android-TTS обычно слушается этого знака и
  /// ставит ударение принудительно. Источник — content/stress.json (едет по OTA).
  Map<String, String> _stress = const {};

  void setStress(Map<String, String> map) {
    _stress = {for (final e in map.entries) e.key.toLowerCase(): e.value};
  }

  /// Готовит текст к озвучке: убирает плейсхолдеры пропуска '_' (иначе движок
  /// читает «нижнее подчёркивание») и проставляет ударение по словарю.
  String _prepare(String text) {
    var t = text.replaceAll(RegExp(r'_+'), ' ');
    if (_stress.isNotEmpty) {
      t = t.replaceAllMapped(RegExp(r'[А-Яа-яЁё]+'), (m) {
        return _stress[m[0]!.toLowerCase()] ?? m[0]!;
      });
    }
    return t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  Future<void> _init() async {
    if (_ready) return;
    try {
      final avail = await _tts.isLanguageAvailable('ru-RU');
      ruAvailable = avail == true || avail == 1;
    } catch (_) {
      ruAvailable = false;
    }
    try {
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.42); // медленнее обычного
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
    } catch (_) {
      // голос может отсутствовать — не критично
    }
    _ready = true;
  }

  /// Прогреть движок и вернуть доступность русского голоса.
  Future<bool> ensureReady() async {
    await _init();
    return ruAvailable;
  }

  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _init();
    try {
      await _tts.stop();
      await _tts.speak(_prepare(t));
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
