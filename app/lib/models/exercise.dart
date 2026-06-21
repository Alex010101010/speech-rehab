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

/// Как именно рисовать задание данного типа.
enum RenderMode { choice, typed, memory, reading, retell, order, unknown }

RenderMode renderModeFor(String type) {
  switch (type) {
    case 'complete_phrase_choice':
    case 'paronyms':
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
