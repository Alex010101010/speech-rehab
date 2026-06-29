import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Карточка интервального повторения для одного задания (по его id).
/// [box] — стадия расширяющегося интервала (Leitner); [due] — день следующего
/// показа ("yyyy-mm-dd"). Заводится только на задания, которые вспомнили САМИ.
class ReviewCard {
  String type; // фактический тип, которым задание было показано (важно для L0)
  int box;
  String due;
  ReviewCard({required this.type, required this.box, required this.due});

  Map<String, dynamic> toJson() => {'type': type, 'box': box, 'due': due};

  factory ReviewCard.fromJson(Map j) => ReviewCard(
        type: (j['type'] ?? '').toString(),
        box: (j['box'] as num?)?.toInt() ?? 0,
        due: (j['due'] ?? '').toString(),
      );
}

/// Интервальное повторение (spaced retrieval): расширяющиеся интервалы.
/// Повторяем только то, что пациент вспомнил САМ (retrieval practice), а не
/// неуспешное — errorless-повтор проигрывает на отложенных замерах и бьёт по
/// мотивации (см. ревью афазия-приложений 28.06, PMC10023178).
class ReviewScheduler {
  // дни до следующего показа по стадии («коробке»)
  static const intervals = <int>[1, 2, 5, 14, 30];

  /// Вспомнил сам → следующая коробка (реже); не вспомнил → на одну вниз
  /// (вернётся раньше, но НЕ в этой же сессии — без «долбёжа»).
  static int nextBox(int box, {required bool recalled}) {
    final b = recalled ? box + 1 : box - 1;
    return b.clamp(0, intervals.length - 1);
  }

  static String dueAfter(DateTime today, int box) {
    final i = box.clamp(0, intervals.length - 1);
    return dayStr(today.add(Duration(days: intervals[i])));
  }

  static String dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

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
  // расписание интервального повторения: id задания -> карточка
  Map<String, ReviewCard> review;
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
    Map<String, ReviewCard>? review,
    Set<String>? achievements,
    Set<String>? days,
    List<Map<String, dynamic>>? history,
  })  : skillLevels = skillLevels ?? <String, int>{},
        readyStreak = readyStreak ?? <String, int>{},
        probeFails = probeFails ?? <String, int>{},
        review = review ?? <String, ReviewCard>{},
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
        'review': review.map((k, v) => MapEntry(k, v.toJson())),
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
        review: ((j['review'] ?? const {}) as Map).map((k, v) =>
            MapEntry(k.toString(), ReviewCard.fromJson(Map.from(v as Map)))),
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
