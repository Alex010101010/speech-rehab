/// Набор заданий одного типа (загружается из assets/content/NN_type.json).
class ExerciseSet {
  final String type;
  final String title;
  final String section;
  final List<Map<String, dynamic>> items;

  ExerciseSet({
    required this.type,
    required this.title,
    required this.section,
    required this.items,
  });

  factory ExerciseSet.fromJson(Map<String, dynamic> j) => ExerciseSet(
        type: (j['type'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        section: (j['section'] ?? '').toString(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

/// Результат одного шага — для адаптации сложности (лестница).
class StepOutcome {
  final bool correct; // верно (не показано принудительно)
  final bool unaided; // верно с первой попытки, без подсказок
  final bool gradeable; // объективно оцениваемое (выбор/ввод), не самооценка
  // глубина подсказки (иерархия cueing): 0 — справился сам, 1 — первый звук,
  // 2 — больше букв, 3 — показан ответ. Метрика восстановления для отчёта.
  final int cueLevel;
  const StepOutcome({
    required this.correct,
    required this.unaided,
    this.gradeable = true,
    this.cueLevel = 0,
  });
}

/// Как именно рисовать задание данного типа.
enum RenderMode { choice, typed, memory, reading, retell, order, unknown }

RenderMode renderModeFor(String type) {
  switch (type) {
    case 'complete_phrase_choice':
    case 'paronyms':
    case 'endings_choice':
      return RenderMode.choice;
    case 'memory_rows':
      return RenderMode.memory;
    case 'reading_texts':
      return RenderMode.reading;
    case 'retell_texts':
      return RenderMode.retell;
    case 'story_order':
      return RenderMode.order;
    case 'name_by_description':
    case 'professions':
    case 'generalization':
    case 'part_whole':
    case 'synonyms_antonyms':
    case 'word_formation':
    case 'prepositions':
    case 'endings_cases':
    case 'complete_phrase_open':
    case 'find_error':
    case 'logic_questions':
    case 'fill_letter':
    case 'stress':
      return RenderMode.typed;
    default:
      return RenderMode.unknown;
  }
}
