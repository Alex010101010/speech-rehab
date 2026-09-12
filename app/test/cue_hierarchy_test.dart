// Иерархия подсказок (cueing hierarchy): две независимые оси — фонематическая
// глубина cueLevel и смысловая semanticCue — и раскладка исходов по бакетам
// называния/узнавания. Красный кейс наивной реализации: picture_word всегда
// отдаёт cueLevel 0, а показанная картинка не считается подсказкой.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rech/models/exercise.dart';
import 'package:rech/engine/tts_service.dart';
import 'package:rech/widgets/exercises.dart';

/// Обёртка для виджета задания + перехват исхода по кнопке «Дальше».
Future<StepOutcome?> _run(
  WidgetTester tester,
  Widget Function(void Function(StepOutcome)) build,
  Future<void> Function(WidgetTester t) act,
) async {
  StepOutcome? got;
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: build((o) => got = o)),
  ));
  await act(tester);
  await tester.tap(find.widgetWithText(ElevatedButton, 'Дальше'));
  await tester.pump();
  return got;
}

void main() {
  // FlutterTts вешает обработчик канала в конструкторе — биндинг нужен раньше
  TestWidgetsFlutterBinding.ensureInitialized();
  final tts = TtsService();

  group('CueTally: раскладка по бакетам', () {
    test('называние и узнавание — в разные бакеты, не в один средний балл', () {
      final t = CueTally();
      t.add('name_by_description',
          const StepOutcome(correct: true, unaided: false, cueLevel: 2));
      t.add('picture_word',
          const StepOutcome(correct: true, unaided: false, cueLevel: 1));
      expect(t.nameSum, 2);
      expect(t.nameN, 1);
      expect(t.recogSum, 1);
      expect(t.recogN, 1);
    });

    test('смысловые подсказки считаются отдельно от фонематических', () {
      final t = CueTally();
      t.add(
          'name_by_description',
          const StepOutcome(
              correct: true, unaided: false, cueLevel: 0, semanticCue: 1));
      expect(t.nameSum, 0, reason: 'смысл не поднимает фонематическую глубину');
      expect(t.semN, 1);
    });

    test('неоцениваемые шаги (самооценка, errorless) в метрику не идут', () {
      final t = CueTally();
      t.add('name_by_description',
          const StepOutcome(correct: true, unaided: false, gradeable: false));
      expect(t.nameN, 0);
      expect(t.semN, 0);
    });

    test('прочие типы в трендах подсказок не участвуют', () {
      final t = CueTally();
      t.add('prepositions',
          const StepOutcome(correct: true, unaided: false, cueLevel: 3));
      expect(t.nameN, 0);
      expect(t.recogN, 0);
      expect(t.toHistoryFields(), isEmpty);
    });

    test('в снимок сессии попадают только непустые бакеты', () {
      final t = CueTally();
      t.add('picture_word',
          const StepOutcome(correct: true, unaided: false, cueLevel: 1));
      final f = t.toHistoryFields();
      expect(f['recogCueSum'], 1);
      expect(f['recogCueN'], 1);
      expect(f.containsKey('nameCueSum'), isFalse);
      expect(f.containsKey('semCueN'), isFalse);
    });
  });

  group('PictureWordExercise: лесенка узнавания', () {
    const Map<String, dynamic> item = {
      'id': 'pw_t1',
      'emoji': '🐟',
      'answer': 'рыба',
      'options': ['рыба', 'лодка', 'сеть'],
    };

    testWidgets('выбрал сам — ступень 0', (t) async {
      final o = await _run(
        t,
        (cb) => PictureWordExercise(item: item, tts: tts, onResult: cb),
        (t) async {
          await t.tap(find.widgetWithText(ElevatedButton, 'рыба'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 0);
      expect(o.unaided, isTrue);
    });

    testWidgets('после неверной попытки — ступень 1', (t) async {
      final o = await _run(
        t,
        (cb) => PictureWordExercise(item: item, tts: tts, onResult: cb),
        (t) async {
          await t.tap(find.widgetWithText(ElevatedButton, 'лодка'));
          await t.pump();
          await t.tap(find.widgetWithText(ElevatedButton, 'рыба'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 1);
      expect(o.correct, isTrue);
    });

    testWidgets('погасили дистрактор подсказкой — ступень 1', (t) async {
      final o = await _run(
        t,
        (cb) => PictureWordExercise(item: item, tts: tts, onResult: cb),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
          await t.pump();
          await t.tap(find.widgetWithText(ElevatedButton, 'рыба'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 1);
    });

    testWidgets('«Не знаю» — ступень 3, ответ показан', (t) async {
      final o = await _run(
        t,
        (cb) => PictureWordExercise(item: item, tts: tts, onResult: cb),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Не знаю'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 3);
      expect(o.correct, isFalse);
    });
  });

  group('TypedExercise: смысловая ось', () {
    const Map<String, dynamic> item = {
      'id': 'nbd_t1',
      'prompt': 'Чем ловят рыбу?',
      'emoji': '🎣',
      'answer': 'удочка',
    };

    testWidgets('показанная картинка — смысловая подсказка, не фонематическая',
        (t) async {
      final o = await _run(
        t,
        (cb) => TypedExercise(
            item: item, tts: tts, onResult: cb, type: 'name_by_description'),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
          await t.pump();
          await t.enterText(find.byType(TextField), 'удочка');
          await t.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
          await t.pump();
        },
      );
      expect(o!.semanticCue, 1);
      expect(o.cueLevel, 0, reason: 'буквы не показывали');
      expect(o.correct, isTrue);
    });

    testWidgets('без подсказок — обе оси нулевые', (t) async {
      final o = await _run(
        t,
        (cb) => TypedExercise(
            item: item, tts: tts, onResult: cb, type: 'name_by_description'),
        (t) async {
          await t.enterText(find.byType(TextField), 'удочка');
          await t.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 0);
      expect(o.semanticCue, 0);
      expect(o.unaided, isTrue);
    });

    testWidgets('буквенная подсказка поднимает только фонематическую ось',
        (t) async {
      const Map<String, dynamic> noCue = {
        'id': 'nbd_t2',
        'prompt': 'Чем ловят рыбу?',
        'answer': 'удочка',
      };
      final o = await _run(
        t,
        (cb) => TypedExercise(
            item: noCue, tts: tts, onResult: cb, type: 'name_by_description'),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
          await t.pump();
          await t.enterText(find.byType(TextField), 'удочка');
          await t.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
          await t.pump();
        },
      );
      expect(o!.cueLevel, 1);
      expect(o.semanticCue, 0);
    });

    testWidgets('semHint — самая слабая ступень, идёт перед картинкой',
        (t) async {
      const Map<String, dynamic> withSem = {
        'id': 'nbd_t3',
        'prompt': 'Чем ловят рыбу?',
        'emoji': '🎣',
        'semHint': 'это рыболовная снасть',
        'answer': 'удочка',
      };
      final o = await _run(
        t,
        (cb) => TypedExercise(
            item: withSem, tts: tts, onResult: cb, type: 'name_by_description'),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
          await t.pump();
          expect(find.text('Подсказка: это рыболовная снасть'), findsOneWidget);
          await t.enterText(find.byType(TextField), 'удочка');
          await t.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
          await t.pump();
        },
      );
      expect(o!.semanticCue, 1);
      expect(o.cueLevel, 0);
    });

    testWidgets('без semHint поведение прежнее — первой идёт картинка',
        (t) async {
      await _run(
        t,
        (cb) => TypedExercise(
            item: item, tts: tts, onResult: cb, type: 'name_by_description'),
        (t) async {
          await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
          await t.pump();
          expect(find.text('Подсказка: смотрите картинку'), findsOneWidget);
          await t.enterText(find.byType(TextField), 'удочка');
          await t.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
          await t.pump();
        },
      );
    });
  });
}
