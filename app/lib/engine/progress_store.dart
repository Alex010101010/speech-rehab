import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Прогресс пациента. Накопительный — значения только растут.
class Progress {
  int sessions;
  int answered;
  int correct;
  int level; // производное «общее» (среднее по навыкам) — для экрана и наград
  Map<String, int> skillLevels; // уровень на каждый навык (тип задания)
  bool pictureMode; // картиночный режим: словарные задания только узнаванием (L0)
  // «мягкий выход» из лёгкого режима: по каждому навыку копим безошибочные
  // узнавания (readyStreak); при достижении порога навык получает «пробу» на
  // реальном уровне. probeFails — сколько проб подряд провалено/пропущено
  // (для мягкого отката). Переживают сессии.
  Map<String, int> readyStreak;
  Map<String, int> probeFails;
  Set<String> achievements;
  Set<String> days; // строки "yyyy-mm-dd"
  // снимки по сессиям для динамики в отчёте: {day, answered, correct, level}
  List<Map<String, dynamic>> history;

  Progress({
    this.sessions = 0,
    this.answered = 0,
    this.correct = 0,
    this.level = 1,
    Map<String, int>? skillLevels,
    this.pictureMode = false,
    Map<String, int>? readyStreak,
    Map<String, int>? probeFails,
    Set<String>? achievements,
    Set<String>? days,
    List<Map<String, dynamic>>? history,
  })  : skillLevels = skillLevels ?? <String, int>{},
        readyStreak = readyStreak ?? <String, int>{},
        probeFails = probeFails ?? <String, int>{},
        achievements = achievements ?? <String>{},
        days = days ?? <String>{},
        history = history ?? <Map<String, dynamic>>[];

  Map<String, dynamic> toJson() => {
        'sessions': sessions,
        'answered': answered,
        'correct': correct,
        'level': level,
        'skillLevels': skillLevels,
        'pictureMode': pictureMode,
        'readyStreak': readyStreak,
        'probeFails': probeFails,
        'achievements': achievements.toList(),
        'days': days.toList(),
        'history': history,
      };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        sessions: (j['sessions'] ?? 0) as int,
        answered: (j['answered'] ?? 0) as int,
        correct: (j['correct'] ?? 0) as int,
        level: (j['level'] ?? 1) as int,
        skillLevels: ((j['skillLevels'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        pictureMode: (j['pictureMode'] ?? false) as bool,
        readyStreak: ((j['readyStreak'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        probeFails: ((j['probeFails'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        achievements: ((j['achievements'] ?? const []) as List)
            .map((e) => e.toString())
            .toSet(),
        days: ((j['days'] ?? const []) as List).map((e) => e.toString()).toSet(),
        history: ((j['history'] ?? const []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

class ProgressStore {
  static const _key = 'progress_v1';
  static const _backupMagic = 'speech-rehab';
  static const _backupVersion = 1;
  Progress progress = Progress();

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString(_key);
    if (s != null) {
      try {
        progress = Progress.fromJson(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        progress = Progress();
      }
    }
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(progress.toJson()));
  }

  /// «Код восстановления» — компактный JSON-конверт с прогрессом.
  /// Вставляется в письмо/заметку как офлайн-копия.
  String exportCode() => jsonEncode({
        'app': _backupMagic,
        'backup_version': _backupVersion,
        'progress': progress.toJson(),
      });

  /// Восстанавливает прогресс из кода. Полностью заменяет текущий и сохраняет.
  /// Возвращает false, если код пустой/не распознан (тогда прогресс не тронут).
  Future<bool> importCode(String raw) async {
    final t = raw.trim();
    if (t.isEmpty) return false;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(t) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    if (j['app'] != _backupMagic) return false;
    final pj = j['progress'];
    if (pj is! Map) return false;
    final Progress restored;
    try {
      restored = Progress.fromJson(Map<String, dynamic>.from(pj));
    } catch (_) {
      return false;
    }
    progress = restored;
    await save();
    return true;
  }
}
