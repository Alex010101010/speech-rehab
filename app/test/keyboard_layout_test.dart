// Печатный ввод на планшете в горизонтали: экранная клавиатура съедает около
// половины высоты. Пациент должен одновременно видеть задание, поле ввода и
// кнопки — без прокрутки. Картинку-подсказку не прячем (это опора, которую он
// сам попросил), а ужимаем.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rech/app_theme.dart';
import 'package:rech/engine/tts_service.dart';
import 'package:rech/widgets/exercises.dart';

const _screen = Size(1280, 800); // планшет 10″ в горизонтали, логические px
const _keyboard = 380.0;


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tts = TtsService();

  final item = <String, dynamic>{
    'id': 'nd_test',
    'prompt': 'Чем режут хлеб, колбасу и овощи на кухне?',
    'answer': 'нож',
    'accept': ['нож'],
    'emoji': '🔪',
  };

  Future<void> pump(WidgetTester tester, {required bool keyboard}) async {
    tester.view.physicalSize = _screen;
    tester.view.devicePixelRatio = 1.0;
    if (keyboard) {
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    }
    addTearDown(tester.view.reset);
    // каркас как в session_screen: AppBar + отступ 24
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        appBar: AppBar(title: const Text('1 из 10')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: TypedExercise(
                item: item, tts: tts, type: 'name_by_description', onResult: (_) {}),
          ),
        ),
      ),
    ));
    // раскрыть картинку-подсказку — самый тесный случай
    await tester.tap(find.widgetWithText(OutlinedButton, 'Подсказка'));
    await tester.pump();
  }

  void expectAboveKeyboard(WidgetTester tester, Finder f) {
    final r = tester.getRect(f);
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(_screen.height - _keyboard),
        reason: '$f уехал под клавиатуру');
  }

  testWidgets('клавиатура открыта: задание, поле и кнопки видны разом',
      (tester) async {
    await pump(tester, keyboard: true);
    expectAboveKeyboard(tester, find.text(item['prompt'] as String));
    expectAboveKeyboard(tester, find.text('🔪'));
    expectAboveKeyboard(tester, find.byType(TextField));
    expectAboveKeyboard(tester, find.widgetWithText(ElevatedButton, 'Проверить'));
    expectAboveKeyboard(tester, find.widgetWithText(OutlinedButton, 'Подсказка'));
    expectAboveKeyboard(tester, find.text('Подсказка: смотрите картинку'));
  });

  testWidgets('клавиатура закрыта: кнопка «Дальше» на месте', (tester) async {
    await pump(tester, keyboard: false);
    expect(find.widgetWithText(ElevatedButton, 'Дальше'), findsOneWidget);
    // без клавиатуры картинка в прежнем полном размере
    expect(tester.getSize(find.text('🔪')).height, greaterThan(100));
  });
}
