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
  Set<String> achievements;
  Set<String> days; // строки "yyyy-mm-dd"

  Progress({
    this.sessions = 0,
    this.answered = 0,
    this.correct = 0,
    this.level = 1,
    Map<String, int>? skillLevels,
    this.pictureMode = false,
    Set<String>? achievements,
    Set<String>? days,
  })  : skillLevels = skillLevels ?? <String, int>{},
        achievements = achievements ?? <String>{},
        days = days ?? <String>{};

  Map<String, dynamic> toJson() => {
        'sessions': sessions,
        'answered': answered,
        'correct': correct,
        'level': level,
        'skillLevels': skillLevels,
        'pictureMode': pictureMode,
        'achievements': achievements.toList(),
        'days': days.toList(),
      };

  factory Progress.fromJson(Map<String, dynamic> j) => Progress(
        sessions: (j['sessions'] ?? 0) as int,
        answered: (j['answered'] ?? 0) as int,
        correct: (j['correct'] ?? 0) as int,
        level: (j['level'] ?? 1) as int,
        skillLevels: ((j['skillLevels'] ?? const {}) as Map)
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        pictureMode: (j['pictureMode'] ?? false) as bool,
        achievements: ((j['achievements'] ?? const []) as List)
            .map((e) => e.toString())
            .toSet(),
        days: ((j['days'] ?? const []) as List).map((e) => e.toString()).toSet(),
      );
}

class ProgressStore {
  static const _key = 'progress_v1';
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
}
