import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/application/steps_stats.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

StepsHistoryDay _day(LocalDate date, int? steps, {int? target = 10000}) =>
    StepsHistoryDay(
      date: date,
      recorded: steps != null,
      progress: StepsProgress(steps: steps ?? 0, target: target),
    );

void main() {
  final today = LocalDate(2026, 10, 3);

  /// Newest first, like the provider.
  List<StepsHistoryDay> week(List<int?> steps, {int? target = 10000}) => [
    for (var i = 0; i < steps.length; i++)
      _day(today.addDays(-i), steps[i], target: target),
  ];

  group('computeStepsStats', () {
    test('averages recorded days only and counts reached days (AT15)', () {
      final stats = computeStepsStats(
        week([12000, 8000, null, 10000, null, 0, 5000]),
      );

      expect(stats.windowDays, 7);
      expect(stats.recordedDays, 5);
      expect(stats.averageSteps, 7000, reason: '(12000+8000+10000+0+5000)/5');
      expect(stats.reachedDays, 2, reason: '12000 and 10000 reach 10000');
      expect(stats.bestSteps, 12000);
      expect(stats.bestDate, today);
      expect(stats.hasTarget, isTrue);
    });

    test('a recorded zero counts, a missing day does not (AT15)', () {
      final withZero = computeStepsStats(week([0, 6000]));
      final withMissing = computeStepsStats(week([null, 6000]));

      expect(withZero.averageSteps, 3000);
      expect(withZero.recordedDays, 2);
      expect(withMissing.averageSteps, 6000);
      expect(withMissing.recordedDays, 1);
    });

    test('rounds the average half up', () {
      expect(computeStepsStats(week([1, 2])).averageSteps, 2, reason: '1,5');
      expect(
        computeStepsStats(week([1, 1, 2])).averageSteps,
        1,
        reason: '1,33',
      );
    });

    test('the latest day wins a tie for the best day', () {
      final stats = computeStepsStats(week([9000, 9000, 3000]));

      expect(stats.bestDate, today);
    });

    test('no record at all stays empty, no invented numbers', () {
      final stats = computeStepsStats(week([null, null, null]));

      expect(stats.isEmpty, isTrue);
      expect(stats.averageSteps, isNull);
      expect(stats.bestSteps, isNull);
      expect(stats.bestDate, isNull);
      expect(stats.reachedDays, 0);
    });

    test('without a goal nothing counts as reached and none is shown', () {
      final stats = computeStepsStats(week([20000, 15000], target: null));

      expect(stats.hasTarget, isFalse);
      expect(stats.reachedDays, 0);
    });

    test('each day is judged against the goal of its own day', () {
      final stats = computeStepsStats([
        _day(today, 8000, target: 8000),
        _day(today.addDays(-1), 8000, target: 10000),
      ]);

      expect(stats.reachedDays, 1);
    });
  });

  group('steps texts', () {
    test('groups thousands with dots and shows percent and remainder', () {
      const progress = StepsProgress(steps: 7450, target: 10000);

      expect(stepsText(7450), '7.450');
      expect(stepsTargetText(progress), '/ 10.000');
      expect(stepsPercentText(progress), '75 % vom Tagesziel');
      expect(stepsRemainingText(progress), 'Noch 2.550');
    });

    test('goal reached and exceeded keep the real percentage', () {
      const progress = StepsProgress(steps: 12000, target: 10000);

      expect(stepsRemainingText(progress), 'Ziel erreicht');
      expect(stepsPercentText(progress), '120 % vom Tagesziel');
      expect(progress.fraction, 1.0);
    });

    test('no goal: honest statement instead of a percentage', () {
      const progress = StepsProgress(steps: 5000, target: null);

      expect(stepsTargetText(progress), isNull);
      expect(stepsRemainingText(progress), isNull);
      expect(stepsPercentText(progress), 'Kein Tagesziel aktiv');
    });

    test('date headings and sentences', () {
      expect(stepsDateHeading(today, today), 'Heute, 3. Oktober');
      expect(stepsDateHeading(today.addDays(-1), today), 'Gestern, 2. Oktober');
      expect(
        stepsDateHeading(LocalDate(2026, 9, 28), today),
        'Montag, 28. September',
      );
      expect(
        stepsDateHeading(LocalDate(2025, 12, 24), today),
        'Mittwoch, 24. Dezember 2025',
      );
      expect(stepsDateInSentence(today, today), 'heute');
      expect(stepsDateInSentence(today.addDays(-1), today), 'gestern');
      expect(
        stepsDateInSentence(LocalDate(2026, 9, 28), today),
        'Mo., 28. Sep.',
      );
    });

    test('chart summary tells coverage, average, best day and goal days', () {
      final stats = computeStepsStats(week([12000, 8000, null, 10000]));

      expect(
        stepsChartSummary(stats),
        '3 von 4 Tagen erfasst, im Schnitt 10.000 Schritte pro Tag, bester '
        'Tag 12.000 Schritte. Das Tagesziel wurde an 2 Tagen erreicht.',
      );
      expect(
        stepsChartSummary(computeStepsStats(week([null, null]))),
        'In den letzten 2 Tagen sind keine Schritte erfasst.',
      );
    });

    test('day status separates missing, no goal, reached and missed', () {
      expect(stepsDayStatus(_day(today, null)), 'Nicht erfasst');
      expect(stepsDayStatus(_day(today, 5000, target: null)), 'Kein Tagesziel');
      expect(stepsDayStatus(_day(today, 10000)), 'Ziel erreicht');
      expect(stepsDayStatus(_day(today, 9999)), 'Ziel nicht erreicht');
    });

    test('best day label names the weekday in a week, the date otherwise', () {
      final week7 = computeStepsStats(
        week([1000, 9000, 2000, 3000, 4000, 5000, 6000]),
      );
      final long = computeStepsStats([
        for (var i = 0; i < 30; i++)
          _day(today.addDays(-i), i == 3 ? 9000 : 1000),
      ]);

      expect(stepsBestDayLabel(week7), 'Bester Tag (Fr)');
      expect(stepsBestDayLabel(long), 'Bester Tag (30. Sep.)');
    });
  });
}
