// Слово с пропуском вслух не произносим по кускам. Красный кейс наивной
// реализации: '_' меняется на пробел, и «ов_а» звучит как «ов а» — пациент
// слышит разорванный образец и закрепляет неверный звуковой рисунок слова.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rech/engine/tts_service.dart';
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

  group('подготовка текста к озвучке', () {
    test('слово с пропуском внутри не читается по кускам', () {
      final t = TtsService();
      final out = t.prepareForSpeech(
          'Напишите слово целиком, вставив пропущенную букву: ов_а (домашняя)');
      expect(out, 'Напишите слово целиком, вставив пропущенную букву: (домашняя)',
          reason: 'слово-обломок выброшено целиком, пояснение осталось');
    });

    test('пропуск на месте целого слова остаётся паузой', () {
      final t = TtsService();
      expect(t.prepareForSpeech('Мы поехали ___ озеро на рыбалку.'),
          'Мы поехали озеро на рыбалку.');
    });

    test('ударение по словарю проставляется', () {
      final t = TtsService()..setStress({'змея': 'зме́я'});
      expect(t.prepareForSpeech('змея'), 'зме́я');
    });
  });

  group('fill_letter: озвучка собранного слова', () {
    final item = <String, dynamic>{
      'id': 'fl_096',
      'prompt': 'ов_а (домашняя)',
      'answer': 'овца',
      'accept': ['овца'],
    };

    Future<_SpyTts> pump(WidgetTester tester) async {
      final tts = _SpyTts();
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TypedExercise(
            item: item,
            tts: tts,
            type: 'fill_letter',
            onResult: (_) {},
          ),
        ),
      ));
      return tts;
    }

    testWidgets('до ответа «Прослушать» не выдаёт слово', (tester) async {
      final tts = await pump(tester);
      await tester.tap(find.byTooltip('Прослушать'));
      await tester.pump();
      expect(tts.spoken.single.contains('овца'), isFalse,
          reason: 'иначе задание решено за пациента');
    });

    testWidgets('после верного ответа читает слово целиком', (tester) async {
      final tts = await pump(tester);
      await tester.enterText(find.byType(TextField), 'овца');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Проверить'));
      await tester.pump();
      tts.spoken.clear();
      await tester.tap(find.byTooltip('Прослушать'));
      await tester.pump();
      expect(tts.spoken.single, 'овца');
    });
  });
}
