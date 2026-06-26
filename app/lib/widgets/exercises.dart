import 'package:flutter/material.dart';
import '../engine/tts_service.dart';
import '../models/exercise.dart';
import 'ota_image.dart';

// ---------- проверка ответа ----------

String normalize(String s) => s
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^0-9a-zа-я ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

bool checkTyped(Map<String, dynamic> item, String input) {
  final candidates = <String>[];
  if (item['answer'] != null) candidates.add(item['answer'].toString());
  if (item['accept'] is List) {
    for (final a in (item['accept'] as List)) {
      candidates.add(a.toString());
    }
  }
  final n = normalize(input);
  if (n.isEmpty) return false;
  return candidates.any((c) => normalize(c) == n);
}

int _editDistance(String a, String b) {
  final la = a.length, lb = b.length;
  if (la == 0) return lb;
  if (lb == 0) return la;
  var prev = List<int>.generate(lb + 1, (i) => i);
  var cur = List<int>.filled(lb + 1, 0);
  for (var i = 1; i <= la; i++) {
    cur[0] = i;
    for (var j = 1; j <= lb; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[lb];
}

/// Похожи ли слова с допуском на опечатки (короткие — строго).
bool _fuzzyWord(String a, String b) {
  if (a == b) return true;
  final m = a.length > b.length ? a.length : b.length;
  if (m <= 3) return false; // короткие слова — только точное совпадение
  final tol = m <= 5 ? 1 : 2;
  return _editDistance(a, b) <= tol;
}

/// Мягкая проверка ТОЛЬКО для свободного ввода: терпит опечатки и лишние
/// слова (все слова ответа должны присутствовать). Для выбора вариантов НЕ
/// использовать — там нужен строгий [checkTyped], иначе примет похожий дистрактор.
bool checkTypedLenient(Map<String, dynamic> item, String input) {
  final n = normalize(input);
  if (n.isEmpty) return false;
  final inTokens = n.split(' ');
  final candidates = <String>[];
  if (item['answer'] != null) candidates.add(item['answer'].toString());
  if (item['accept'] is List) {
    for (final a in (item['accept'] as List)) {
      candidates.add(a.toString());
    }
  }
  for (final c in candidates) {
    final cn = normalize(c);
    if (cn.isEmpty) continue;
    if (cn == n) return true; // точное
    if (_fuzzyWord(cn, n)) return true; // опечатка в целой фразе
    // все слова ответа есть во вводе (порядок и лишние слова не важны)
    final cTokens = cn.split(' ');
    if (cTokens.every((ct) => inTokens.any((it) => _fuzzyWord(ct, it)))) {
      return true;
    }
  }
  return false;
}

/// Формулировка задания. Для синонимов/антонимов (`task`) явно указываем,
/// какое слово ждём, иначе по голому слову непонятно: синоним или антоним.
String displayPrompt(String type, Map<String, dynamic> item) {
  final p = (item['prompt'] ?? '').toString();
  switch (type) {
    case 'find_error':
      return 'Найдите одно неверное слово и повторите предложение целиком, '
          'исправив его.\n'
          'Например: «Зимой на улице жарко» → «Зимой на улице холодно».\n\n$p';
    case 'synonyms_antonyms':
      final task = (item['task'] ?? '').toString();
      return task == 'синоним'
          ? 'Близкое по смыслу слову «$p» (синоним)'
          : 'Противоположное по смыслу слову «$p»';
    case 'prepositions':
      return 'Вставьте подходящий предлог.\n'
          'Например: «Кот сидит ___ окне» → «на».\n\n$p';
    case 'endings_cases':
      return 'Поставьте слово в скобках в правильную форму.\n'
          'Например: «много (дом…)» → «домов».\n\n$p';
    case 'generalization':
      return 'Назовите одним общим словом.\n'
          'Например: «стол, стул, шкаф» → «мебель».\n\n$p';
    case 'fill_letter':
      return 'Напишите слово целиком, вставив пропущенную букву:\n\n$p';
    default:
      return p;
  }
}

/// Длина эталона `answer` (буквы без пробелов) для живой шкалы прогресса.
/// null — шкалу не показываем (errorless или fill_letter со своей формой).
int? answerTargetLen(String type, Map<String, dynamic> item, bool errorless) {
  if (errorless) return null;
  final letters = (item['answer'] ?? '').toString().replaceAll(RegExp(r'\s+'), '');
  return letters.isEmpty ? null : letters.runes.length;
}

/// Живая шкала длины ответа: по мере ввода показывает «мало / столько же /
/// лишнее» (цвет + короткая подпись). Опора при афазии без счёта букв.
class _LengthGauge extends StatelessWidget {
  final int target;
  final int current;
  const _LengthGauge({required this.target, required this.current});

  @override
  Widget build(BuildContext context) {
    final over = current > target;
    final exact = current == target && current > 0;
    final ratio = target == 0 ? 0.0 : (current / target).clamp(0.0, 1.0);
    final Color fill = over
        ? const Color(0xFFE8A33D) // лишнее — янтарный
        : (exact ? const Color(0xFF2E9E5B) : const Color(0xFF4C84D6));
    final String label = current == 0
        ? 'Начните писать'
        : over
            ? 'Длинновато — проверьте'
            : (exact ? 'Длина совпала — проверьте' : 'Пишите…');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 22,
            color: const Color(0xFFE7EAF0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: ratio == 0 ? 0.001 : ratio,
                child: Container(color: fill),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 18, color: fill, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ---------- общий каркас задания ----------

class ExerciseScaffold extends StatelessWidget {
  final String prompt;
  final Widget child;
  final String hint;
  final bool solved;
  final VoidCallback onNext;
  final TtsService tts;
  final String nextLabel;
  final String? imageName; // имя файла картинки-подсказки (если есть)
  final String? emoji; // значок-подсказка (если нет картинки)
  const ExerciseScaffold({
    super.key,
    required this.prompt,
    required this.child,
    required this.hint,
    required this.solved,
    required this.onNext,
    required this.tts,
    this.nextLabel = 'Дальше',
    this.imageName,
    this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (imageName != null) ...[
                  Center(
                    // OTA-кеш → вшитый ассет → emoji (запасная опора)
                    child: OtaImage(
                        fileName: imageName!, emoji: emoji, height: 200),
                  ),
                  const SizedBox(height: 16),
                ] else if (emoji != null && emoji!.isNotEmpty) ...[
                  Center(
                    child: Text(emoji!, style: const TextStyle(fontSize: 110)),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(prompt,
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      iconSize: 42,
                      icon: const Icon(Icons.volume_up),
                      tooltip: 'Прослушать',
                      onPressed: () => tts.speak(prompt),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                child,
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: solved
                        ? Colors.green.shade50
                        : const Color(0xFFEAF1FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(hint,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: solved
                              ? Colors.green.shade800
                              : const Color(0xFF1A3A66))),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: solved ? Colors.green : null,
            foregroundColor: solved ? Colors.white : null,
          ),
          onPressed: solved ? onNext : null,
          child: Text(nextLabel),
        ),
      ],
    );
  }
}

// ---------- выбор из вариантов ----------

class ChoiceExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final String type;

  /// Безошибочный режим (пол лестницы): сразу подсвечиваем верный, гасим
  /// неверные — задание невозможно провалить.
  final bool errorless;
  const ChoiceExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.type = '',
      this.errorless = false});
  @override
  State<ChoiceExercise> createState() => _ChoiceExerciseState();
}

class _ChoiceExerciseState extends State<ChoiceExercise> {
  String? _wrongPick;
  final Set<String> _faded = {}; // погашенные подсказкой неверные варианты
  bool _solved = false;
  bool _revealed = false; // ответ показан по «Не знаю» — засчитываем как неверный

  bool _isCorrect(String o) =>
      checkTyped(widget.item, o) ||
      normalize(o) == normalize((widget.item['answer'] ?? '').toString());

  // Перемешанный один раз порядок: в контенте правильный ответ всегда стоит
  // первым, поэтому без перемешивания он бы всегда был верхней кнопкой.
  late final List<String> _options = ((widget.item['options'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList()
    ..shuffle();

  List<String> _wrongLeft(List<String> options) =>
      options.where((o) => !_isCorrect(o) && !_faded.contains(o)).toList();

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      // гасим все неверные, оставляем только правильный, проговариваем его
      for (final o in _options) {
        if (!_isCorrect(o)) _faded.add(o);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _options.firstWhere(_isCorrect, orElse: () => '');
        if (c.isNotEmpty) widget.tts.speak('Правильный ответ. $c');
      });
    }
  }

  void _hint(List<String> options) {
    final left = _wrongLeft(options);
    if (left.length <= 1) return; // оставляем хотя бы один неверный вариант
    setState(() => _faded.add(left.first));
  }

  void _reveal(List<String> options) {
    final correct = options.firstWhere(_isCorrect, orElse: () => '');
    setState(() {
      _revealed = true;
      _solved = true;
    });
    if (correct.isNotEmpty) widget.tts.speak('Правильный ответ. $correct');
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(
      correct: !_revealed,
      unaided: !_revealed && _wrongPick == null && _faded.isEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompt = displayPrompt(widget.type, widget.item);
    final img = (widget.item['image'] ?? '').toString();
    final emoji = (widget.item['emoji'] ?? '').toString();
    final options = _options;
    final canHint = !widget.errorless && _wrongLeft(options).length > 1;
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      imageName: img.isEmpty ? null : img,
      emoji: emoji.isEmpty ? null : emoji,
      solved: _solved,
      hint: widget.errorless
          ? 'Это правильный ответ — нажмите его'
          : (_solved
              ? (_revealed ? 'Правильный ответ показан' : 'Верно!')
              : (_wrongPick != null ? 'Попробуйте ещё раз' : 'Выберите ответ')),
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_solved || widget.errorless) && _isCorrect(o)
                      ? Colors.green.shade100
                      : (_wrongPick == o ? Colors.orange.shade100 : null),
                ),
                onPressed: (_solved || _faded.contains(o))
                    ? null
                    : () {
                        if (_isCorrect(o)) {
                          setState(() => _solved = true);
                          widget.tts.speak('Верно. $o');
                        } else {
                          setState(() => _wrongPick = o);
                        }
                      },
                child: Text(o, textAlign: TextAlign.center),
              ),
            ),
          if (!_solved && !widget.errorless)
            Row(
              children: [
                if (canHint) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _hint(options),
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Подсказка'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reveal(options),
                    child: const Text('Не знаю'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------- картинка → слово (этаж L0, узнавание) ----------

/// До-вербальный пол лестницы: показываем картинку и просим выбрать слово.
/// Узнавание (а не воспроизведение) — самая нижняя ступень для грубой формы.
class PictureWordExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final bool errorless;
  const PictureWordExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.errorless = false});
  @override
  State<PictureWordExercise> createState() => _PictureWordExerciseState();
}

class _PictureWordExerciseState extends State<PictureWordExercise> {
  String? _wrongPick;
  final Set<String> _faded = {}; // погашенные подсказкой неверные варианты
  bool _solved = false;
  bool _revealed = false; // ответ показан по «Не знаю» — засчитываем как неверный
  bool _hintUsed = false;

  String get _answer => (widget.item['answer'] ?? '').toString();
  bool _isCorrect(String o) => normalize(o) == normalize(_answer);

  // правильный ответ в контенте стоит первым — перемешиваем один раз
  late final List<String> _options =
      ((widget.item['options'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList()
        ..shuffle();

  List<String> _wrongLeft() =>
      _options.where((o) => !_isCorrect(o) && !_faded.contains(o)).toList();

  void _hint() {
    final left = _wrongLeft();
    if (left.length <= 1) return; // оставляем хотя бы один неверный вариант
    setState(() {
      _faded.add(left.first);
      _hintUsed = true;
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      _solved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_answer.isNotEmpty) widget.tts.speak('Это $_answer');
      });
    }
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(
      correct: !_revealed,
      unaided: !_revealed && _wrongPick == null && !_hintUsed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = (widget.item['image'] ?? '').toString();
    final emoji = (widget.item['emoji'] ?? '').toString();
    final canHint = !widget.errorless && _wrongLeft().length > 1;
    return ExerciseScaffold(
      prompt: 'Как это называется?',
      tts: widget.tts,
      imageName: img.isEmpty ? null : img,
      // emoji передаём всегда: при картинке — как фолбэк, без картинки — основной cue
      emoji: emoji.isEmpty ? null : emoji,
      solved: _solved,
      hint: widget.errorless
          ? 'Это правильный ответ — нажмите его'
          : (_solved
              ? (_revealed ? 'Правильный ответ показан' : 'Верно!')
              : (_wrongPick != null ? 'Попробуйте ещё раз' : 'Выберите слово')),
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          for (final o in _options)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_solved || widget.errorless) && _isCorrect(o)
                      ? Colors.green.shade100
                      : (_wrongPick == o ? Colors.orange.shade100 : null),
                ),
                onPressed: (_solved || _faded.contains(o))
                    ? null
                    : () {
                        if (_isCorrect(o)) {
                          setState(() => _solved = true);
                          widget.tts.speak('Верно. $o');
                        } else {
                          setState(() => _wrongPick = o);
                        }
                      },
                child: Text(o, textAlign: TextAlign.center),
              ),
            ),
          if (!_solved && !widget.errorless)
            Row(
              children: [
                if (canHint) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _hint,
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('Подсказка'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _revealed = true;
                        _solved = true;
                      });
                      if (_answer.isNotEmpty) widget.tts.speak('Это $_answer');
                    },
                    child: const Text('Не знаю'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------- да/нет: слово ↔ картинка (этаж L0, узнавание) ----------

/// Самая нижняя ступень узнавания: картинка + одно слово, ответ Да/Нет.
/// Бинарный выбор легче, чем выбор из трёх (picture_word).
class YesNoPictureExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final bool errorless;
  const YesNoPictureExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.errorless = false});
  @override
  State<YesNoPictureExercise> createState() => _YesNoPictureExerciseState();
}

class _YesNoPictureExerciseState extends State<YesNoPictureExercise> {
  bool _solved = false;
  bool _revealed = false; // ответ показан по «Не знаю» — засчитываем как неверный
  bool _wrong = false; // была неверная попытка (для unaided)
  bool? _picked; // выбранное «да/нет» (для подсветки кнопки)

  bool get _match => widget.item['match'] == true;
  String get _word => (widget.item['word'] ?? '').toString();

  String get _truth => _match ? 'Да, это $_word' : 'Нет, это не $_word';

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      _solved = true;
      _picked = _match;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_word.isNotEmpty) widget.tts.speak(_truth);
      });
    }
  }

  void _answer(bool yes) {
    if (_solved) return;
    if (yes == _match) {
      setState(() {
        _solved = true;
        _picked = yes;
      });
      widget.tts.speak(_truth);
    } else {
      setState(() {
        _wrong = true;
        _picked = yes;
      });
    }
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(correct: !_revealed, unaided: !_revealed && !_wrong);
  }

  Widget _button(String label, bool yes) {
    final correctBtn = (_solved || widget.errorless) && yes == _match;
    final wrongBtn = _picked == yes && yes != _match;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 22),
          backgroundColor: correctBtn
              ? Colors.green.shade100
              : (wrongBtn ? Colors.orange.shade100 : null),
        ),
        onPressed: _solved ? null : () => _answer(yes),
        child: Text(label, style: const TextStyle(fontSize: 30)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = (widget.item['image'] ?? '').toString();
    final emoji = (widget.item['emoji'] ?? '').toString();
    return ExerciseScaffold(
      prompt: 'Это $_word?',
      tts: widget.tts,
      imageName: img.isEmpty ? null : img,
      emoji: emoji.isEmpty ? null : emoji,
      solved: _solved,
      hint: widget.errorless
          ? 'Нажмите правильный ответ'
          : (_solved
              ? (_revealed ? 'Правильный ответ показан' : 'Верно!')
              : (_wrong ? 'Попробуйте ещё раз' : 'Ответьте: да или нет')),
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          Row(
            children: [
              _button('Да', true),
              const SizedBox(width: 16),
              _button('Нет', false),
            ],
          ),
          const SizedBox(height: 14),
          if (!_solved && !widget.errorless)
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _revealed = true;
                  _solved = true;
                  _picked = _match;
                });
                if (_word.isNotEmpty) widget.tts.speak(_truth);
              },
              child: const Text('Не знаю'),
            ),
        ],
      ),
    );
  }
}

// ---------- собрать слово из слогов (этаж L0) ----------

/// Семья fill_letter, но проще: слово собирается из целых слогов касанием,
/// без печати. Слоги ставятся по порядку — неверный слог просто не встаёт
/// (как ударная гласная в StressExercise), провалить нельзя.
class SyllablesExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final bool errorless;
  const SyllablesExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.errorless = false});
  @override
  State<SyllablesExercise> createState() => _SyllablesExerciseState();
}

class _SyllablesExerciseState extends State<SyllablesExercise> {
  late final List<String> _syl = ((widget.item['syllables'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  // перемешанный пул слогов с устойчивой идентичностью по индексу (слоги
  // могут повторяться) — правильный порядок в контенте, поэтому перемешиваем
  late final List<String> _pool = List<String>.of(_syl)..shuffle();
  final List<int> _placed = []; // индексы из _pool в порядке постановки
  int? _wrongPick; // индекс пула с неверной попыткой (подсветка)
  int _wrongCount = 0;
  bool _hintUsed = false;
  bool _solved = false;
  bool _revealed = false;

  String get _answer => (widget.item['answer'] ?? '').toString();
  String get _expected =>
      _placed.length < _syl.length ? _syl[_placed.length] : '';

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      _fillCorrect();
      _solved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_answer.isNotEmpty) widget.tts.speak('Это слово. $_answer');
      });
    }
  }

  // расставить все слоги в правильном порядке (для подсказки/«Не знаю»/errorless)
  void _fillCorrect() {
    _placed.clear();
    for (final s in _syl) {
      for (var i = 0; i < _pool.length; i++) {
        if (_pool[i] == s && !_placed.contains(i)) {
          _placed.add(i);
          break;
        }
      }
    }
  }

  void _tapPool(int i) {
    if (_solved || _placed.contains(i)) return;
    if (_pool[i] == _expected) {
      setState(() {
        _placed.add(i);
        _wrongPick = null;
        if (_placed.length == _syl.length) {
          _solved = true;
          widget.tts.speak(_answer);
        }
      });
    } else {
      setState(() {
        _wrongPick = i;
        _wrongCount++;
      });
    }
  }

  void _undo() {
    if (_solved || _placed.isEmpty) return;
    setState(() {
      _placed.removeLast();
      _wrongPick = null;
    });
  }

  void _hint() {
    if (_solved || _expected.isEmpty) return;
    for (var i = 0; i < _pool.length; i++) {
      if (_pool[i] == _expected && !_placed.contains(i)) {
        setState(() {
          _placed.add(i);
          _hintUsed = true;
          _wrongPick = null;
          if (_placed.length == _syl.length) {
            _solved = true;
            widget.tts.speak(_answer);
          }
        });
        return;
      }
    }
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(
      correct: !_revealed,
      unaided: !_revealed && _wrongCount == 0 && !_hintUsed,
    );
  }

  Widget _syllableTile(String text,
      {required bool placed, required bool wrong, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: wrong
              ? Colors.orange.shade200
              : (placed ? Colors.green.shade100 : Colors.blue.shade50),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200, width: 2),
        ),
        child: Text(text, style: const TextStyle(fontSize: 32)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emoji = (widget.item['emoji'] ?? '').toString();
    final assembled = _placed.map((i) => _pool[i]).join();
    return ExerciseScaffold(
      prompt: 'Соберите слово из слогов',
      tts: widget.tts,
      emoji: emoji.isEmpty ? null : emoji,
      solved: _solved,
      hint: _solved
          ? (_revealed ? 'Слово показано' : 'Верно!')
          : (_wrongPick != null
              ? 'Этот слог не подходит — попробуйте другой'
              : 'Нажимайте слоги по порядку'),
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          // собранное слово (плашки уже поставленных слогов, можно снять)
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            alignment: Alignment.center,
            child: assembled.isEmpty
                ? Text('—',
                    style: TextStyle(fontSize: 32, color: Colors.grey.shade400))
                : Wrap(
                    spacing: 6,
                    children: [
                      for (final i in _placed)
                        _syllableTile(_pool[i],
                            placed: true,
                            wrong: false,
                            onTap: _solved ? null : _undo),
                    ],
                  ),
          ),
          const SizedBox(height: 18),
          // банк слогов (ещё не поставленные)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _pool.length; i++)
                if (!_placed.contains(i))
                  _syllableTile(_pool[i],
                      placed: false,
                      wrong: _wrongPick == i,
                      onTap: () => _tapPool(i)),
            ],
          ),
          const SizedBox(height: 18),
          if (!_solved)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _hint,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Подсказка'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _fillCorrect();
                        _revealed = true;
                        _solved = true;
                      });
                      if (_answer.isNotEmpty) widget.tts.speak(_answer);
                    },
                    child: const Text('Не знаю'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------- ввод текста ----------

class TypedExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final String type;
  final bool errorless;
  const TypedExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.type = '',
      this.errorless = false});
  @override
  State<TypedExercise> createState() => _TypedExerciseState();
}

class _TypedExerciseState extends State<TypedExercise> {
  final _c = TextEditingController();
  bool _solved = false;
  bool _revealed = false;
  bool _hintUsed = false;
  bool _cueShown = false; // картинка/эмодзи-подсказка раскрыта по кнопке
  int _tries = 0;
  int _letterHints = 0; // сколько раз показывали буквенную подсказку (макс. 2)
  String _hint = 'Напишите ответ';

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      // показываем ответ и просим прочитать вслух — провалить нельзя
      final ans = (widget.item['answer'] ?? '').toString();
      _solved = true;
      _hint = ans.isEmpty ? 'Нажмите «Дальше»' : 'Прочитайте вслух: $ans';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ans.isNotEmpty) widget.tts.speak(ans);
      });
    } else if (answerTargetLen(widget.type, widget.item, false) != null) {
      // длину показывает живая шкала — текстовая подсказка о числе слов не нужна
      _hint = 'Напишите ответ';
    } else {
      // подсказка по форме ответа: сколько слов ожидается
      _hint = _wordsHint((widget.item['answer'] ?? '').toString());
    }
  }

  static String _plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'слово';
    if (m10 >= 2 && m10 <= 4 && !(m100 >= 12 && m100 <= 14)) return 'слова';
    return 'слов';
  }

  String _wordsHint(String answer) {
    final n = answer.trim().isEmpty
        ? 0
        : answer.trim().split(RegExp(r'\s+')).length;
    if (n <= 0) return 'Напишите ответ';
    if (n == 1) return 'Ответ — одно слово';
    return 'Ответ — $n ${_plural(n)}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _check() {
    if (checkTypedLenient(widget.item, _c.text)) {
      setState(() {
        _solved = true;
        _hint = 'Верно!';
      });
      widget.tts.speak('Верно');
    } else {
      _tries++;
      if (_tries >= 2) {
        final ans = (widget.item['answer'] ?? '').toString();
        setState(() {
          _revealed = true;
          _solved = true;
          _hint = 'Правильный ответ: $ans';
        });
        widget.tts.speak(ans);
      } else {
        setState(() => _hint = 'Попробуйте ещё раз');
      }
    }
  }

  void _giveHint() {
    // первый шаг подсказки — раскрыть визуальный cue (картинку/эмодзи), если есть
    final hasCue = (widget.item['image'] ?? '').toString().isNotEmpty ||
        (widget.item['emoji'] ?? '').toString().isNotEmpty;
    if (hasCue && !_cueShown) {
      setState(() {
        _cueShown = true;
        _hintUsed = true;
        _hint = 'Подсказка: смотрите картинку';
      });
      return;
    }
    final ans = (widget.item['answer'] ?? '').toString();
    if (ans.isEmpty) return;
    final runes = ans.runes.toList();
    final len = runes.length;
    // прогрессивно: 1-е нажатие — первая буква; 2-е — около половины (если
    // пропущено больше 1 буквы); дальше новой информации не добавляем
    if (_letterHints >= 2 || (_letterHints >= 1 && len <= 2)) {
      setState(() => _hint = 'Больше подсказок нет — попробуйте или «Не знаю»');
      return;
    }
    _letterHints++;
    final reveal = _letterHints == 1
        ? 1
        : ((len + 1) ~/ 2).clamp(1, len - 1); // половина, но не всё слово
    final prefix = String.fromCharCodes(runes.take(reveal));
    setState(() {
      _hintUsed = true;
      _hint = reveal == 1
          ? 'Подсказка: начинается на «$prefix»'
          : 'Подсказка: начинается на «$prefix…»';
    });
    widget.tts.speak('Начинается на $prefix');
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(
      correct: !_revealed,
      unaided: !_revealed && _tries == 0 && !_hintUsed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompt = displayPrompt(widget.type, widget.item);
    final img = (widget.item['image'] ?? '').toString();
    final emoji = (widget.item['emoji'] ?? '').toString();
    final target = answerTargetLen(widget.type, widget.item, widget.errorless);
    final typedLen = _c.text.replaceAll(RegExp(r'\s+'), '').runes.length;
    // визуальный cue показываем только после нажатия «Подсказка»
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      imageName: (_cueShown && img.isNotEmpty) ? img : null,
      emoji: (_cueShown && emoji.isNotEmpty) ? emoji : null,
      hint: _hint,
      solved: _solved,
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          if (target != null && !_solved) ...[
            _LengthGauge(target: target, current: typedLen),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _c,
            enabled: !_solved,
            style: const TextStyle(fontSize: 26),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}), // живой пересчёт шкалы длины
            onSubmitted: (_) => _check(),
          ),
          const SizedBox(height: 14),
          if (!_solved)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                      onPressed: _check, child: const Text('Проверить')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                      onPressed: _giveHint, child: const Text('Подсказка')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---------- найди и исправь ошибку (устно, самооценка) ----------

class FixErrorExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  const FixErrorExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<FixErrorExercise> createState() => _FixErrorExerciseState();
}

class _FixErrorExerciseState extends State<FixErrorExercise> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final prompt = (widget.item['prompt'] ?? '').toString();
    final answer = (widget.item['answer'] ?? '').toString();
    return ExerciseScaffold(
      prompt: 'Найдите ошибку и скажите правильно:\n$prompt',
      tts: widget.tts,
      solved: true, // самооценка: «Дальше» доступно всегда
      hint: _revealed ? 'Правильно: $answer' : 'Скажите вслух, потом проверьте',
      onNext: () => widget.onResult(
          const StepOutcome(correct: true, unaided: true, gradeable: false)),
      child: Column(
        children: [
          if (!_revealed)
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _revealed = true);
                widget.tts.speak(answer);
              },
              icon: const Icon(Icons.check),
              label: const Text('Показать правильно'),
            )
          else
            Text(answer,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, color: Colors.green.shade800)),
        ],
      ),
    );
  }
}

// ---------- сколько времени (электронные часы, устно) ----------

class ClockExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  const ClockExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<ClockExercise> createState() => _ClockExerciseState();
}

class _ClockExerciseState extends State<ClockExercise> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final time = (widget.item['time'] ?? '').toString();
    final answer = (widget.item['answer'] ?? '').toString();
    return ExerciseScaffold(
      prompt: 'Сколько времени?',
      tts: widget.tts,
      solved: true, // самооценка: «Дальше» доступно всегда
      hint: _revealed ? answer : 'Скажите вслух, потом проверьте',
      onNext: () => widget.onResult(
          const StepOutcome(correct: true, unaided: true, gradeable: false)),
      child: Column(
        children: [
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 24, horizontal: 36),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(time,
                  style: const TextStyle(
                      fontSize: 84,
                      color: Color(0xFF7CFFB2),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4)),
            ),
          ),
          const SizedBox(height: 20),
          if (!_revealed)
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _revealed = true);
                widget.tts.speak(answer);
              },
              icon: const Icon(Icons.check),
              label: const Text('Показать ответ'),
            )
          else
            Text(answer,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, color: Colors.green.shade800)),
        ],
      ),
    );
  }
}

// ---------- ударение: нажать ударную гласную ----------

const _vowels = 'аеёиоуыэюяАЕЁИОУЫЭЮЯ';

class StressExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final bool errorless;
  const StressExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.errorless = false});
  @override
  State<StressExercise> createState() => _StressExerciseState();
}

class _StressExerciseState extends State<StressExercise> {
  late final String _word; // слово без знака ударения
  late final int _stress; // индекс ударной гласной в _word (-1 если не нашли)
  late final String _note; // значение из скобок промпта (для гомографов)
  int? _wrongPick;
  int _wrongCount = 0;
  bool _solved = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    // выводим слово и позицию ударения из answer (комбинирующий акут U+0301 / ё)
    const accent = '́'; // комбинирующий акут
    final raw = (widget.item['answer'] ?? '').toString();
    final sb = StringBuffer();
    int stress = -1;
    for (final ch in raw.split('')) {
      if (ch == accent) {
        stress = sb.length - 1; // ударная — предыдущая гласная
      } else {
        sb.write(ch);
      }
    }
    _word = sb.toString();
    if (stress < 0) {
      final yo = _word.indexOf('ё');
      if (yo >= 0) {
        stress = yo; // ё всегда ударная
      } else {
        // единственная гласная — она и ударная
        final idxs = [
          for (var i = 0; i < _word.length; i++)
            if (_vowels.contains(_word[i])) i
        ];
        if (idxs.length == 1) stress = idxs.first;
      }
    }
    _stress = stress;
    final m = RegExp(r'\(([^)]*)\)').firstMatch(
        (widget.item['prompt'] ?? '').toString());
    _note = m != null ? m.group(1)!.trim() : '';

    if (widget.errorless) {
      _solved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_word.isNotEmpty) widget.tts.speak('Ударение здесь. $_word');
      });
    }
  }

  void _tap(int i) {
    if (_solved) return;
    if (i == _stress) {
      setState(() => _solved = true);
      widget.tts.speak(_word);
    } else {
      setState(() {
        _wrongPick = i;
        _wrongCount++;
      });
    }
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    return StepOutcome(
      correct: !_revealed,
      unaided: !_revealed && _wrongCount == 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = _solved
        ? (_revealed ? 'Ударение показано' : 'Верно!')
        : (_wrongPick != null
            ? 'Не здесь — попробуйте ещё раз'
            : 'Нажмите ударную гласную');
    return ExerciseScaffold(
      prompt: _note.isEmpty
          ? 'На какую букву падает ударение?'
          : 'На какую букву падает ударение?\nЗначение: $_note',
      tts: widget.tts,
      solved: _solved,
      hint: hint,
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _word.length; i++)
                _Tile(
                  ch: _word[i],
                  vowel: _vowels.contains(_word[i]),
                  correct: _solved && i == _stress,
                  wrong: _wrongPick == i,
                  onTap: _vowels.contains(_word[i]) ? () => _tap(i) : null,
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (!_solved)
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _revealed = true;
                  _solved = true;
                });
                widget.tts.speak(_word);
              },
              child: const Text('Не знаю'),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String ch;
  final bool vowel;
  final bool correct;
  final bool wrong;
  final VoidCallback? onTap;
  const _Tile(
      {required this.ch,
      required this.vowel,
      required this.correct,
      required this.wrong,
      this.onTap});
  @override
  Widget build(BuildContext context) {
    final bg = correct
        ? Colors.green.shade300
        : (wrong ? Colors.orange.shade200 : (vowel ? Colors.blue.shade50 : null));
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: vowel ? Border.all(color: Colors.blue.shade200, width: 2) : null,
        ),
        child: Text(ch,
            style: TextStyle(
                fontSize: 38,
                fontWeight: vowel ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

// ---------- слухоречевая память ----------

class MemoryExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  const MemoryExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<MemoryExercise> createState() => _MemoryExerciseState();
}

class _MemoryExerciseState extends State<MemoryExercise> {
  bool _played = false;
  bool _shown = false;

  List<String> get _row =>
      ((widget.item['row'] as List?) ?? const []).map((e) => e.toString()).toList();

  /// Для показа: цифры — прописью «5 (пять)» (если есть display), иначе как есть.
  List<String> get _shownWords {
    final disp = widget.item['display'];
    if (disp is List) return disp.map((e) => e.toString()).toList();
    return _row;
  }

  void _play() {
    widget.tts.speak(_row.join(', '));
    setState(() => _played = true);
  }

  @override
  Widget build(BuildContext context) {
    return ExerciseScaffold(
      prompt: 'Послушайте и повторите вслух',
      tts: widget.tts,
      solved: _played,
      hint: _played ? 'Повторите ряд вслух' : 'Нажмите «Слушать»',
      nextLabel: 'Повторил',
      // самооценка — не влияет на адаптацию сложности
      onNext: () => widget.onResult(
          const StepOutcome(correct: true, unaided: true, gradeable: false)),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _play,
            icon: const Icon(Icons.volume_up),
            label: Text(_played ? 'Послушать ещё раз' : 'Слушать'),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => setState(() => _shown = !_shown),
            child: Text(_shown ? 'Скрыть слова' : 'Показать слова',
                style: const TextStyle(fontSize: 18)),
          ),
          if (_shown)
            Text(_shownWords.join('  ·  '),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24)),
        ],
      ),
    );
  }
}

// ---------- чтение → вопросы → пересказ ----------

class ReadingExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  const ReadingExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<ReadingExercise> createState() => _ReadingExerciseState();
}

class _ReadingExerciseState extends State<ReadingExercise> {
  int _phase = 0; // 0 чтение, 1 вопросы, 2 пересказ
  final Set<int> _revealed = {};

  // самооценка пересказа — не влияет на адаптацию сложности
  static const _selfReport =
      StepOutcome(correct: true, unaided: true, gradeable: false);

  @override
  Widget build(BuildContext context) {
    final title = (widget.item['title'] ?? '').toString();
    final text = (widget.item['text'] ?? '').toString();
    final allQuestions = ((widget.item['questions'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    // на нижнем уровне — меньше вопросов (старт с малого)
    final level = (widget.item['level'] ?? 1) as int;
    final questions = allQuestions
        .take(level >= 3 ? allQuestions.length : (level == 2 ? 3 : 2))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title.isNotEmpty)
                  Text(title,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_phase == 0) ...[
                  Text(text,
                      style: const TextStyle(fontSize: 24, height: 1.4)),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: () => widget.tts.speak(text),
                    icon: const Icon(Icons.volume_up),
                    label: const Text('Прочитать вслух'),
                  ),
                ],
                if (_phase == 1) ...[
                  const Text('Ответьте на вопросы:',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  for (int i = 0; i < questions.length; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      (questions[i]['q'] ?? '').toString(),
                                      style: const TextStyle(fontSize: 22)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.volume_up),
                                  onPressed: () => widget.tts.speak(
                                      (questions[i]['q'] ?? '').toString()),
                                ),
                              ],
                            ),
                            if (_revealed.contains(i))
                              Text((questions[i]['a'] ?? '').toString(),
                                  style: TextStyle(
                                      fontSize: 20,
                                      color: Colors.green.shade800))
                            else
                              TextButton(
                                onPressed: () =>
                                    setState(() => _revealed.add(i)),
                                child: const Text('Показать ответ',
                                    style: TextStyle(fontSize: 18)),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (_phase == 2) ...[
                  const Text('Перескажите текст своими словами.',
                      style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 10),
                  const Text('Помощник отмечает результат:',
                      style:
                          TextStyle(fontSize: 18, color: Colors.black54)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_phase == 0)
          ElevatedButton(
              onPressed: () => setState(() => _phase = 1),
              child: const Text('Дальше')),
        if (_phase == 1)
          // пересказ (связная речь) — только на верхнем уровне; ниже заканчиваем после вопросов
          ElevatedButton(
              onPressed: level >= 3
                  ? () => setState(() => _phase = 2)
                  : () => widget.onResult(_selfReport),
              child: Text(level >= 3 ? 'Перейти к пересказу' : 'Готово')),
        if (_phase == 2)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  onPressed: () => widget.onResult(_selfReport),
                  child: const Text('Получилось'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  // вернуться к тексту и перечитать заново
                  onPressed: () => setState(() {
                    _phase = 0;
                    _revealed.clear();
                  }),
                  child: const Text('Ещё раз'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ---------- соединение пар (слово↔действие / синонимы / буква↔слово) ----------

class MatchPairsExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  final bool errorless;
  const MatchPairsExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult,
      this.errorless = false});
  @override
  State<MatchPairsExercise> createState() => _MatchPairsExerciseState();
}

class _MatchPairsExerciseState extends State<MatchPairsExercise> {
  // пары в порядке контента; left — якорь (слово/слово-с-пропуском), right — ответ
  late final List<Map<String, String>> _pairs =
      ((widget.item['pairs'] as List?) ?? const [])
          .map((e) => {
                'left': (e['left'] ?? '').toString(),
                'right': (e['right'] ?? '').toString(),
              })
          .toList();
  // правый столбец перемешан, идентичность по индексу (значения могут повторяться)
  late final List<String> _rights =
      _pairs.map((p) => p['right']!).toList()..shuffle();

  int? _selLeft; // выбранная строка слева (ждёт пары справа)
  final Map<int, int> _link = {}; // left-index -> right-index (зафиксировано)
  int? _wrongRight; // правый индекс с неверной попыткой (подсветка)
  int _wrongCount = 0;
  bool get _solved => _link.length == _pairs.length;

  @override
  void initState() {
    super.initState();
    if (widget.errorless) {
      _solveAll();
    }
  }

  // соединить все пары верно (errorless-пол) без подсчёта ошибок
  void _solveAll() {
    for (var li = 0; li < _pairs.length; li++) {
      if (_link.containsKey(li)) continue;
      final want = _pairs[li]['right'];
      for (var ri = 0; ri < _rights.length; ri++) {
        if (_rights[ri] == want && !_link.containsValue(ri)) {
          _link[li] = ri;
          break;
        }
      }
    }
  }

  void _tapLeft(int li) {
    if (_solved || _link.containsKey(li)) return;
    setState(() {
      _selLeft = li;
      _wrongRight = null;
    });
    widget.tts.speak(_pairs[li]['left']!);
  }

  void _tapRight(int ri) {
    if (_solved || _link.containsValue(ri)) return;
    if (_selLeft == null) {
      // подсказываем порядок действий: сначала слово слева
      widget.tts.speak('Сначала выберите слово слева');
      return;
    }
    final li = _selLeft!;
    if (_pairs[li]['right'] == _rights[ri]) {
      setState(() {
        _link[li] = ri;
        _selLeft = null;
        _wrongRight = null;
      });
      widget.tts.speak('${_pairs[li]['left']} — ${_rights[ri]}');
    } else {
      setState(() {
        _wrongRight = ri;
        _wrongCount++;
      });
      widget.tts.speak(_rights[ri]);
    }
  }

  StepOutcome _outcome() {
    if (widget.errorless) {
      return const StepOutcome(correct: true, unaided: false, gradeable: false);
    }
    // соединить можно только верно (неверное не фиксируется) → выполнено = верно;
    // без ошибочных нажатий = самостоятельно
    return StepOutcome(correct: true, unaided: _wrongCount == 0);
  }

  Widget _tile(String text,
      {required Color color, required bool selected, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? Colors.blue.shade700 : Colors.blue.shade200,
                width: selected ? 3 : 2),
          ),
          child: Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompt =
        (widget.item['prompt'] ?? 'Соедините пары').toString();
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      solved: _solved,
      hint: _solved
          ? 'Готово!'
          : (_selLeft == null
              ? 'Нажмите слово слева, потом подходящее справа'
              : (_wrongRight != null
                  ? 'Не подходит — попробуйте другое'
                  : 'Теперь выберите подходящее справа')),
      onNext: () => widget.onResult(_outcome()),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                for (var li = 0; li < _pairs.length; li++)
                  _tile(
                    _pairs[li]['left']!,
                    selected: _selLeft == li,
                    color: _link.containsKey(li)
                        ? Colors.green.shade100
                        : (_selLeft == li
                            ? Colors.blue.shade100
                            : Colors.blue.shade50),
                    onTap: () => _tapLeft(li),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                for (var ri = 0; ri < _rights.length; ri++)
                  _tile(
                    _rights[ri],
                    selected: false,
                    color: _link.containsValue(ri)
                        ? Colors.green.shade100
                        : (_wrongRight == ri
                            ? Colors.orange.shade200
                            : Colors.blue.shade50),
                    onTap: () => _tapRight(ri),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- автоматизированные ряды (растормаживание непроизвольной речи) ----------

class SeriesExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(StepOutcome) onResult;
  const SeriesExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<SeriesExercise> createState() => _SeriesExerciseState();
}

class _SeriesExerciseState extends State<SeriesExercise> {
  late final List<String> _full = ((widget.item['items'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();
  late final int _shown = () {
    final s = (widget.item['start'] as num?)?.toInt() ?? 3;
    return s.clamp(1, _full.isEmpty ? 1 : _full.length);
  }();
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    // озвучиваем начало ряда — задаём «разгон» автоматизированной речи
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final head = _full.take(_shown).join(', ');
      if (head.isNotEmpty) widget.tts.speak('$head …');
    });
  }

  void _reveal() {
    setState(() => _revealed = true);
    widget.tts.speak(_full.join(', '));
  }

  Widget _chip(String text, {required bool faded}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: faded ? Colors.grey.shade200 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200, width: 2),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 26,
              color: faded ? Colors.grey.shade500 : Colors.black87)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prompt = (widget.item['prompt'] ??
            'Продолжите ряд вслух, потом нажмите «Показать ряд»')
        .toString();
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      solved: _revealed,
      hint: _revealed
          ? 'Молодец! Назвали ряд'
          : 'Произнесите ряд вслух до конца, затем проверьте себя',
      onNext: () => widget.onResult(
          const StepOutcome(correct: true, unaided: false, gradeable: false)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _full.length; i++)
                if (i < _shown || _revealed)
                  _chip(_full[i], faded: i >= _shown)
                else if (i == _shown)
                  _chip('…', faded: true),
            ],
          ),
          const SizedBox(height: 18),
          if (!_revealed)
            ElevatedButton.icon(
              onPressed: _reveal,
              icon: const Icon(Icons.visibility),
              label: const Text('Показать ряд'),
            ),
        ],
      ),
    );
  }
}
