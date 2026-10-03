import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/presentation/weight_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

WeightEntry entry({
  bool toilet = false,
  bool drinking = false,
  bool eating = false,
}) => WeightEntry(
  id: 'e',
  weightGrams: 71500,
  occurredAtUtc: DateTime.utc(2026, 10, 3, 6, 32),
  localDate: LocalDate(2026, 10, 3),
  timezoneId: 'Europe/Berlin',
  beforeToilet: toilet,
  afterDrinking: drinking,
  afterEating: eating,
  rowVersion: 1,
  gamificationEligible: true,
);

void main() {
  group('condition texts (AT06)', () {
    test('no condition flagged means the derived text nüchtern', () {
      expect(weightConditionLabels(entry()), ['nüchtern']);
      expect(weightMetaLine('08:32', entry()), '08:32 · nüchtern');
    });

    test('toilet is named separately and keeps nüchtern', () {
      expect(weightConditionLabels(entry(toilet: true)), [
        'nüchtern',
        'Vor dem Klo',
      ]);
    });

    test('drinking or eating removes nüchtern and lists the flags', () {
      expect(weightConditionLabels(entry(drinking: true)), [
        'Nach dem Trinken',
      ]);
      expect(
        weightMetaLine(
          '09:15',
          entry(toilet: true, drinking: true, eating: true),
        ),
        '09:15 · Vor dem Klo · Nach dem Trinken · Nach dem Essen',
      );
    });

    test('the start marker is appended last', () {
      expect(
        weightMetaLine('08:00', entry(), isStart: true),
        '08:00 · nüchtern · Startgewicht',
      );
    });
  });

  group('changes are neutral text with arrow and true minus (AT08)', () {
    test('loss, gain and no change', () {
      expect(weightDeltaText(-300), '↓  −0,3 kg');
      expect(weightDeltaText(500), '↑  +0,5 kg');
      expect(weightDeltaText(0), '→  0,0 kg');
    });

    test('spoken form names the direction in words', () {
      expect(weightDeltaSpoken(-300), 'minus 0,3 Kilogramm');
      expect(weightDeltaSpoken(1250), 'plus 1,2 Kilogramm');
      expect(weightDeltaSpoken(0), 'unverändert');
    });
  });

  group('goal and period texts (AT09)', () {
    test('remaining distance or goal reached, never negative', () {
      expect(
        weightGoalRemainingText(
          const WeightGoalState(
            progress: 0.5,
            remainingGrams: 3500,
            reached: false,
          ),
        ),
        'Noch 3,5 kg',
      );
      expect(
        weightGoalRemainingText(
          const WeightGoalState(progress: 1, remainingGrams: 0, reached: true),
        ),
        'Ziel erreicht',
      );
    });

    test('3 M is spoken as 90 days', () {
      expect(weightPeriodLabel(7), '7 T');
      expect(weightPeriodLabel(30), '30 T');
      expect(weightPeriodLabel(90), '3 M');
      expect(weightPeriodSpoken(90), '3 Monate, 90 Tage');
      expect(weightPeriodSpoken(7), '7 Tage');
    });
  });

  group('chart text alternative (AT08)', () {
    final today = LocalDate(2026, 10, 3);

    test('no point says so and invents no value', () {
      expect(
        weightChartSummary(const [], 7, today),
        'In den letzten 7 Tagen gibt es keine Messung.',
      );
    });

    test('one point names the day and the value only', () {
      expect(
        weightChartSummary(
          [WeightDayPoint(date: LocalDate(2026, 10, 3), grams: 71500)],
          7,
          today,
        ),
        'Eine Messung am Sa., 3. Okt.: 71,5 kg.',
      );
    });

    test('several points give count, first, last and the neutral change', () {
      expect(
        weightChartSummary(
          [
            WeightDayPoint(date: LocalDate(2026, 9, 28), grams: 72700),
            WeightDayPoint(date: LocalDate(2026, 10, 1), grams: 72000),
            WeightDayPoint(date: LocalDate(2026, 10, 3), grams: 71500),
          ],
          7,
          today,
        ),
        '3 Messtage in 7 Tagen. Zuerst 72,7 kg, zuletzt 71,5 kg (\u22121,2 kg).',
      );
    });
  });
}
