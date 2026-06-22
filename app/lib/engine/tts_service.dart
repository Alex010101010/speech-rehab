import 'package:flutter_tts/flutter_tts.dart';

/// Озвучка (русский), медленно и чётко — для пожилого пользователя.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Доступен ли русский голос на устройстве. Если нет — вся озвучка молча
  /// не работает, поэтому главный экран показывает подсказку об установке.
  bool ruAvailable = true;

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
      await _tts.speak(t);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
