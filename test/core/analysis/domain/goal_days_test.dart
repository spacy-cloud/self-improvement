import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/goal_days.dart';
import 'package:self_improvement/core/modules/module_id.dart';

import '../analysis_fixtures.dart';

GoalDay _goalDay(int applicable, int fulfilled) => GoalDay(
  date: d2026(10, 3),
  applicableGoals: applicable,
  fulfilledGoals: fulfilled,
);

void main() {
  group('GoalDay', () {
    test('a day without an applicable goal has no fraction and is no '
        'complete day', () {
      final day = _goalDay(0, 0);
      expect(day.hasGoals, isFalse);
      expect(day.isComplete, isFalse);
      expect(day.fraction, isNull);
    });

    test('complete means all applicable goals fulfilled, both sides', () {
      final partial = _goalDay(3, 2);
      final all = _goalDay(3, 3);
      final one = _goalDay(1, 1);
      expect(partial.isComplete, isFalse);
      expect(partial.fraction, closeTo(2 / 3, 1e-9));
      expect(all.isComplete, isTrue);
      expect(all.fraction, 1.0);
      expect(one.isComplete, isTrue);
    });

    test('a day with goals but none fulfilled is a 0 fraction, not null', () {
      final none = _goalDay(4, 0);
      expect(none.fraction, 0.0);
      expect(none.isComplete, isFalse);
    });

    test('spoken label names weekday, date and the state in words', () {
      final complete = GoalDay(
        date: d2026(9, 28),
        applicableGoals: 6,
        fulfilledGoals: 6,
      );
      final partial = GoalDay(
        date: d2026(9, 29),
        applicableGoals: 6,
        fulfilledGoals: 2,
      );
      final none = GoalDay(
        date: d2026(9, 27),
        applicableGoals: 0,
        fulfilledGoals: 0,
      );
      final single = GoalDay(
        date: d2026(9, 30),
        applicableGoals: 1,
        fulfilledGoals: 1,
      );
      expect(
        complete.semanticsLabel,
        'Montag, 28.09.2026: 6 von 6 Tageszielen erfüllt, Tag komplett',
      );
      expect(
        partial.semanticsLabel,
        'Dienstag, 29.09.2026: 2 von 6 Tageszielen erfüllt',
      );
      expect(none.semanticsLabel, 'Sonntag, 27.09.2026: keine Tagesziele');
      expect(
        single.semanticsLabel,
        'Mittwoch, 30.09.2026: 1 von 1 Tagesziel erfüllt, Tag komplett',
      );
    });
  });

  group('buildGoalDays and AnalysisReport.goalDays', () {
    AnalysisReport report(AnalysisPeriodLength length) => buildAnalysisReport(
      period: refPeriod(length),
      days: referenceDays(),
      usageStart: refUsageStart,
      activeModules: ModuleId.values.toSet(),
    );

    test('one entry per day of the period, oldest first, today last', () {
      final days = report(AnalysisPeriodLength.days7).goalDays;
      expect(days, hasLength(7));
      expect(days.first.date, d2026(9, 27));
      expect(days.last.date, d2026(10, 3));
    });

    test('the reference week reads 0/0, 6/6, 2/6, 7/7, 3/7, 0/4, 7/7', () {
      final days = report(AnalysisPeriodLength.days7).goalDays;
      expect(
        [
          for (final day in days)
            '${day.fulfilledGoals}/${day.applicableGoals}',
        ],
        ['0/0', '6/6', '2/6', '7/7', '3/7', '0/4', '7/7'],
      );
    });

    test('the complete days of the strip equal the complete days of the '
        'figures (same rule)', () {
      final r = report(AnalysisPeriodLength.days7);
      expect(
        r.goalDays.where((day) => day.isComplete).length,
        r.current.goals.completeDays,
      );
      expect(
        r.goalDays.where((day) => day.hasGoals).length,
        r.current.goals.daysWithGoals,
      );
    });

    test('longer periods list every day, missing days are days without '
        'goals', () {
      final days = report(AnalysisPeriodLength.days30).goalDays;
      expect(days, hasLength(30));
      expect(days.last.date, d2026(10, 3));
      // 30 days back from the sparse reference data: the oldest days have no
      // entry at all.
      expect(days.first.hasGoals, isFalse);
      expect(days.first.semanticsLabel, contains('keine Tagesziele'));
    });

    test('a report built without days has a strip of days without goals', () {
      final r = buildAnalysisReport(
        period: refPeriod(AnalysisPeriodLength.days7),
        days: const <AnalysisDay>[],
        usageStart: refUsageStart,
        activeModules: ModuleId.values.toSet(),
      );
      expect(r.goalDays, hasLength(7));
      expect(r.goalDays.every((day) => !day.hasGoals), isTrue);
    });
  });
}
