import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  final longAgo = LocalDate(2026, 1, 1);

  /// A day with workouts only.
  AnalysisDay w(LocalDate date, int entries, int minutes) =>
      AnalysisDay(date: date, workoutEntries: entries, workoutMinutes: minutes);

  WorkoutWeekCard card(
    LocalDate today,
    Iterable<AnalysisDay> days, {
    LocalDate? usageStart,
    int? target = 3,
  }) => buildWorkoutWeekCard(
    today: today,
    days: days,
    usageStart: usageStart ?? longAgo,
    weeklyTarget: target,
  );

  group('reference week (Saturday 2026-10-03)', () {
    final week = card(refToday, referenceDays());

    test('Monday to today against the same weekdays of the previous week', () {
      expect(week.today, refToday);
      expect(week.weekStart, d2026(9, 28), reason: 'Monday');
      expect(week.elapsedDays, 6, reason: 'Monday .. Saturday');
      expect(week.previousWeekStart, d2026(9, 21), reason: 'Monday');
      expect(week.previousWeekEnd, d2026(9, 26), reason: 'Saturday, today - 7');
    });

    test('counts and minutes of both ranges', () {
      // this week: 09-29 (1 x 45), 10-01 (2 x 90 min); 09-27 is last week's Sunday
      expect(week.entries, 3);
      expect(week.minutes, 135);
      // last week to date: 09-22 (1 x 40), 09-25 (1 x 50)
      expect(week.previousEntries, 2);
      expect(week.previousMinutes, 90);
      expect(week.hasData, isTrue);
    });

    test('the target of 3 is reached: ring 100 %', () {
      expect(week.weeklyTarget, 3);
      expect(week.targetReached, isTrue);
      expect(week.ringFraction, 1.0);
      expect(week.ringPercent, 100);
      expect(week.progressText, '3 von 3 Workouts, Wochenziel erreicht');
    });

    test('texts and labels of the week', () {
      expect(week.title, 'Workouts diese Woche');
      expect(week.rangeText, '28.09. bis 03.10.2026, bis heute');
      expect(week.previousRangeText, 'Vorwoche: 21.09. bis 26.09.2026');
      final labels = ComparisonLabels.forWeek(refToday);
      expect(labels.currentTitle, 'Diese Woche (Mo bis Sa)');
      expect(labels.previousTitle, 'Vorwoche (Mo bis Sa)');
      expect(labels.against, 'gegenüber der Vorwoche (Mo bis Sa)');
    });

    test('both figures compare week to date with week to date', () {
      expect(week.figures, hasLength(2));
      final count = week.countFigure;
      expect(count.key, AnalysisFigureKeys.workoutWeekCount);
      expect(count.metric, AnalysisMetric.workoutWeek);
      expect(count.currentText, '3');
      expect(count.previousText, '2');
      expect(count.changeText, '+50$nb% (+1)');
      expect(
        count.comparisonText,
        '+50$nb% (+1) gegenüber der Vorwoche (Mo bis Sa)',
      );
      expect(count.coverage!.text, 'Wochenziel 3 erreicht');
      final minutes = week.minutesFigure;
      expect(minutes.key, AnalysisFigureKeys.workoutWeekMinutes);
      expect(minutes.currentText, '2${nb}h 15${nb}min');
      expect(minutes.previousText, '1${nb}h 30${nb}min');
      expect(minutes.changeText, '+50$nb% (+45${nb}min)');
    });

    test('the card reads as one sentence for screen readers', () {
      expect(week.semanticsLabel, startsWith('Workouts diese Woche, '));
      expect(week.semanticsLabel, contains('3 von 3 Workouts'));
      expect(week.semanticsLabel, contains('Vorwoche (Mo bis Sa)'));
    });
  });

  group('Monday boundaries: week to date, not the whole week', () {
    test(
      'on a Monday only Monday counts, last Sunday belongs to last week',
      () {
        final monday = d2026(9, 28);
        final week = card(monday, [
          w(d2026(9, 27), 2, 80), // Sunday: last week
          w(d2026(9, 28), 1, 30), // Monday: this week
          w(d2026(9, 21), 1, 20), // previous Monday: same weekday
          w(d2026(9, 22), 1, 99), // previous Tuesday: not part of week to date
        ]);
        expect(week.weekStart, monday);
        expect(week.elapsedDays, 1);
        expect(week.previousWeekStart, d2026(9, 21));
        expect(week.previousWeekEnd, d2026(9, 21));
        expect(week.entries, 1);
        expect(week.minutes, 30);
        expect(week.previousEntries, 1);
        expect(week.previousMinutes, 20);
        expect(week.rangeText, '28.09.2026, bis heute');
        expect(week.previousRangeText, 'Vorwoche: 21.09.2026');
        expect(
          ComparisonLabels.forWeek(monday).currentTitle,
          'Diese Woche (Mo)',
        );
        expect(week.countFigure.comparison!.percentRounded, 0);
      },
    );

    test('on a Wednesday the previous Thursday and Friday do not count', () {
      final wednesday = d2026(9, 30);
      final week = card(wednesday, [
        w(d2026(9, 21), 1, 30), // previous Monday
        w(d2026(9, 23), 1, 40), // previous Wednesday
        w(d2026(9, 24), 1, 50), // previous Thursday: not yet in week to date
        w(d2026(9, 25), 2, 60), // previous Friday: not yet in week to date
        w(d2026(9, 28), 1, 25), // Monday
        w(d2026(9, 30), 1, 35), // Wednesday
      ]);
      expect(week.elapsedDays, 3);
      expect(week.previousWeekEnd, d2026(9, 23));
      expect(week.previousEntries, 2, reason: 'a full week would be 5');
      expect(week.previousMinutes, 70);
      expect(week.entries, 2);
      expect(week.minutes, 60);
    });

    test('on a Sunday the whole week meets the whole previous week', () {
      final sunday = d2026(10, 4);
      final week = card(sunday, [
        w(d2026(9, 27), 1, 40), // previous Sunday: part of the previous week
        w(d2026(9, 28), 1, 30),
        w(d2026(10, 4), 2, 50), // today
        w(d2026(9, 21), 1, 20),
      ]);
      expect(week.elapsedDays, 7);
      expect(week.weekStart, d2026(9, 28));
      expect(week.previousWeekStart, d2026(9, 21));
      expect(week.previousWeekEnd, d2026(9, 27));
      expect(week.entries, 3);
      expect(week.previousEntries, 2);
      expect(week.previousMinutes, 60);
    });

    test('the day after a Sunday starts a new week', () {
      final monday = d2026(10, 5);
      final week = card(monday, [
        w(d2026(10, 4), 3, 100), // Sunday: now last week
        w(d2026(10, 5), 1, 10),
      ]);
      expect(week.weekStart, monday);
      expect(week.entries, 1);
      expect(week.previousWeekStart, d2026(9, 28));
      expect(week.previousWeekEnd, d2026(9, 28));
    });

    test('data outside the two ranges is ignored', () {
      final week = card(refToday, [
        w(d2026(10, 4), 9, 900), // tomorrow
        w(d2026(9, 27), 9, 900), // Sunday of last week, after the base range
        w(d2026(9, 20), 9, 900), // two weeks ago
        w(d2026(9, 29), 1, 10),
      ]);
      expect(week.entries, 1);
      expect(week.previousEntries, 0);
    });
  });

  group('calendar boundaries', () {
    test('year boundary: Thursday 2026-01-01', () {
      final week = card(LocalDate(2026, 1, 1), [
        w(LocalDate(2025, 12, 28), 5, 500), // Sunday: previous week
        w(LocalDate(2025, 12, 29), 1, 30), // Monday
        w(LocalDate(2026, 1, 1), 1, 40),
        w(LocalDate(2025, 12, 22), 1, 20), // previous Monday
        w(LocalDate(2025, 12, 25), 1, 25), // previous Thursday
        w(LocalDate(2025, 12, 26), 7, 700), // previous Friday: not yet
      ], usageStart: LocalDate(2025, 1, 1));
      expect(week.weekStart, LocalDate(2025, 12, 29));
      expect(week.elapsedDays, 4);
      expect(week.previousWeekStart, LocalDate(2025, 12, 22));
      expect(week.previousWeekEnd, LocalDate(2025, 12, 25));
      expect(week.entries, 2);
      expect(week.minutes, 70);
      expect(week.previousEntries, 2);
      expect(week.previousMinutes, 45);
    });

    test('leap day 2028-02-29 is part of the week of Wednesday 2028-03-01', () {
      final week = card(LocalDate(2028, 3, 1), [
        w(LocalDate(2028, 2, 27), 4, 400), // Sunday: previous week
        w(LocalDate(2028, 2, 28), 1, 30),
        w(LocalDate(2028, 2, 29), 1, 40),
        w(LocalDate(2028, 3, 1), 1, 50),
      ], usageStart: LocalDate(2027, 1, 1));
      expect(week.weekStart, LocalDate(2028, 2, 28));
      expect(week.elapsedDays, 3);
      expect(week.entries, 3);
      expect(week.previousWeekStart, LocalDate(2028, 2, 21));
      expect(week.previousWeekEnd, LocalDate(2028, 2, 23));
    });

    test('the clock change Sundays are normal calendar days', () {
      final spring = card(LocalDate(2026, 3, 29), [
        w(LocalDate(2026, 3, 23), 1, 30),
        w(LocalDate(2026, 3, 29), 1, 40),
        w(LocalDate(2026, 3, 16), 1, 20),
        w(LocalDate(2026, 3, 22), 1, 25),
      ]);
      expect(spring.weekStart, LocalDate(2026, 3, 23));
      expect(spring.elapsedDays, 7);
      expect(spring.previousWeekStart, LocalDate(2026, 3, 16));
      expect(spring.previousWeekEnd, LocalDate(2026, 3, 22));
      expect(spring.entries, 2);
      expect(spring.previousEntries, 2);

      final autumn = card(LocalDate(2026, 10, 25), [
        w(LocalDate(2026, 10, 19), 1, 30),
        w(LocalDate(2026, 10, 25), 2, 70),
        w(LocalDate(2026, 10, 12), 1, 20),
        w(LocalDate(2026, 10, 18), 1, 25),
      ]);
      expect(autumn.weekStart, LocalDate(2026, 10, 19));
      expect(autumn.elapsedDays, 7);
      expect(autumn.previousWeekStart, LocalDate(2026, 10, 12));
      expect(autumn.previousWeekEnd, LocalDate(2026, 10, 18));
      expect(autumn.entries, 3);
      expect(autumn.minutes, 100);
      expect(autumn.previousEntries, 2);
    });
  });

  group('target ring: capped at 100 % while the real count stays', () {
    WorkoutWeekCard withEntries(int entries, {int? target = 3}) => card(
      refToday,
      [if (entries > 0) w(d2026(10, 1), entries, entries * 30)],
      target: target,
    );

    test('0 to 3 workouts with the default target 3', () {
      final expectations = <(int, double, int, String)>[
        (0, 0.0, 0, '0 von 3 Workouts'),
        (1, 1 / 3, 33, '1 von 3 Workouts'),
        (2, 2 / 3, 67, '2 von 3 Workouts'),
        (3, 1.0, 100, '3 von 3 Workouts, Wochenziel erreicht'),
      ];
      for (final (entries, fraction, percent, text) in expectations) {
        final week = withEntries(entries);
        expect(week.entries, entries);
        expect(week.ringFraction, closeTo(fraction, 1e-9), reason: '$entries');
        expect(week.ringPercent, percent, reason: '$entries');
        expect(week.progressText, text);
        expect(week.targetReached, entries >= 3);
      }
    });

    test(
      'more than the target: the ring stays at 100 %, the count is real',
      () {
        for (final entries in [4, 5, 9]) {
          final week = withEntries(entries);
          expect(week.entries, entries);
          expect(week.ringFraction, 1.0);
          expect(week.ringPercent, 100);
          expect(week.targetReached, isTrue);
          expect(week.progressText, '$entries Workouts, Wochenziel 3 erreicht');
          expect(week.countFigure.currentText, '$entries');
        }
        expect(withEntries(4).minutes, 120, reason: 'minutes are not capped');
      },
    );

    test('other targets round the ring percent half up', () {
      expect(withEntries(1, target: 1).ringPercent, 100);
      expect(withEntries(7, target: 14).ringPercent, 50);
      expect(withEntries(1, target: 14).ringPercent, 7, reason: '7.14 %');
      expect(withEntries(13, target: 14).ringPercent, 93, reason: '92.86 %');
      expect(withEntries(1, target: 6).ringPercent, 17, reason: '16.67 %');
      expect(withEntries(1, target: 8).ringPercent, 13, reason: '12.5 %');
      expect(withEntries(14, target: 14).ringFraction, 1.0);
      expect(withEntries(2, target: 5).targetReached, isFalse);
    });

    test('a switched-off weekly goal has no ring and no target text', () {
      final none = withEntries(0, target: null);
      expect(none.weeklyTarget, isNull);
      expect(none.ringFraction, isNull);
      expect(none.ringPercent, isNull);
      expect(none.targetReached, isFalse);
      expect(none.progressText, 'Noch kein Workout diese Woche');
      expect(none.countFigure.coverage, isNull);
      final one = withEntries(1, target: null);
      expect(one.progressText, '1 Workout');
      expect(withEntries(2, target: null).progressText, '2 Workouts');
    });

    test('the default target is 3', () {
      expect(defaultWorkoutWeeklyTarget, 3);
    });

    test('an open target shows how many are still missing', () {
      expect(
        withEntries(1).countFigure.coverage!.text,
        'Wochenziel 3, noch 2 offen',
      );
      expect(
        withEntries(2).countFigure.coverage!.text,
        'Wochenziel 3, noch 1 offen',
      );
      expect(
        withEntries(3).countFigure.coverage!.text,
        'Wochenziel 3 erreicht',
      );
    });
  });

  group('comparison base of the week', () {
    final days = [
      w(d2026(9, 22), 1, 40), // previous Tuesday
      w(d2026(10, 1), 2, 60), // this week
    ];

    test('the previous week may start exactly on the usage start', () {
      final week = card(refToday, days, usageStart: d2026(9, 21));
      expect(week.countFigure.hasComparison, isTrue);
      expect(week.minutesFigure.hasComparison, isTrue);
    });

    test(
      'a previous week that starts before the usage start: no comparison',
      () {
        final week = card(refToday, days, usageStart: d2026(9, 22));
        for (final figure in week.figures) {
          expect(figure.hasComparison, isFalse);
          expect(
            figure.comparison!.reason,
            NoComparisonReason.previousPeriodBeforeStart,
          );
          expect(figure.changeText, 'Noch kein Vergleich');
          expect(figure.comparisonText, 'Noch kein Vergleich');
          expect(figure.explanation, contains('Nutzungszeit'));
        }
        expect(week.entries, 2, reason: 'the current week is still shown');
      },
    );

    test('the current week may start after the usage start', () {
      final week = card(refToday, days, usageStart: d2026(9, 1));
      expect(week.countFigure.hasComparison, isTrue);
    });

    test('no workout this week: no comparison, the ring shows 0', () {
      final week = card(refToday, [w(d2026(9, 22), 1, 40)]);
      expect(week.entries, 0);
      expect(week.hasData, isFalse);
      expect(week.ringPercent, 0);
      expect(week.countFigure.currentText, '–');
      expect(
        week.countFigure.comparison!.reason,
        NoComparisonReason.noCurrentData,
      );
    });

    test('no workout in the previous week to date: no comparison', () {
      final week = card(refToday, [w(d2026(10, 1), 1, 40)]);
      expect(week.entries, 1);
      expect(week.previousEntries, 0);
      expect(week.countFigure.previousText, '–');
      expect(
        week.countFigure.comparison!.reason,
        NoComparisonReason.noPreviousData,
      );
    });

    test('an unknown usage start allows no comparison', () {
      final week = buildWorkoutWeekCard(
        today: refToday,
        days: days,
        usageStart: null,
        weeklyTarget: 3,
      );
      expect(
        week.countFigure.comparison!.reason,
        NoComparisonReason.noUsageStart,
      );
    });
  });
}
