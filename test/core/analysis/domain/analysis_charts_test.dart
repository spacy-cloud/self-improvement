import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  final allModules = ModuleId.values.toSet();

  AnalysisReport report({
    AnalysisPeriodLength length = AnalysisPeriodLength.days7,
    Iterable<AnalysisDay>? days,
    Set<ModuleId>? modules,
  }) => buildAnalysisReport(
    period: refPeriod(length),
    days: days ?? referenceDays(),
    usageStart: refUsageStart,
    activeModules: modules ?? allModules,
  );

  final r = report();
  ChartSeries series(AnalysisMetric metric) => r.chartFor(metric)!;

  const dayLabels = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  const dateLabels = [
    '27.09.',
    '28.09.',
    '29.09.',
    '30.09.',
    '01.10.',
    '02.10.',
    '03.10.',
  ];

  test('one series per chart in a fixed order, one point per day', () {
    expect(r.charts.map((s) => s.metric), [
      AnalysisMetric.steps,
      AnalysisMetric.water,
      AnalysisMetric.weight,
      AnalysisMetric.workouts,
      AnalysisMetric.focus,
      AnalysisMetric.tasks,
      AnalysisMetric.habits,
    ]);
    for (final s in r.charts) {
      expect(s.points, hasLength(7), reason: s.title);
      expect(s.points.map((p) => p.index), [0, 1, 2, 3, 4, 5, 6]);
      expect(s.points.first.date, d2026(9, 27));
      expect(s.points.last.date, refToday, reason: 'today is the last point');
      expect(s.points.map((p) => p.dayLabel), dayLabels, reason: s.title);
      expect(s.points.map((p) => p.dateLabel), dateLabels, reason: s.title);
      expect(s.hasData, isTrue, reason: s.title);
    }
    expect(r.chartFor(AnalysisMetric.meals), isNull);
    expect(r.chartFor(AnalysisMetric.dailyGoals), isNull);
  });

  test('longer periods have one point per day as well', () {
    for (final length in [
      AnalysisPeriodLength.days30,
      AnalysisPeriodLength.days90,
    ]) {
      final long = report(length: length);
      for (final s in long.charts) {
        expect(s.points, hasLength(length.days));
        expect(s.points.first.date, refToday.addDays(1 - length.days));
        expect(s.points.last.date, refToday);
      }
    }
  });

  group('steps: a recorded 0 is not a missing day', () {
    final steps = series(AnalysisMetric.steps);

    test('values and markers', () {
      expect(steps.points.map((p) => p.value), [
        8000,
        0,
        0,
        12000,
        0,
        6000,
        9000,
      ]);
      expect(steps.points.map((p) => p.marker), [
        DayMarker.recorded,
        DayMarker.recorded, // recorded zero
        DayMarker.notRecorded,
        DayMarker.recorded,
        DayMarker.notRecorded,
        DayMarker.recorded,
        DayMarker.recorded,
      ]);
      expect(steps.points.map((p) => p.isRecorded), [
        true,
        true,
        false,
        true,
        false,
        true,
        true,
      ]);
      expect(steps.unit, ChartUnit.steps);
      expect(steps.maxValue, 12000);
    });

    test('the texts tell "Nicht erfasst" from a recorded zero', () {
      expect(steps.points.map((p) => p.valueText), [
        '8.000',
        '0',
        'Nicht erfasst',
        '12.000',
        'Nicht erfasst',
        '6.000',
        '9.000',
      ]);
      expect(steps.points[1].semanticsLabel, 'Montag, 28.09.2026: 0 Schritte');
      expect(
        steps.points[2].semanticsLabel,
        'Dienstag, 29.09.2026: nicht erfasst',
      );
      expect(
        steps.points[0].semanticsLabel,
        'Sonntag, 27.09.2026: 8.000 Schritte',
      );
    });

    test('text summary', () {
      expect(steps.title, 'Schritte pro Tag');
      expect(
        steps.summary,
        'Schritte pro Tag, 27.09. bis 03.10.2026, inklusive heute. '
        'An 5 von 7 Tagen erfasst. '
        'Durchschnitt 7.000 Schritte pro erfasstem Tag. '
        'Höchster Wert 12.000 Schritte am Mittwoch, 30.09.2026.',
      );
    });
  });

  group('water: milliliters per day with "Nicht erfasst"', () {
    final water = series(AnalysisMetric.water);

    test('values and markers', () {
      expect(water.points.map((p) => p.value), [
        0,
        750,
        2000,
        0,
        1500,
        0,
        2500,
      ]);
      expect(water.points.map((p) => p.marker), [
        DayMarker.notRecorded,
        DayMarker.recorded,
        DayMarker.recorded,
        DayMarker.notRecorded,
        DayMarker.recorded,
        DayMarker.notRecorded,
        DayMarker.recorded,
      ]);
      expect(water.unit, ChartUnit.milliliters);
      expect(water.maxValue, 2500);
    });

    test('texts and summary', () {
      expect(water.points.map((p) => p.valueText), [
        'Nicht erfasst',
        '0,75${nb}l',
        '2${nb}l',
        'Nicht erfasst',
        '1,5${nb}l',
        'Nicht erfasst',
        '2,5${nb}l',
      ]);
      expect(
        water.summary,
        'Wasser pro Tag, 27.09. bis 03.10.2026, inklusive heute. '
        'An 4 von 7 Tagen erfasst. '
        'Durchschnitt 1,69 Liter pro erfasstem Tag. '
        'Höchster Wert 2,5 Liter am Samstag, 03.10.2026.',
      );
    });
  });

  group('weight: only measured days, never filled with zero', () {
    final weight = series(AnalysisMetric.weight);

    test('values are null on unmeasured days', () {
      expect(weight.points.map((p) => p.value), [
        71800,
        null,
        null,
        71600,
        null,
        null,
        71500,
      ]);
      expect(weight.points.map((p) => p.marker), [
        DayMarker.recorded,
        DayMarker.notRecorded,
        DayMarker.notRecorded,
        DayMarker.recorded,
        DayMarker.notRecorded,
        DayMarker.notRecorded,
        DayMarker.recorded,
      ]);
      expect(weight.unit, ChartUnit.grams);
      expect(weight.plottedPoints.map((p) => p.index), [0, 3, 6]);
      expect(weight.maxValue, 71800);
    });

    test('texts and summary', () {
      expect(weight.points.map((p) => p.valueText), [
        '71,8${nb}kg',
        'Nicht erfasst',
        'Nicht erfasst',
        '71,6${nb}kg',
        'Nicht erfasst',
        'Nicht erfasst',
        '71,5${nb}kg',
      ]);
      expect(weight.title, 'Gewicht, letzter Wert des Tages');
      expect(
        weight.summary,
        'Gewicht, letzter Wert des Tages, 27.09. bis 03.10.2026, inklusive '
        'heute. An 3 von 7 Tagen gemessen. '
        'Von 71,8 Kilogramm am Sonntag, 27.09.2026 auf 71,5 Kilogramm am '
        'Samstag, 03.10.2026. Änderung minus 0,3 Kilogramm.',
      );
    });

    test('a single measurement has no change yet', () {
      final single = report(
        days: [AnalysisDay(date: d2026(10, 1), weightGrams: 71500)],
      ).chartFor(AnalysisMetric.weight)!;
      expect(single.plottedPoints, hasLength(1));
      expect(
        single.summary,
        'Gewicht, letzter Wert des Tages, 27.09. bis 03.10.2026, inklusive '
        'heute. Eine Messung: 71,5 Kilogramm am Donnerstag, 01.10.2026. Noch '
        'kein Vergleich.',
      );
    });
  });

  group('activity series: a plain 0 without activity', () {
    test('workouts per day', () {
      final workouts = series(AnalysisMetric.workouts);
      expect(workouts.points.map((p) => p.value), [0, 0, 1, 0, 2, 0, 0]);
      expect(workouts.points.map((p) => p.marker), [
        DayMarker.noActivity,
        DayMarker.noActivity,
        DayMarker.recorded,
        DayMarker.noActivity,
        DayMarker.recorded,
        DayMarker.noActivity,
        DayMarker.noActivity,
      ]);
      expect(workouts.points.map((p) => p.valueText), [
        '0',
        '0',
        '1',
        '0',
        '2',
        '0',
        '0',
      ]);
      expect(workouts.unit, ChartUnit.count);
      expect(workouts.maxValue, 2);
      expect(
        workouts.points[0].semanticsLabel,
        'Sonntag, 27.09.2026: kein Workout',
      );
      expect(
        workouts.points[4].semanticsLabel,
        'Donnerstag, 01.10.2026: 2 Workouts',
      );
      expect(
        workouts.summary,
        'Workouts pro Tag, 27.09. bis 03.10.2026, inklusive heute. '
        'Insgesamt 3 Workouts an 2 Tagen, 2 Stunden 15 Minuten gesamt.',
      );
    });

    test('focus minutes per day (completed sessions only)', () {
      final focus = series(AnalysisMetric.focus);
      expect(focus.points.map((p) => p.value), [0, 25, 0, 30, 0, 10, 0]);
      expect(focus.unit, ChartUnit.minutes);
      expect(focus.points.map((p) => p.valueText), [
        '0${nb}min',
        '25${nb}min',
        '0${nb}min',
        '30${nb}min',
        '0${nb}min',
        '10${nb}min',
        '0${nb}min',
      ]);
      expect(focus.points[1].marker, DayMarker.recorded);
      expect(focus.points[2].marker, DayMarker.noActivity);
      expect(
        focus.summary,
        'Fokuszeit pro Tag, 27.09. bis 03.10.2026, inklusive heute. '
        'Insgesamt 1 Stunde 5 Minuten in 3 Sitzungen an 3 Tagen.',
      );
    });

    test('a focus session below one minute is fractional minutes', () {
      final short = report(
        days: [
          AnalysisDay(
            date: d2026(10, 1),
            focusCompletedSeconds: 30,
            focusCompletedSessions: 1,
          ),
        ],
      ).chartFor(AnalysisMetric.focus)!;
      expect(short.points[4].value, 0.5);
      expect(short.points[4].valueText, '<${nb}1${nb}min');
      expect(short.points[4].marker, DayMarker.recorded);
    });

    test('completed tasks per day', () {
      final tasks = series(AnalysisMetric.tasks);
      expect(tasks.points.map((p) => p.value), [0, 2, 0, 1, 0, 0, 3]);
      expect(tasks.points.map((p) => p.valueText), [
        '0',
        '2',
        '0',
        '1',
        '0',
        '0',
        '3',
      ]);
      expect(
        tasks.points[3].semanticsLabel,
        'Mittwoch, 30.09.2026: 1 Aufgabe erledigt',
      );
      expect(
        tasks.summary,
        'Erledigte Aufgaben pro Tag, 27.09. bis 03.10.2026, inklusive heute. '
        'Insgesamt 6 Aufgaben erledigt an 3 Tagen.',
      );
    });
  });

  group('habits: fulfilled out of applicable', () {
    final habits = series(AnalysisMetric.habits);

    test('value and outOf per day, days without a habit do not apply', () {
      expect(habits.points.map((p) => p.value), [null, 1, 0, 2, 1, null, 2]);
      expect(habits.points.map((p) => p.outOf), [null, 1, 1, 2, 2, null, 2]);
      expect(habits.points.map((p) => p.marker), [
        DayMarker.notApplicable,
        DayMarker.recorded,
        DayMarker.noActivity,
        DayMarker.recorded,
        DayMarker.recorded,
        DayMarker.notApplicable,
        DayMarker.recorded,
      ]);
      expect(habits.points.map((p) => p.valueText), [
        '–',
        '1 von 1',
        '0 von 1',
        '2 von 2',
        '1 von 2',
        '–',
        '2 von 2',
      ]);
      expect(
        habits.points[0].semanticsLabel,
        'Sonntag, 27.09.2026: keine Gewohnheit aktiv',
      );
      expect(
        habits.points[1].semanticsLabel,
        'Montag, 28.09.2026: 1 von 1 Gewohnheit erfüllt',
      );
      expect(
        habits.points[3].semanticsLabel,
        'Mittwoch, 30.09.2026: 2 von 2 Gewohnheiten erfüllt',
      );
      expect(habits.maxValue, 2);
    });

    test('summary', () {
      expect(
        habits.summary,
        'Erfüllte Gewohnheiten pro Tag, 27.09. bis 03.10.2026, inklusive '
        'heute. 6 von 8 Habit-Tagen erfüllt, 75 Prozent.',
      );
    });
  });

  group('empty series', () {
    final empty = report(days: const []);

    test('no data: honest summary, markers instead of zeros', () {
      for (final s in empty.charts) {
        expect(s.hasData, isFalse, reason: s.title);
        expect(
          s.summary,
          '${s.title}, 27.09. bis 03.10.2026, inklusive heute. '
          'Noch keine Daten.',
        );
      }
      final steps = empty.chartFor(AnalysisMetric.steps)!;
      expect(
        steps.points.every((p) => p.marker == DayMarker.notRecorded),
        isTrue,
      );
      expect(steps.maxValue, 0);
      final weight = empty.chartFor(AnalysisMetric.weight)!;
      expect(weight.plottedPoints, isEmpty);
      expect(weight.points.every((p) => p.value == null), isTrue);
      final habits = empty.chartFor(AnalysisMetric.habits)!;
      expect(
        habits.points.every((p) => p.marker == DayMarker.notApplicable),
        isTrue,
      );
    });
  });

  group('the series follow the calendar', () {
    test('a series across a month and a year boundary', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 1, 3),
      );
      final cross = buildAnalysisReport(
        period: period,
        days: [AnalysisDay(date: LocalDate(2025, 12, 31), stepsRecorded: 1000)],
        usageStart: LocalDate(2025, 1, 1),
        activeModules: allModules,
      );
      final steps = cross.chartFor(AnalysisMetric.steps)!;
      expect(steps.points.map((p) => p.dateLabel), [
        '28.12.',
        '29.12.',
        '30.12.',
        '31.12.',
        '01.01.',
        '02.01.',
        '03.01.',
      ]);
      expect(steps.points.map((p) => p.dayLabel), [
        'So',
        'Mo',
        'Di',
        'Mi',
        'Do',
        'Fr',
        'Sa',
      ]);
      expect(steps.points[3].value, 1000);
      expect(steps.points[3].marker, DayMarker.recorded);
      expect(steps.summary, contains('28.12.2025 bis 03.01.2026'));
    });

    test('the clock change days are ordinary days in the series', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 3, 31),
      );
      final spring = buildAnalysisReport(
        period: period,
        days: [
          AnalysisDay(
            date: LocalDate(2026, 3, 28),
            waterMl: 500,
            waterEntries: 1,
          ),
          AnalysisDay(
            date: LocalDate(2026, 3, 29),
            waterMl: 750,
            waterEntries: 2,
          ),
          AnalysisDay(
            date: LocalDate(2026, 3, 30),
            waterMl: 250,
            waterEntries: 1,
          ),
        ],
        usageStart: LocalDate(2026, 1, 1),
        activeModules: allModules,
      );
      final water = spring.chartFor(AnalysisMetric.water)!;
      expect(water.points.map((p) => p.dateLabel), [
        '25.03.',
        '26.03.',
        '27.03.',
        '28.03.',
        '29.03.',
        '30.03.',
        '31.03.',
      ]);
      expect(water.points.map((p) => p.value), [0, 0, 0, 500, 750, 250, 0]);
      expect(water.points[4].semanticsLabel, 'Sonntag, 29.03.2026: 0,75 Liter');
    });
  });
}
