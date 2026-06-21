import 'package:flutter/material.dart';
import '../data/content_repository.dart';
import '../engine/progress_store.dart';
import '../engine/tts_service.dart';
import '../engine/session_builder.dart';
import '../engine/achievements.dart';
import '../models/exercise.dart';
import '../widgets/exercises.dart';

class SessionScreen extends StatefulWidget {
  final ContentRepository repo;
  final ProgressStore store;
  final TtsService tts;
  const SessionScreen(
      {super.key,
      required this.repo,
      required this.store,
      required this.tts});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late List<SessionStep> _steps;
  int _i = 0;
  int _correct = 0;
  bool _done = false;
  List<String> _newAch = const [];

  @override
  void initState() {
    super.initState();
    _steps = SessionBuilder(widget.repo).build(widget.store.progress.level);
    if (_steps.isEmpty) _done = true;
  }

  void _onResult(bool ok) {
    if (ok) _correct++;
    if (_i + 1 >= _steps.length) {
      _finish();
    } else {
      setState(() => _i++);
    }
  }

  Future<void> _finish() async {
    final p = widget.store.progress;
    p.sessions += 1;
    p.answered += _steps.length;
    p.correct += _correct;
    final now = DateTime.now();
    p.days.add(
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    p.level = p.sessions >= 10 ? 3 : (p.sessions >= 4 ? 2 : 1);
    _newAch = updateAchievements(p);
    await widget.store.save();
    widget.tts.speak('Молодец! Занятие окончено.');
    if (mounted) setState(() => _done = true);
  }

  Widget _render(SessionStep step) {
    final key = ValueKey(_i);
    switch (step.mode) {
      case RenderMode.choice:
        return ChoiceExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onResult);
      case RenderMode.memory:
        return MemoryExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onResult);
      case RenderMode.reading:
        return ReadingExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onResult);
      default:
        return TypedExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onResult);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _DoneView(newAch: _newAch);
    final step = _steps[_i];
    return Scaffold(
      appBar: AppBar(
        title: Text('${_i + 1} из ${_steps.length}',
            style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отдохнуть', style: TextStyle(fontSize: 18)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_i + 1) / _steps.length),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _render(step),
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final List<String> newAch;
  const _DoneView({required this.newAch});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('🎉',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 80)),
              const Text('Молодец!',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Занятие окончено.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22)),
              if (newAch.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Новая награда:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                ...newAch.map((a) => Text('🏅 ${achievementTitle(a)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22))),
              ],
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
