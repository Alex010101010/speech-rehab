import 'package:flutter/material.dart';
import '../engine/tts_service.dart';
import '../models/exercise.dart';

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
    default:
      return p;
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
  final String? imagePath; // картинка-подсказка (если есть)
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
    this.imagePath,
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
                if (imagePath != null) ...[
                  Center(
                    child: Image.asset(imagePath!,
                        height: 200,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
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
                Text(hint,
                    style: TextStyle(
                        fontSize: 20,
                        color: solved
                            ? Colors.green.shade800
                            : Colors.black54)),
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

  List<String> get _options => ((widget.item['options'] as List?) ?? const [])
      .map((e) => e.toString())
      .toList();

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
      imagePath: img.isEmpty ? null : 'assets/content/img/$img',
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
  int _tries = 0;
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
    final ans = (widget.item['answer'] ?? '').toString();
    if (ans.isEmpty) return;
    setState(() {
      _hintUsed = true;
      _hint = 'Подсказка: начинается на «${ans[0]}»';
    });
    widget.tts.speak('Начинается на ${ans[0]}');
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
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      imagePath: img.isEmpty ? null : 'assets/content/img/$img',
      emoji: emoji.isEmpty ? null : emoji,
      hint: _hint,
      solved: _solved,
      onNext: () => widget.onResult(_outcome()),
      child: Column(
        children: [
          TextField(
            controller: _c,
            enabled: !_solved,
            style: const TextStyle(fontSize: 26),
            decoration: const InputDecoration(border: OutlineInputBorder()),
            textInputAction: TextInputAction.done,
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
