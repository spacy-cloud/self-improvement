import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

WeightEntry entry(String id, String isoDate, int hour, int grams) {
  final date = LocalDate.parse(isoDate);
  return WeightEntry(
    id: id,
    weightGrams: grams,
    occurredAtUtc: DateTime.utc(date.year, date.month, date.day, hour),
    localDate: date,
    timezoneId: 'Europe/Berlin',
    beforeToilet: false,
    afterDrinking: false,
    afterEating: false,
    rowVersion: 1,
    gamificationEligible: true,
  );
}

void main() {
  final today = LocalDate(2026, 10, 3);

  group('dashboard weight card (AT08)', () {
    test('without measurements the card is empty and shows no number', () {
      final model = buildWeightCard(entriesNewestFirst: const [], today: today);
      expect(model.isEmpty, isTrue);
      expect(model.current, isNull);
      expect(model.points, isEmpty);
      expect(model.weekDeltaGrams, isNull);
    });

    test('one measurement: the value and one point, no week comparison', () {
      final model = buildWeightCard(
        entriesNewestFirst: [entry('a', '2026-10-03', 7, 71500)],
        today: today,
      );
      expect(model.current!.weightGrams, 71500);
      expect(model.points, hasLength(1));
      expect(model.weekDeltaGrams, isNull);
    });

    test('week comparison needs a measurement on or before today - 7', () {
      final model = buildWeightCard(
        entriesNewestFirst: [
          entry('c', '2026-10-03', 7, 71500),
          entry('b', '2026-10-01', 7, 72000),
          entry('a', '2026-09-26', 7, 72700),
        ],
        today: today,
      );
      expect(model.current!.id, 'c');
      expect(model.weekDeltaGrams, -1200, reason: '71,5 - 72,7');
      expect(model.points.map((p) => p.date.toIso()), [
        '2026-10-01',
        '2026-10-03',
      ], reason: 'the window is the last 7 local days incl. today');
    });

    test('the card ignores the period chosen on the weight screen', () {
      final model = buildWeightCard(
        entriesNewestFirst: [
          entry('new', '2026-10-03', 7, 71500),
          entry('old', '2026-08-01', 7, 74000),
        ],
        today: today,
      );
      expect(model.points, hasLength(1));
    });
  });
}
