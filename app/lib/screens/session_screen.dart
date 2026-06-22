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

  // Адаптивная лестница НА КАЖДЫЙ НАВЫК (тип задания).
  final Map<String, int> _skill = {}; // тип -> рабочий уровень
  final Map<String, int> _up = {}; // серии верных самостоятельно по типу
  final Map<String, int> _down = {}; // серии ошибок по типу
  final Set<String> _errorlessTypes = {}; // типам: след. core-шаг безошибочно

  // уровень навыка с ленивым засевом из сохранёнки (или старого общего level)
  int _levelFor(String t) => _skill[t] ??=
      (widget.store.progress.skillLevels[t] ?? widget.store.progress.level);

  Map<String, int> get _mergedLevels =>
      Map<String, int>.from(widget.store.progress.skillLevels)..addAll(_skill);

  // «общий» уровень (среднее по навыкам) — для памяти/чтения и экрана
  int get _overallLevel {
    final v = _mergedLevels.values;
    if (v.isEmpty) return widget.store.progress.level;
    return (v.reduce((a, b) => a + b) / v.length).round().clamp(1, 3);
  }

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
    if (_plan.isEmpty) {
      _done = true;
    } else {
      _resolve();
    }
  }

  /// Подобрать конкретное задание для текущего слота под уровень навыка.
  void _resolve() {
    final slot = _plan[_i];
    // core — по уровню своего навыка; память/чтение — по общему; разминка/финал — 1
    final lvl = slot.fixedEasy
        ? 1
        : (slot.role == 'core' ? _levelFor(slot.type) : _overallLevel);
    final item = _builder.pickItem(slot.type, lvl, _usedItems);
    if (item.isNotEmpty) _usedItems.add(item);
    final m = renderModeFor(slot.type);
    final canErrorless = m == RenderMode.choice || m == RenderMode.typed;
    _errorlessCurrent =
        slot.role == 'core' && canErrorless && _errorlessTypes.remove(slot.type);
    _current = SessionStep(slot.type, _builder.titleFor(slot.type), item, slot.role);
  }

  /// Лестница на навык: вниз быстро (2 ошибки подряд), вверх осторожно
  /// (3 верных самостоятельно подряд). На полу навыка — errorless.
  void _applyStaircase(StepOutcome o) {
    final slot = _plan[_i];
    if (!o.gradeable || slot.role != 'core') return;
    final t = slot.type;
    final cur = _levelFor(t);
    if (o.correct && o.unaided) {
      _up[t] = (_up[t] ?? 0) + 1;
      _down[t] = 0;
      if (_up[t]! >= 3 && cur < 3) {
        _skill[t] = cur + 1;
        _up[t] = 0;
      }
    } else {
      _down[t] = (_down[t] ?? 0) + 1;
      _up[t] = 0;
      if (_down[t]! >= 2) {
        if (cur > 1) {
          _skill[t] = cur - 1;
          _down[t] = 0;
        } else {
          _errorlessTypes.add(t); // ниже некуда — поддержим безошибочным шагом
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
    // Лестница: сохраняем уровни навыков; общий level — среднее (для экрана/наград).
    p.skillLevels = _mergedLevels;
    p.level = _overallLevel;
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
    if (step.type == 'find_error') {
      return FixErrorExercise(
          key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
    }
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
