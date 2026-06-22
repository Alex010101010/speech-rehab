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
  late final SessionBuilder _builder;
  late List<SessionSlot> _plan; // первый проход (слоты, задания подбираются по ходу)
  final List<SessionStep> _missed = []; // пропущенное/неверное — в блок «Повторим»
  final Set<Object> _usedItems = {}; // чтобы задания не повторялись в сессии

  // Адаптивная лестница: единый рабочий уровень, серии для шага вверх/вниз.
  int _workingLevel = 1;
  int _upStreak = 0; // подряд верных самостоятельно
  int _downStreak = 0; // подряд ошибок
  bool _errorlessNext = false; // следующий core-шаг показать безошибочно (пол)

  int _i = 0; // индекс в плане (первый проход)
  int _ri = 0; // индекс в повторе
  int _correct = 0;
  bool _reviewing = false;
  bool _done = false;
  late SessionStep _current; // текущий шаг первого прохода
  bool _errorlessCurrent = false;
  List<String> _newAch = const [];

  @override
  void initState() {
    super.initState();
    _builder = SessionBuilder(widget.repo);
    _plan = _builder.buildPlan();
    _workingLevel = widget.store.progress.level;
    if (_plan.isEmpty) {
      _done = true;
    } else {
      _resolve();
    }
  }

  /// Подобрать конкретное задание для текущего слота под рабочий уровень.
  void _resolve() {
    final slot = _plan[_i];
    final lvl = slot.fixedEasy ? 1 : _workingLevel;
    final item = _builder.pickItem(slot.type, lvl, _usedItems);
    if (item.isNotEmpty) _usedItems.add(item);
    final m = renderModeFor(slot.type);
    final canErrorless = m == RenderMode.choice || m == RenderMode.typed;
    _errorlessCurrent =
        _errorlessNext && slot.role == 'core' && canErrorless;
    _errorlessNext = false;
    _current = SessionStep(slot.type, _builder.titleFor(slot.type), item, slot.role);
  }

  /// Лестница реагирует только на ядро (core): вниз быстро (2 ошибки подряд),
  /// вверх осторожно (3 верных самостоятельно подряд). На полу — errorless.
  void _applyStaircase(StepOutcome o) {
    if (!o.gradeable || _plan[_i].role != 'core') return;
    if (o.correct && o.unaided) {
      _upStreak++;
      _downStreak = 0;
      if (_upStreak >= 3 && _workingLevel < 3) {
        _workingLevel++;
        _upStreak = 0;
      }
    } else {
      _downStreak++;
      _upStreak = 0;
      if (_downStreak >= 2) {
        if (_workingLevel > 1) {
          _workingLevel--;
          _downStreak = 0;
        } else {
          _errorlessNext = true; // ниже некуда — поддержим безошибочным шагом
        }
      }
    }
  }

  // длина блока «Повторим» ограничена — чтобы не утомлять длинным хвостом
  int get _reviewCount => _missed.length > 3 ? 3 : _missed.length;

  void _onOutcome(StepOutcome o) {
    if (_reviewing) {
      if (_ri + 1 >= _reviewCount) {
        _finish();
      } else {
        setState(() => _ri++);
      }
      return;
    }
    if (o.correct) {
      _correct++;
    } else {
      _missed.add(_current);
    }
    _applyStaircase(o);
    if (_i + 1 >= _plan.length) {
      if (_missed.isNotEmpty) {
        setState(() {
          _reviewing = true;
          _ri = 0;
        });
      } else {
        _finish();
      }
    } else {
      setState(() {
        _i++;
        _resolve();
      });
    }
  }

  /// Сохранить прогресс. При досрочном выходе считаем по реально сделанным
  /// заданиям первого прохода, а не по всему плану.
  Future<void> _persist({required bool early}) async {
    final p = widget.store.progress;
    final answered = (early && !_reviewing) ? _i : _plan.length;
    p.sessions += 1;
    p.answered += answered;
    p.correct += _correct;
    final now = DateTime.now();
    p.days.add(
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    // Лестница: следующий заход начинаем с уровня, на котором остановились.
    p.level = _workingLevel;
    _newAch = updateAchievements(p);
    await widget.store.save();
  }

  Future<void> _finish() async {
    await _persist(early: false);
    widget.tts.speak('Молодец! Занятие окончено.');
    if (mounted) setState(() => _done = true);
  }

  /// «Отдохнуть»: сохранить сделанное и выйти на главный (без экрана «Молодец»).
  Future<void> _rest() async {
    if (_i > 0 || _reviewing) await _persist(early: true);
    if (mounted) Navigator.pop(context);
  }

  Widget _render(SessionStep step) {
    final key = ValueKey('${_reviewing ? 'r$_ri' : 'p$_i'}');
    final errorless = !_reviewing && _errorlessCurrent;
    switch (step.mode) {
      case RenderMode.choice:
        return ChoiceExercise(
            key: key,
            item: step.item,
            tts: widget.tts,
            onResult: _onOutcome,
            type: step.type,
            errorless: errorless);
      case RenderMode.memory:
        return MemoryExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
      case RenderMode.reading:
        return ReadingExercise(
            key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
      default:
        return TypedExercise(
            key: key,
            item: step.item,
            tts: widget.tts,
            onResult: _onOutcome,
            type: step.type,
            errorless: errorless);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _DoneView(newAch: _newAch);
    final step = _reviewing ? _missed[_ri] : _current;
    final total = _reviewing ? _reviewCount : _plan.length;
    final idx = _reviewing ? _ri : _i;
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _reviewing
                ? 'Повторим • ${idx + 1} из $total'
                : '${idx + 1} из $total',
            style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(
            onPressed: () => _onOutcome(
                const StepOutcome(correct: false, unaided: false, gradeable: false)),
            child: const Text('Пропустить', style: TextStyle(fontSize: 18)),
          ),
          TextButton(
            onPressed: _rest,
            child: const Text('Отдохнуть', style: TextStyle(fontSize: 18)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (idx + 1) / total),
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
