import 'dart:math';
import '../models/exercise.dart';
import '../data/content_repository.dart';

class SessionStep {
  final String type;
  final String title;
  final Map<String, dynamic> item;
  final String role; // warmup | core | memory | reading | cooldown
  SessionStep(this.type, this.title, this.item, this.role);
  RenderMode get mode => renderModeFor(type);
}

/// Собирает дневную сессию: разминка → ядро → память → чтение → завершение.
/// Сессия всегда заканчивается лёгким заданием (на успехе).
class SessionBuilder {
  final ContentRepository repo;
  final Random _r = Random();
  SessionBuilder(this.repo);

  List<Map<String, dynamic>> _pick(String type, int maxLevel, int n) {
    final set = repo[type];
    if (set == null) return const [];
    var pool =
        set.items.where((e) => ((e['level'] ?? 1) as int) <= maxLevel).toList();
    if (pool.isEmpty) pool = List.of(set.items);
    pool.shuffle(_r);
    return pool.take(n).toList();
  }

  List<SessionStep> build(int level) {
    final steps = <SessionStep>[];

    void addOne(String type, String role, int maxLevel) {
      final items = _pick(type, maxLevel, 1);
      if (items.isNotEmpty) {
        steps.add(SessionStep(type, repo[type]?.title ?? type, items.first, role));
      }
    }

    // Разминка — лёгкий выбор
    addOne('complete_phrase_choice', 'warmup', 1);

    // Ядро — несколько разных типов под уровень
    final coreTypes = <String>[
      'name_by_description',
      'complete_phrase_choice',
      'fill_letter',
      'prepositions',
      'generalization',
      'synonyms_antonyms',
      'logic_questions',
      'endings_cases',
    ]..shuffle(_r);
    for (final t in coreTypes.take(5)) {
      addOne(t, 'core', level);
    }

    // Память — два ряда
    for (final it in _pick('memory_rows', level, 2)) {
      steps.add(SessionStep(
          'memory_rows', repo['memory_rows']?.title ?? 'Память', it, 'memory'));
    }

    // Чтение и пересказ — один текст
    addOne('reading_texts', 'reading', level);

    // Завершение — лёгкий выбор (успех в конце)
    addOne('complete_phrase_choice', 'cooldown', 1);

    return steps;
  }
}
