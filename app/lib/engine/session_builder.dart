import 'dart:math';
import '../models/exercise.dart';
import '../data/content_repository.dart';

/// Слот сессии без привязки к сложности — конкретное задание подбирается
/// по ходу под текущий рабочий уровень (адаптивная лестница).
class SessionSlot {
  final String type;
  final String role; // warmup | core | memory | reading | cooldown
  final bool fixedEasy; // разминка/завершение — всегда уровень 1 (успех)
  SessionSlot(this.type, this.role, {this.fixedEasy = false});
}

class SessionStep {
  final String type;
  final String title;
  final Map<String, dynamic> item;
  final String role;
  SessionStep(this.type, this.title, this.item, this.role);
  RenderMode get mode => renderModeFor(type);
}

/// Собирает план дневной сессии: разминка → ядро → память → чтение → завершение.
/// Сессия всегда заканчивается лёгким заданием (на успехе).
class SessionBuilder {
  final ContentRepository repo;
  final Random _r = Random();
  SessionBuilder(this.repo);

  List<SessionSlot> buildPlan() {
    final plan = <SessionSlot>[];
    plan.add(SessionSlot('complete_phrase_choice', 'warmup', fixedEasy: true));

    final coreTypes = <String>[
      'name_by_description',
      'complete_phrase_choice',
      'fill_letter',
      'prepositions',
      'generalization',
      'synonyms_antonyms',
      'logic_questions',
      'endings_cases',
      'find_error',
      'clock',
    ]..shuffle(_r);
    for (final t in coreTypes.take(5)) {
      plan.add(SessionSlot(t, 'core'));
    }

    plan.add(SessionSlot('memory_rows', 'memory'));
    plan.add(SessionSlot('memory_rows', 'memory'));
    plan.add(SessionSlot('reading_texts', 'reading'));
    plan.add(SessionSlot('complete_phrase_choice', 'cooldown', fixedEasy: true));
    return plan;
  }

  /// Берёт ещё не использованное задание типа [type] не сложнее [maxLevel]
  /// (мягкое смешивание: на уровне N доступны задания уровней 1..N).
  Map<String, dynamic> pickItem(String type, int maxLevel, Set<Object> used) {
    final set = repo[type];
    if (set == null) return const {};
    var pool =
        set.items.where((e) => ((e['level'] ?? 1) as int) <= maxLevel).toList();
    if (pool.isEmpty) pool = List.of(set.items);
    pool.shuffle(_r);
    for (final it in pool) {
      if (!used.contains(it)) return it;
    }
    return pool.isEmpty ? const {} : pool.first;
  }

  String titleFor(String type) => repo[type]?.title ?? type;
}
