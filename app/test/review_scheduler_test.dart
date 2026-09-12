// Тесты интервального повторения (spaced retrieval): лесенка Leitner,
// сериализация карточек и расписания в прогрессе. Чистая логика без виджетов —
// гоняется CI-шагом flutter test (локального Flutter нет).
import 'package:flutter_test/flutter_test.dart';
import 'package:rech/engine/progress_store.dart';

void main() {
  group('ReviewScheduler.nextBox', () {
    test('вспомнил сам — вверх по лесенке', () {
      expect(ReviewScheduler.nextBox(0, recalled: true), 1);
      expect(ReviewScheduler.nextBox(3, recalled: true), 4);
    });

    test('не вспомнил — на одну коробку вниз', () {
      expect(ReviewScheduler.nextBox(4, recalled: false), 3);
      expect(ReviewScheduler.nextBox(1, recalled: false), 0);
    });

    test('клампы на краях: не ниже 0 и не выше последней', () {
      expect(ReviewScheduler.nextBox(0, recalled: false), 0);
      expect(ReviewScheduler.nextBox(4, recalled: true), 4);
    });
  });

  group('ReviewScheduler.dueAfter', () {
    test('лесенка интервалов 1→2→5→14→30 дней', () {
      final d = DateTime(2026, 7, 2);
      expect(ReviewScheduler.dueAfter(d, 0), '2026-07-03');
      expect(ReviewScheduler.dueAfter(d, 1), '2026-07-04');
      expect(ReviewScheduler.dueAfter(d, 2), '2026-07-07');
      expect(ReviewScheduler.dueAfter(d, 3), '2026-07-16');
      expect(ReviewScheduler.dueAfter(d, 4), '2026-08-01');
    });

    test('box за пределами лесенки клампится', () {
      final d = DateTime(2026, 7, 2);
      expect(ReviewScheduler.dueAfter(d, 99), '2026-08-01');
      expect(ReviewScheduler.dueAfter(d, -1), '2026-07-03');
    });
  });

  group('ReviewScheduler.dayStr', () {
    test('нули в месяце и дне — иначе сломается сравнение строк', () {
      expect(ReviewScheduler.dayStr(DateTime(2026, 1, 5)), '2026-01-05');
      expect(ReviewScheduler.dayStr(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('созревание сравнением строк: due ≤ сегодня', () {
      const today = '2026-07-02';
      expect('2026-06-30'.compareTo(today) <= 0, isTrue); // просрочена
      expect(today.compareTo(today) <= 0, isTrue); // созрела сегодня
      expect('2026-07-03'.compareTo(today) <= 0, isFalse); // ещё рано
    });
  });

  group('ReviewCard JSON', () {
    test('round-trip', () {
      final c = ReviewCard(type: 'picture_word', box: 2, due: '2026-07-07');
      final back = ReviewCard.fromJson(c.toJson());
      expect(back.type, 'picture_word');
      expect(back.box, 2);
      expect(back.due, '2026-07-07');
    });

    test('битые/пустые поля не роняют загрузку', () {
      final c = ReviewCard.fromJson(const {});
      expect(c.type, '');
      expect(c.box, 0);
      expect(c.due, '');
    });
  });

  group('Progress.review сериализация', () {
    test('round-trip через toJson/fromJson', () {
      final p = Progress();
      p.review['ech_001'] =
          ReviewCard(type: 'endings_choice', box: 1, due: '2026-07-04');
      final back = Progress.fromJson(p.toJson());
      expect(back.review.length, 1);
      expect(back.review['ech_001']!.type, 'endings_choice');
      expect(back.review['ech_001']!.box, 1);
      expect(back.review['ech_001']!.due, '2026-07-04');
    });

    test('старый прогресс без поля review читается', () {
      final p = Progress.fromJson(const {'sessions': 3});
      expect(p.sessions, 3);
      expect(p.review, isEmpty);
    });
  });
}
