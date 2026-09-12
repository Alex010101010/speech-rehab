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
  // глубина ФОНЕМАТИЧЕСКОЙ подсказки (иерархия cueing): 0 — справился сам,
  // 1 — первый звук, 2 — больше букв, 3 — показан ответ. Метрика для отчёта.
  final int cueLevel;
  // смысловая (семантическая) подсказка — вторая, независимая ось: картинка,
  // категория, рифма. 0 — не понадобилась, 1 — помогла. Отдельно от cueLevel,
  // чтобы история nameCueSum осталась сопоставимой со старыми сессиями.
  final int semanticCue;
  const StepOutcome({
    required this.correct,
    required this.unaided,
    this.gradeable = true,
    this.cueLevel = 0,
    this.semanticCue = 0,
  });
}

/// Накопитель глубины подсказок за сессию. Называние (продукция) и узнавание —
/// разные конструкты, в один средний балл их мешать нельзя, поэтому бакеты
/// раздельные. Смысловые подсказки считаются по тем же шагам, что попали в
/// бакеты, — знаменатель тренда «смысловых» = nameN + recogN.
class CueTally {
  int nameSum = 0, nameN = 0; // name_by_description: фонематическая глубина 0–3
  int recogSum = 0, recogN = 0; // picture_word: ступень узнавания 0/1/3
  int semN = 0; // сколько раз понадобилась смысловая подсказка

  /// Учесть исход основного (core) шага; [type] — фактический тип задания.
  void add(String type, StepOutcome o) {
    if (!o.gradeable) return; // самооценка и errorless в метрику не идут
    if (type == 'name_by_description') {
      nameSum += o.cueLevel;
      nameN++;
    } else if (type == 'picture_word') {
      recogSum += o.cueLevel;
      recogN++;
    } else {
      return; // остальные типы в трендах подсказок не участвуют
    }
    if (o.semanticCue > 0) semN++;
  }

  /// Поля для снимка сессии в history — только непустые бакеты.
  Map<String, int> toHistoryFields() => {
        if (nameN > 0) 'nameCueSum': nameSum,
        if (nameN > 0) 'nameCueN': nameN,
        if (recogN > 0) 'recogCueSum': recogSum,
        if (recogN > 0) 'recogCueN': recogN,
        if (semN > 0) 'semCueN': semN,
      };
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
