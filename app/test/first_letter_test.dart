// Пропуск первой буквы подаётся касанием: слева буквы из пары, справа хвост
// слова. Красный кейс наивной реализации: форму включают всему fill_letter —
// тогда задания с пропуском внутри слова («элек_род») и задание с парой, где
// нужной буквы нет (fl_082: «_ука» при паре ж/ш), становятся нерешаемыми.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rech/engine/tts_service.dart';
import 'package:rech/models/exercise.dart';
import 'package:rech/widgets/exercises.dart';

/// Перехватывает озвучку, не трогая платформенный канал.
class _SpyTts extends TtsService {
  final List<String> spoken = [];
  @override
  Future<void> speak(String text) async => spoken.add(text);
}

void main() {
  // FlutterTts вешает обработчик канала в конструкторе — биндинг нужен раньше
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> item({
    String prompt = '_уб',
    String answer = 'дуб',
    String pair = 'д/т',
    String emoji = '',
  }) =>
      {
        'id': 'fl_001',
        'prompt': prompt,
        'answer': answer,
        'accept': [answer],
        'pair': pair,
        if (emoji.isNotEmpty) 'emoji': emoji,
      };

  group('когда задание годится для выбора буквы', () {
    test('пропуск в начале слова и пара с нужной буквой — годится', () {
      expect(firstLetterPickable(item()), isTrue);
    });

    test('пропуск внутри слова остаётся печатным', () {
      expect(
          firstLetterPickable(
              item(prompt: 'элек_род', answer: 'электрод', pair: 'д/т')),
          isFalse);
    });

    test('пара без правильной буквы не годится (fl_082)', () {
      expect(
          firstLetterPickable(
              item(prompt: '_ука', answer: 'щука', pair: 'ж/ш')),
          isFalse,
          reason: 'иначе правильную букву нажать негде');
    });

    test('пара не из двух букв не годится', () {
      expect(firstLetterPickable(item(pair: 'д')), isFalse);
      expect(firstLetterPickable(item(pair: 'ду/т')), isFalse);
    });
  });

  group('FirstLetterExercise', () {
    Future<(_SpyTts, StepOutcome?)> run(
      WidgetTester tester,
      Future<void> Function(WidgetTester t) act, {
      Map<String, dynamic>? data,
      bool errorless = false,
      bool next = true,
    }) async {
      final tts = _SpyTts();
      StepOutcome? got;
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FirstLetterExercise(
            item: data ?? item(),
            tts: tts,
            errorless: errorless,
            onResult: (o) => got = o,
          ),
        ),
      ));
      await act(tester);
      if (next) {
        await tester.tap(find.widgetWithText(ElevatedButton, 'Дальше'));
        await tester.pump();
      }
      return (tts, got);
    }

    testWidgets('на экране обе буквы пары и хвост слова', (tester) async {
      await run(tester, (t) async {}, next: false);
      expect(find.text('д'), findsOneWidget);
      expect(find.text('т'), findsOneWidget);
      expect(find.text('уб'), findsOneWidget, reason: 'хвост слова справа');
      expect(find.text('?'), findsOneWidget, reason: 'пустой слот под букву');
      expect(find.byType(TextField), findsNothing, reason: 'печатать не нужно');
    });

    testWidgets('верная буква встаёт на место, слово звучит целиком',
        (tester) async {
      final (tts, out) = await run(tester, (t) async {
        await t.tap(find.text('д'));
        await t.pump();
      });
      expect(tts.spoken, ['дуб'], reason: 'по порядку и целиком, не по кускам');
      expect(find.text('?'), findsNothing);
      expect(out!.correct, isTrue);
      expect(out.unaided, isTrue);
      expect(out.cueLevel, 0);
    });

    testWidgets('неверная буква не решает задание', (tester) async {
      final (tts, out) = await run(tester, (t) async {
        await t.tap(find.text('т'));
        await t.pump();
        expect(find.text('?'), findsOneWidget, reason: 'слот ещё пуст');
        await t.tap(find.text('д'));
        await t.pump();
      });
      expect(tts.spoken, ['дуб'],
          reason: 'на неверную букву вслух ничего не идёт');
      expect(out!.correct, isTrue);
      expect(out.unaided, isFalse, reason: 'была неверная попытка');
    });

    testWidgets('«Не знаю» показывает ответ и не засчитывается', (tester) async {
      final (tts, out) = await run(tester, (t) async {
        await t.tap(find.widgetWithText(OutlinedButton, 'Не знаю'));
        await t.pump();
      });
      expect(tts.spoken, ['дуб']);
      expect(out!.correct, isFalse);
      expect(out.cueLevel, 3);
    });

    testWidgets('картинка-подсказка — смысловая ось, не фонематическая',
        (tester) async {
      final (_, out) = await run(tester, (t) async {
        await t.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
        await t.pump();
        await t.tap(find.text('д'));
        await t.pump();
      }, data: item(emoji: '🌳'));
      expect(out!.semanticCue, 1);
      expect(out.cueLevel, 0);
      expect(out.unaided, isFalse);
    });

    testWidgets('самое длинное слово влезает на узкий экран', (tester) async {
      // тест падает на RenderFlex overflow — это и есть проверка вёрстки
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FirstLetterExercise(
            item: item(
                prompt: '_олотенце', answer: 'полотенце', pair: 'б/п'),
            tts: _SpyTts(),
            onResult: (_) {},
          ),
        ),
      ));
      expect(find.text('олотенце'), findsOneWidget);
    });

    testWidgets('errorless: слово собрано сразу и в метрику не идёт',
        (tester) async {
      final (tts, out) = await run(tester, (t) async {
        await t.pump();
      }, errorless: true);
      expect(tts.spoken, ['Это слово. дуб']);
      expect(out!.gradeable, isFalse);
    });
  });
}
