import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  test('exactly five fixed neutral texts', () {
    expect(motivationTexts, hasLength(5));
    expect(motivationTexts.toSet(), hasLength(5), reason: 'all different');
    for (final text in motivationTexts) {
      expect(text, isNotEmpty);
      expect(text.toLowerCase(), isNot(contains('abnehm')));
      expect(text.toLowerCase(), isNot(contains('gewicht')));
    }
  });

  test('the text follows dayOfYear % 5 and repeats every five days', () {
    final start = LocalDate(2026, 10, 3);
    expect(motivationTextFor(start), motivationTexts[start.dayOfYear % 5]);
    for (var offset = 0; offset < 10; offset++) {
      expect(
        motivationTextFor(start.addDays(offset)),
        motivationTextFor(start.addDays(offset + 5)),
      );
    }
    final consecutive = {
      for (var i = 0; i < 5; i++) motivationTextFor(start.addDays(i)),
    };
    expect(
      consecutive,
      hasLength(5),
      reason: 'five consecutive days show all five texts',
    );
  });

  test('it is stable within a day and does not depend on time', () {
    final date = LocalDate(2026, 1, 1);
    expect(date.dayOfYear, 1);
    expect(motivationTextFor(date), motivationTexts[1]);
    expect(motivationTextFor(LocalDate(2026, 1, 1)), motivationTextFor(date));
  });
}
