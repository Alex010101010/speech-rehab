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
  late List<SessionSlot> _plan; // план сессии (слоты, задания подбираются по ходу)
  final Set<Object> _usedItems = {}; // чтобы задания не повторялись в сессии

  // Интервальное повторение (spaced retrieval). Рабочая копия расписания
  // (id задания -> карточка); пишется в прогресс при сохранении. Повторяем
  // только то, что вспомнили САМИ — не неуспешное (без негативной концовки).
  final DateTime _today = DateTime.now();
  late final Map<String, ReviewCard> _review = {
    for (final e in widget.store.progress.review.entries)
      e.key: ReviewCard(type: e.value.type, box: e.value.box, due: e.value.due),
  };
  static const _reviewCap = 3; // межсессионных повторов («Вспомним») за сессию

  // Повтор «сегодня» (первый шаг лесенки, внутри этой же сессии): свежевыученные
  // самостоятельно задания переигрываются мини-блоком «Закрепим» перед финалом.
  // Отдельный лимит — НЕ из пула «Вспомним», чтобы не утомлять (лёгкий: 6+2+3).
  final List<SessionStep> _todayQueue = [];
  bool _sameDayInserted = false;
  static const _sameDayCap = 2;

  // Адаптивная лестница НА КАЖДЫЙ НАВЫК (тип задания).
  final Map<String, int> _skill = {}; // тип -> рабочий уровень
  final Map<String, int> _up = {}; // серии верных самостоятельно по типу
  final Map<String, int> _down = {}; // серии ошибок по типу
  final Set<String> _errorlessTypes = {}; // типам: след. core-шаг безошибочно

  // «Мягкий выход» из лёгкого режима: копим безошибочные узнавания по навыку,
  // на пороге — одна «проба» на реальном уровне; повышаем только если прошёл
  // её сам. Переживают сессии (зеркало progress.readyStreak/probeFails).
  late final Map<String, int> _ready =
      Map<String, int>.from(widget.store.progress.readyStreak);
  late final Map<String, int> _pfail =
      Map<String, int>.from(widget.store.progress.probeFails);
  static const _probeThreshold = 6; // узнаваний до пробы (≈ раз в несколько сессий)
  static const _maxProbeFails = 2; // провалов подряд → мягкий откат (копим заново)
  String? _probeSkill; // навык, поданный пробой на текущем шаге (иначе null)
  bool _probedThisSession = false; // не больше одной пробы за сессию

  // Навыки на слово/смысл, у которых есть до-вербальный пол L0 (картинка→слово).
  static const _picturable = {
    'name_by_description',
    'fill_letter',
    'generalization',
    'synonyms_antonyms',
  };
  bool _isPicturable(String t) => _picturable.contains(t);
  bool get _pictureMode => widget.store.progress.pictureMode;

  // Floor-типы узнавания: их успех НЕ поднимает рабочий уровень и не входит в
  // средний — иначе лёгкие задания быстро выводят пациента из лёгкого трека.
  static const _recognitionFloor = {
    'picture_word',
    'yesno_picture',
    'syllables',
    'match_pairs',
    'auto_series',
  };

  // Фонологические типы (звуко-буквенная форма, не смысл). В повторении показываем
  // их errorless: усиленное доставание звуковой формы рискует закрепить ошибку —
  // на фонологическом уровне errorless не уступает retrieval practice (ревью 28.06).
  static const _phonological = {'fill_letter', 'syllables', 'stress', 'anagram'};

  // Лёгкий режим: на низком общем уровне сессия короче и без печати (только
  // касание/выбор). Авто — не требует действий настройщика; отключается сам,
  // когда пациент дорастает до L2.
  bool get _lightMode => !_pictureMode && _overallLevel <= 1;

  // уровень навыка с ленивым засевом из сохранёнки (или старого общего level)
  int _levelFor(String t) => _skill[t] ??=
      (widget.store.progress.skillLevels[t] ?? widget.store.progress.level);

  Map<String, int> get _mergedLevels =>
      Map<String, int>.from(widget.store.progress.skillLevels)..addAll(_skill);

  // «общий» уровень (среднее по навыкам) — для памяти/чтения и экрана.
  // Floor-типы узнавания исключены: успех в узнавании не должен поднимать уровень.
  int get _overallLevel {
    final v = _mergedLevels.entries
        .where((e) => !_recognitionFloor.contains(e.key))
        .map((e) => e.value)
        .toList();
    if (v.isEmpty) return widget.store.progress.level;
    return (v.reduce((a, b) => a + b) / v.length).round().clamp(1, 3);
  }

  int _i = 0; // индекс в плане
  int _correct = 0;
  // глубина подсказки по называнию (name_by_description) за сессию — метрика
  // восстановления для отчёта логопеду (средняя ступень должна падать со временем)
  int _nameCueSum = 0;
  int _nameCueN = 0;
  bool _done = false;
  late SessionStep _current; // текущий шаг первого прохода
  bool _errorlessCurrent = false;
  bool _useL0Current = false; // текущий шаг отдан как L0-узнавание (не повышаем уровень)
  List<String> _newAch = const [];

  @override
  void initState() {
    super.initState();
    _builder = SessionBuilder(widget.repo);
    _plan = _builder.buildPlan(pictureMode: _pictureMode, level: _overallLevel);
    // блок «Вспомним» (созревшие повторы) — сразу после разминки: тёплый вход
    // на успехе, а не наказание в конце. Сами задания резервируем, чтобы они
    // не выпали повторно как обычные.
    final reviews = _dueReviewSlots();
    if (_plan.isNotEmpty && reviews.isNotEmpty) {
      _plan.insertAll(1, reviews);
      for (final s in reviews) {
        if (s.fixedItem != null) _usedItems.add(s.fixedItem!);
      }
    }
    if (_plan.isEmpty) {
      _done = true;
    } else {
      _resolve();
    }
  }

  /// Созревшие карточки повторения (due ≤ сегодня), самые «просроченные» вперёд,
  /// не больше [_reviewCap]. Карточки на исчезнувший контент пропускаем.
  List<SessionSlot> _dueReviewSlots() {
    final todayStr = ReviewScheduler.dayStr(_today);
    final due = _review.entries
        .where((e) => e.value.due.compareTo(todayStr) <= 0)
        .toList()
      ..sort((a, b) => a.value.due.compareTo(b.value.due));
    final slots = <SessionSlot>[];
    for (final e in due) {
      if (slots.length >= _reviewCap) break;
      final item = _builder.itemById(e.value.type, e.key);
      if (item.isEmpty) continue;
      slots.add(SessionSlot(e.value.type, 'review', fixedItem: item));
    }
    return slots;
  }

  /// Блок «Закрепим» — повтор «сегодня»: до [_sameDayCap] заданий, выученных
  /// самостоятельно в этой же сессии. Бонусный шаг (не из пула «Вспомним»).
  List<SessionSlot> _sameDaySlots() => _todayQueue
      .take(_sameDayCap)
      .map((s) => SessionSlot(s.type, 'sameday', fixedItem: s.item))
      .toList();

  /// Подобрать конкретное задание для текущего слота под уровень навыка.
  void _resolve() {
    final slot = _plan[_i];
    // повтор (интервальное повторение): конкретное задание по id, на своём
    // уровне — это настоящая проверка припоминания, без errorless и без пробы
    if (slot.fixedItem != null) {
      _probeSkill = null;
      _useL0Current = false;
      // фонологические повторяем errorless (без риска закрепить ошибку),
      // остальные — настоящим тестом на припоминание
      _errorlessCurrent = _phonological.contains(slot.type);
      _current = SessionStep(
          slot.type, _builder.titleFor(slot.type), slot.fixedItem!, slot.role);
      return;
    }
    // core — по уровню своего навыка; память/чтение — по общему; разминка/финал — 1
    final lvl = slot.fixedEasy
        ? 1
        : (slot.role == 'core' ? _levelFor(slot.type) : _overallLevel);
    // навык, который СЕЙЧАС подавался бы узнаванием (L0): провал L1 (lvl==0)
    // или лёгкий режим. Картиночный режим — ручной, пробу там не даём.
    final wouldUseL0 = slot.role == 'core' &&
        _isPicturable(slot.type) &&
        !_pictureMode &&
        (lvl == 0 || _lightMode);
    // «Мягкий выход»: если навык накопил готовность (readyStreak ≥ порог) —
    // один раз за сессию подаём его на РЕАЛЬНОМ уровне (проба), а не узнаванием.
    // Повышаем только если пройдена самостоятельно (иначе застрял бы на L0).
    final pendingProbe = wouldUseL0 &&
        !_probedThisSession &&
        (_ready[slot.type] ?? 0) >= _probeThreshold;
    _probeSkill = pendingProbe ? slot.type : null;
    if (pendingProbe) _probedThisSession = true;
    // этаж L0: словарный core опускается до узнавания при провале L1 (lvl==0),
    // принудительно в картиночном режиме, а также в лёгком режиме (без печати)
    final useL0 = slot.role == 'core' &&
        _isPicturable(slot.type) &&
        !pendingProbe &&
        (_pictureMode || lvl == 0 || _lightMode);
    _useL0Current = useL0;
    final type = useL0 ? 'picture_word' : slot.type;
    final pickLevel = useL0 ? 0 : lvl;
    final item = _builder.pickItem(type, pickLevel, _usedItems);
    if (item.isNotEmpty) _usedItems.add(item);
    final m = renderModeFor(type);
    final canErrorless = useL0 ||
        m == RenderMode.choice ||
        m == RenderMode.typed ||
        type == 'yesno_picture' ||
        type == 'syllables' ||
        type == 'match_pairs' ||
        type == 'word_order' ||
        type == 'anagram';
    _errorlessCurrent =
        slot.role == 'core' && canErrorless && _errorlessTypes.remove(slot.type);
    if (pendingProbe) _errorlessCurrent = false; // проба — настоящий тест, не авто-решение
    _current = SessionStep(type, _builder.titleFor(type), item, slot.role);
  }

  /// Лестница на навык: вниз быстро (2 ошибки подряд), вверх осторожно
  /// (3 верных самостоятельно подряд). На полу навыка — errorless.
  void _applyStaircase(StepOutcome o) {
    final slot = _plan[_i];
    if (!o.gradeable || slot.role != 'core') return;
    final t = slot.type;
    final cur = _levelFor(t);
    final floor = _isPicturable(t) ? 0 : 1; // у словарных навыков пол — L0 (картинка)
    // в ручном картиночном режиме экран всё равно зафиксирован на L0 —
    // не двигаем уровни навыков (иначе при выключении режима они уедут в
    // текстовый трек завышенными по результатам узнавания), но errorless-
    // поддержку на повторных ошибках оставляем
    // успех на узнавании (L0-понижение или floor-тип) не повышает уровень —
    // иначе лёгкие задания быстро выводят из лёгкого трека
    final servedEasy = _useL0Current || _recognitionFloor.contains(t);
    if (o.correct && o.unaided) {
      _up[t] = (_up[t] ?? 0) + 1;
      _down[t] = 0;
      // безошибочное узнавание словарного навыка копит готовность к пробе
      // (не повышает уровень напрямую — повышение только через пройденную пробу)
      if (servedEasy && _isPicturable(t) && !_pictureMode) {
        final r = _ready[t] ?? 0;
        if (r < _probeThreshold) _ready[t] = r + 1;
      }
      if (!_pictureMode && !servedEasy && _up[t]! >= 3 && cur < 3) {
        _skill[t] = cur + 1;
        _up[t] = 0;
      }
    } else {
      _down[t] = (_down[t] ?? 0) + 1;
      _up[t] = 0;
      if (_down[t]! >= 2) {
        if (!_pictureMode && cur > floor) {
          _skill[t] = cur - 1;
          _down[t] = 0;
        } else {
          _errorlessTypes.add(t); // ниже некуда — поддержим безошибочным шагом
        }
      }
    }
  }

  /// Исход «пробы» (навык подан на реальном уровне в лёгком режиме).
  /// Прошёл сам → навык +1 (выход с пола). Провалил/пропустил → не готов:
  /// проба остаётся висеть на следующую сессию; после _maxProbeFails подряд —
  /// мягкий откат (копим готовность заново).
  void _applyProbe(StepOutcome o) {
    final t = _probeSkill!;
    if (o.correct && o.unaided) {
      final cur = _levelFor(t);
      if (cur < 3) _skill[t] = cur + 1;
      _ready[t] = 0;
      _pfail[t] = 0;
      _up[t] = 0;
      _down[t] = 0;
    } else {
      _pfail[t] = (_pfail[t] ?? 0) + 1;
      if (_pfail[t]! >= _maxProbeFails) {
        _ready[t] = 0; // откат: навык отдыхает и снова копит готовность
        _pfail[t] = 0;
      }
      // иначе readyStreak остаётся на пороге → проба повторится в след. сессии
    }
  }

  /// Засев в расписание повторения: задание, отвечённое САМОСТОЯТЕЛЬНО и верно,
  /// вернётся через растущие интервалы. Только core-шаги с объективной оценкой;
  /// уже стоящие на расписании не трогаем (ими управляет их карточка).
  void _maybeSeedReview(StepOutcome o, SessionSlot slot) {
    if (slot.role != 'core' || !o.gradeable || !o.correct || !o.unaided) return;
    final id = _current.item['id']?.toString();
    if (id == null || id.isEmpty || _review.containsKey(id)) return;
    _review[id] = ReviewCard(
      type: _current.type, // фактический тип (может быть picture_word при L0)
      box: 0,
      due: ReviewScheduler.dueAfter(_today, 0), // межсессионно — завтра (1д)
    );
    // и кандидат на повтор «сегодня» (бонусный внутрисессионный шаг лесенки)
    _todayQueue
        .add(SessionStep(_current.type, _current.title, _current.item, 'sameday'));
  }

  /// Исход повтора: вспомнил сам → дальше по интервалам (реже); не вспомнил →
  /// на коробку вниз (вернётся раньше, но НЕ в этой сессии — без «долбёжа»).
  void _applyReview(StepOutcome o) {
    final id = _current.item['id']?.toString();
    final card = id == null ? null : _review[id];
    if (card == null) return;
    // errorless-повтор (фонологический) — не тест, а выполненный разнесённый шаг:
    // двигаем дальше. Обычный повтор — дальше только если вспомнил сам.
    final recalled = o.correct && (o.unaided || !o.gradeable);
    card.box = ReviewScheduler.nextBox(card.box, recalled: recalled);
    card.due = ReviewScheduler.dueAfter(_today, card.box);
  }

  void _onOutcome(StepOutcome o) {
    widget.tts.stop(); // глушим незавершённую озвучку (длинный ряд) при уходе с задания
    if (o.correct) _correct++;
    final slot = _plan[_i];
    if (slot.role == 'review') {
      _applyReview(o);
    } else if (slot.role == 'sameday') {
      // повтор «сегодня» — бонусная внутрисессионная проверка, расписание не трогаем
    } else {
      if (_probeSkill != null) {
        _applyProbe(o); // у пробы своя логика повышения (ловит и пропуск)
      } else {
        _applyStaircase(o);
      }
      _maybeSeedReview(o, slot);
    }
    // лог глубины подсказки по называнию (печатный ввод; L0-узнавание исключаем)
    if (slot.role == 'core' &&
        _current.type == 'name_by_description' &&
        o.gradeable) {
      _nameCueSum += o.cueLevel;
      _nameCueN++;
    }
    // перед финалом (cooldown) один раз вставляем «Закрепим» — повтор сегодня
    if (!_sameDayInserted &&
        _i + 1 < _plan.length &&
        _plan[_i + 1].role == 'cooldown') {
      _sameDayInserted = true;
      final block = _sameDaySlots();
      if (block.isNotEmpty) _plan.insertAll(_i + 1, block);
    }
    if (_i + 1 >= _plan.length) {
      _finish();
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
    final answered = early ? _i : _plan.length;
    p.sessions += 1;
    p.answered += answered;
    p.correct += _correct;
    final now = DateTime.now();
    final dayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    p.days.add(dayStr);
    // Лестница: сохраняем уровни навыков; общий level — среднее (для экрана/наград).
    p.skillLevels = _mergedLevels;
    p.readyStreak = _ready;
    p.probeFails = _pfail;
    p.review = _review;
    p.level = _overallLevel;
    // снимок сессии для динамики в отчёте логопеду (храним последние 60)
    if (answered > 0) {
      p.history.add({
        'day': dayStr,
        'answered': answered,
        'correct': _correct,
        'level': _overallLevel,
        // глубина подсказки по называнию (для будущего отчёта); только если были
        if (_nameCueN > 0) 'nameCueSum': _nameCueSum,
        if (_nameCueN > 0) 'nameCueN': _nameCueN,
      });
      if (p.history.length > 60) {
        p.history.removeRange(0, p.history.length - 60);
      }
    }
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
    widget.tts.stop(); // глушим незавершённую озвучку при выходе из сессии
    if (_i > 0) await _persist(early: true);
    if (mounted) Navigator.pop(context);
  }

  Widget _render(SessionStep step) {
    final key = ValueKey('p$_i');
    final errorless = _errorlessCurrent;
    if (step.type == 'picture_word') {
      return PictureWordExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          errorless: errorless);
    }
    if (step.type == 'find_error') {
      return FixErrorExercise(
          key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
    }
    if (step.type == 'clock') {
      return ClockExercise(
          key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
    }
    if (step.type == 'stress') {
      return StressExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          errorless: errorless);
    }
    if (step.type == 'yesno_picture') {
      return YesNoPictureExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          errorless: errorless);
    }
    if (step.type == 'syllables') {
      return SyllablesExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          errorless: errorless);
    }
    if (step.type == 'match_pairs') {
      return MatchPairsExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          errorless: errorless);
    }
    if (step.type == 'auto_series') {
      return SeriesExercise(
          key: key, item: step.item, tts: widget.tts, onResult: _onOutcome);
    }
    if (step.type == 'word_order') {
      return OrderExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          sep: ' ',
          errorless: errorless);
    }
    if (step.type == 'anagram') {
      return OrderExercise(
          key: key,
          item: step.item,
          tts: widget.tts,
          onResult: _onOutcome,
          sep: '',
          errorless: errorless);
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
    final step = _current;
    final total = _plan.length;
    final idx = _i;
    final role = _plan[_i].role;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false, // убираем ← (путал с «к прошлому заданию»)
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: _rest,
          icon: const Icon(Icons.home_outlined, size: 22),
          label: const Text('Отдохнуть', style: TextStyle(fontSize: 16)),
        ),
        centerTitle: true,
        title: Text(
            role == 'review'
                ? 'Вспомним'
                : role == 'sameday'
                    ? 'Закрепим'
                    : '${idx + 1} из $total',
            style: const TextStyle(fontSize: 20)),
        actions: [
          TextButton(
            onPressed: () => _onOutcome(
                const StepOutcome(correct: false, unaided: false, gradeable: false)),
            child: const Text('Пропустить', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 8),
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
