import 'package:flutter/material.dart';
import '../engine/tts_service.dart';

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

// ---------- общий каркас задания ----------

class ExerciseScaffold extends StatelessWidget {
  final String prompt;
  final Widget child;
  final String hint;
  final bool solved;
  final VoidCallback onNext;
  final TtsService tts;
  final String nextLabel;
  const ExerciseScaffold({
    super.key,
    required this.prompt,
    required this.child,
    required this.hint,
    required this.solved,
    required this.onNext,
    required this.tts,
    this.nextLabel = 'Дальше',
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
  final void Function(bool) onResult;
  const ChoiceExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<ChoiceExercise> createState() => _ChoiceExerciseState();
}

class _ChoiceExerciseState extends State<ChoiceExercise> {
  String? _wrongPick;
  bool _solved = false;

  bool _isCorrect(String o) =>
      checkTyped(widget.item, o) ||
      normalize(o) == normalize((widget.item['answer'] ?? '').toString());

  @override
  Widget build(BuildContext context) {
    final prompt = (widget.item['prompt'] ?? '').toString();
    final options = ((widget.item['options'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      solved: _solved,
      hint: _solved
          ? 'Верно!'
          : (_wrongPick != null ? 'Попробуйте ещё раз' : 'Выберите ответ'),
      onNext: () => widget.onResult(true),
      child: Column(
        children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _solved && _isCorrect(o)
                      ? Colors.green.shade100
                      : (_wrongPick == o ? Colors.orange.shade100 : null),
                ),
                onPressed: _solved
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
        ],
      ),
    );
  }
}

// ---------- ввод текста ----------

class TypedExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(bool) onResult;
  const TypedExercise(
      {super.key,
      required this.item,
      required this.tts,
      required this.onResult});
  @override
  State<TypedExercise> createState() => _TypedExerciseState();
}

class _TypedExerciseState extends State<TypedExercise> {
  final _c = TextEditingController();
  bool _solved = false;
  bool _revealed = false;
  int _tries = 0;
  String _hint = 'Напишите ответ';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _check() {
    if (checkTyped(widget.item, _c.text)) {
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

  @override
  Widget build(BuildContext context) {
    final prompt = (widget.item['prompt'] ?? '').toString();
    return ExerciseScaffold(
      prompt: prompt,
      tts: widget.tts,
      hint: _hint,
      solved: _solved,
      onNext: () => widget.onResult(!_revealed),
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
            ElevatedButton(onPressed: _check, child: const Text('Проверить')),
        ],
      ),
    );
  }
}

// ---------- слухоречевая память ----------

class MemoryExercise extends StatefulWidget {
  final Map<String, dynamic> item;
  final TtsService tts;
  final void Function(bool) onResult;
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
      onNext: () => widget.onResult(true),
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
            Text(_row.join('  ·  '),
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
  final void Function(bool) onResult;
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

  @override
  Widget build(BuildContext context) {
    final title = (widget.item['title'] ?? '').toString();
    final text = (widget.item['text'] ?? '').toString();
    final questions = ((widget.item['questions'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
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
          ElevatedButton(
              onPressed: () => setState(() => _phase = 2),
              child: const Text('Перейти к пересказу')),
        if (_phase == 2)
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white),
                  onPressed: () => widget.onResult(true),
                  child: const Text('Получилось'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => widget.onResult(true),
                  child: const Text('Ещё раз'),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
