import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_charts.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/modules/module_id.dart';

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

  /// The visible cells of a metric row: label, current, previous, change,
  /// coverage (empty without one).
  List<String> row(AnalysisFigure f) => [
    f.tableLabel,
    f.currentText,
    f.previousText,
    f.changeText,
    f.coverage?.text ?? '',
  ];

  final r = report();

  group('metric table equals the cards', () {
    test('the rows are the very figures of the cards, in card order', () {
      final fromCards = [for (final card in r.cards) ...card.figures];
      expect(r.table.periodTable.rows, hasLength(fromCards.length));
      for (var i = 0; i < fromCards.length; i++) {
        expect(
          r.table.periodTable.rows[i],
          same(fromCards[i]),
          reason: fromCards[i].key,
        );
      }
      final weekRows = r.table.weekTable!.rows;
      expect(weekRows, hasLength(2));
      for (var i = 0; i < weekRows.length; i++) {
        expect(weekRows[i], same(r.workoutWeek!.figures[i]));
      }
    });

    test('the numbers of the reference scenario, row by row', () {
      expect(r.table.periodTable.rows.map(row).toList(), [
        [
          'Tagesziele, Kompletttage',
          '50$nb%',
          '29$nb%',
          '+21${nb}Prozentpunkte',
          '3 von 6 Tagen komplett',
        ],
        [
          'Tagesziele, aktive Tage',
          '83$nb%',
          '71$nb%',
          '+12${nb}Prozentpunkte',
          '5 von 6 Tagen aktiv',
        ],
        [
          'Schritte, Ø pro erfasstem Tag',
          '7.000',
          '5.000',
          '+40$nb% (+2.000)',
          '5/7 Tage erfasst',
        ],
        ['Schritte, gesamt', '35.000', '15.000', '–', '5/7 Tage erfasst'],
        [
          'Wasser, Ø pro erfasstem Tag',
          '1,69${nb}l',
          '1,5${nb}l',
          '+13$nb% (+0,19${nb}l)',
          '4/7 Tage erfasst',
        ],
        ['Wasser, gesamt', '6,75${nb}l', '3${nb}l', '–', '4/7 Tage erfasst'],
        [
          'Gewicht, Änderung vom ersten zum letzten Wert',
          '${minus}0,3${nb}kg',
          '${minus}0,5${nb}kg',
          '+0,2${nb}kg',
          '3/7 Tage gemessen',
        ],
        [
          'Gewicht, letzter Wert',
          '71,5${nb}kg',
          '71,9${nb}kg',
          '${minus}0,4${nb}kg',
          '3/7 Tage gemessen',
        ],
        ['Workouts, Anzahl', '3', '2', '+50$nb% (+1)', ''],
        [
          'Workouts, Dauer gesamt',
          '2${nb}h 15${nb}min',
          '1${nb}h 30${nb}min',
          '+50$nb% (+45${nb}min)',
          '',
        ],
        [
          'Fokuszeit, gesamt',
          '1${nb}h 5${nb}min',
          '50${nb}min',
          '+30$nb% (+15${nb}min)',
          '',
        ],
        ['Fokuszeit, abgeschlossene Sitzungen', '3', '1', '+200$nb% (+2)', ''],
        ['Aufgaben, erledigt', '6', '4', '+50$nb% (+2)', ''],
        [
          'Gewohnheiten, erfüllte Habit-Tage',
          '75$nb%',
          '29$nb%',
          '+46${nb}Prozentpunkte',
          '6 von 8 Habit-Tagen erfüllt',
        ],
        ['Mahlzeiten, Anzahl', '5', '2', '+150$nb% (+3)', ''],
        [
          'Mahlzeiten, bekannte Kalorien',
          '1.500${nb}kcal',
          '1.000${nb}kcal',
          'Noch kein Vergleich',
          'Kalorien unvollständig: 4 von 5 Mahlzeiten mit Angabe',
        ],
      ]);
    });

    test('the workout week rows', () {
      expect(r.table.weekTable!.rows.map(row).toList(), [
        [
          'Workouts diese Woche, Anzahl',
          '3',
          '2',
          '+50$nb% (+1)',
          'Wochenziel 3 erreicht',
        ],
        [
          'Workouts diese Woche, Dauer gesamt',
          '2${nb}h 15${nb}min',
          '1${nb}h 30${nb}min',
          '+50$nb% (+45${nb}min)',
          '',
        ],
      ]);
    });

    test('headers and captions use the real dates', () {
      expect(r.table.periodTable.headers, [
        'Kennzahl',
        'Letzte 7 Tage',
        'Vorherige 7 Tage',
        'Veränderung',
        'Erfassung',
      ]);
      expect(
        r.table.periodTable.caption,
        'Kennzahlen der letzten 7 Tage (27.09. bis 03.10.2026, inklusive '
        'heute) im Vergleich mit den vorherigen 7 Tagen (20.09. bis '
        '26.09.2026)',
      );
      expect(r.table.weekTable!.headers, [
        'Kennzahl',
        'Diese Woche (Mo bis Sa)',
        'Vorwoche (Mo bis Sa)',
        'Veränderung',
        'Wochenziel',
      ]);
      expect(
        r.table.weekTable!.caption,
        'Workouts diese Woche (28.09. bis 03.10.2026, bis heute) im '
        'Vergleich mit der Vorwoche (Vorwoche: 21.09. bis 26.09.2026)',
      );
    });

    test('every row has a complete sentence for screen readers', () {
      for (final f in r.table.periodTable.rows) {
        expect(f.spokenText, startsWith('${f.tableLabel}: '));
        expect(f.spokenText, contains('Vorherige 7 Tage: '));
      }
      expect(
        r.table.periodTable.rows[2].spokenText,
        'Schritte, Ø pro erfasstem Tag: 7.000 Schritte, an 5 von 7 Tagen '
        'erfasst. Vorherige 7 Tage: 5.000 Schritte, an 3 von 7 Tagen erfasst. '
        'plus 40 Prozent, plus 2.000 Schritte gegenüber den vorherigen 7 '
        'Tagen.',
      );
    });

    test('only active modules have rows', () {
      final body = report(modules: {ModuleId.body});
      expect(body.table.periodTable.rows.map((f) => f.key), [
        AnalysisFigureKeys.goalsComplete,
        AnalysisFigureKeys.goalsActive,
        AnalysisFigureKeys.stepsAverage,
        AnalysisFigureKeys.stepsTotal,
        AnalysisFigureKeys.weightChange,
        AnalysisFigureKeys.weightLast,
      ]);
      expect(body.table.weekTable, isNull);
    });
  });

  group('per-day table', () {
    final table = r.table.dayTable;

    test('columns of all active modules', () {
      expect(table.headers, [
        'Schritte',
        'Wasser',
        'Gewicht',
        'Workouts',
        'Fokuszeit',
        'Aufgaben',
        'Gewohnheiten',
        'Mahlzeiten',
        'Kalorien (bekannt)',
        'Tagesziele',
      ]);
      expect(
        table.caption,
        'Werte pro Tag, 27.09. bis 03.10.2026, inklusive heute',
      );
    });

    test('one row per day, oldest first, with weekday and date', () {
      expect(table.rows, hasLength(7));
      expect(table.rows.map((row) => row.dayText), [
        'So, 27.09.',
        'Mo, 28.09.',
        'Di, 29.09.',
        'Mi, 30.09.',
        'Do, 01.10.',
        'Fr, 02.10.',
        'Sa, 03.10.',
      ]);
      expect(table.rows.first.date, d2026(9, 27));
      expect(table.rows.last.date, refToday);
      for (final row in table.rows) {
        expect(row.cells, hasLength(table.headers.length));
      }
    });

    List<String> texts(int index) =>
        table.rows[index].cells.map((cell) => cell.text).toList();

    test('Sunday 09-27: values and "Nicht erfasst" markers', () {
      expect(texts(0), [
        '8.000',
        'Nicht erfasst',
        '71,8${nb}kg',
        '0',
        '0${nb}min',
        '0',
        '–',
        '0',
        '–',
        '–',
      ]);
    });

    test('Monday 09-28: a recorded zero is not "Nicht erfasst"', () {
      expect(texts(1), [
        '0',
        '0,75${nb}l',
        'Nicht erfasst',
        '0',
        '25${nb}min',
        '2',
        '1 von 1',
        '3',
        '1.200${nb}kcal (Kalorien unvollständig)',
        '6 von 6',
      ]);
      expect(table.rows[1].cells[0].marker, DayMarker.recorded);
      expect(table.rows[0].cells[1].marker, DayMarker.notRecorded);
      expect(table.rows[1].cells[2].marker, DayMarker.notRecorded);
    });

    test('Thursday 10-01: complete calories and two workouts', () {
      expect(texts(4), [
        'Nicht erfasst',
        '1,5${nb}l',
        'Nicht erfasst',
        '2',
        '0${nb}min',
        '0',
        '1 von 2',
        '2',
        '300${nb}kcal',
        '3 von 7',
      ]);
    });

    test('Friday 10-02: tasks module off, no habit, four goals', () {
      expect(texts(5), [
        '6.000',
        'Nicht erfasst',
        'Nicht erfasst',
        '0',
        '10${nb}min',
        '0',
        '–',
        '0',
        '–',
        '0 von 4',
      ]);
      expect(table.rows[5].cells[6].marker, DayMarker.notApplicable);
    });

    test('the cells of a row read as one sentence', () {
      expect(
        table.rows[1].semanticsLabel,
        'Montag, 28.09.2026: Schritte 0 Schritte, Wasser 0,75 Liter, Gewicht '
        'nicht erfasst, Workouts kein Workout, Fokuszeit 25 Minuten, Aufgaben '
        '2 Aufgaben erledigt, Gewohnheiten 1 von 1 Gewohnheit erfüllt, '
        'Mahlzeiten 3 Mahlzeiten, Kalorien (bekannt) 1.200 Kilokalorien, '
        'Kalorien unvollständig, Tagesziele 6 von 6 Tageszielen erfüllt, Tag '
        'komplett',
      );
      expect(
        table.rows[0].semanticsLabel,
        'Sonntag, 27.09.2026: Schritte 8.000 Schritte, Wasser nicht erfasst, '
        'Gewicht 71,8 Kilogramm, Workouts kein Workout, Fokuszeit keine '
        'Fokuszeit, Aufgaben keine Aufgabe erledigt, Gewohnheiten keine '
        'Gewohnheit aktiv, Mahlzeiten keine Mahlzeit, Kalorien (bekannt) '
        'keine Mahlzeit, Tagesziele keine Tagesziele',
      );
    });

    test('the daily values add up to the totals of the cards', () {
      int sum(int Function(AnalysisDay) pick) => referenceDays()
          .where((d) => !d.date.isBefore(d2026(9, 27)))
          .fold(0, (a, d) => a + pick(d));
      expect(sum((d) => d.stepsRecorded ?? 0), r.current.steps.totalSteps);
      expect(sum((d) => d.waterMl), r.current.water.totalMl);
      expect(sum((d) => d.workoutEntries), r.current.workouts.entries);
      expect(sum((d) => d.workoutMinutes), r.current.workouts.minutes);
      expect(
        sum((d) => d.focusCompletedSeconds),
        r.current.focus.completedSeconds,
      );
      expect(sum((d) => d.tasksCompleted), r.current.tasks.completed);
      expect(sum((d) => d.mealEntries), r.current.meals.meals);
      expect(sum((d) => d.knownKcal), r.current.meals.knownKcal);
      expect(
        sum((d) => d.applicableHabits),
        r.current.habits.applicableHabitDays,
      );
      expect(
        sum((d) => d.fulfilledHabits),
        r.current.habits.fulfilledHabitDays,
      );
    });

    test(
      'the same values appear in the table cells and in the chart points',
      () {
        final steps = r.chartFor(AnalysisMetric.steps)!;
        final column = table.headers.indexOf('Schritte');
        for (var i = 0; i < 7; i++) {
          expect(
            table.rows[i].cells[column].text,
            steps.points[i].valueText,
            reason: 'day $i',
          );
        }
        final water = r.chartFor(AnalysisMetric.water)!;
        final waterColumn = table.headers.indexOf('Wasser');
        for (var i = 0; i < 7; i++) {
          expect(
            table.rows[i].cells[waterColumn].text,
            water.points[i].valueText,
            reason: 'day $i',
          );
        }
      },
    );

    test('only active modules have columns', () {
      final focus = report(modules: {ModuleId.focus});
      expect(focus.table.dayTable.headers, [
        'Workouts',
        'Fokuszeit',
        'Tagesziele',
      ]);
      for (final row in focus.table.dayTable.rows) {
        expect(row.cells, hasLength(3));
      }
      final nutrition = report(modules: {ModuleId.nutrition});
      expect(nutrition.table.dayTable.headers, [
        'Wasser',
        'Mahlzeiten',
        'Kalorien (bekannt)',
        'Tagesziele',
      ]);
      final none = report(modules: const {});
      expect(none.table.dayTable.headers, ['Tagesziele']);
    });
  });

  group('calorie cells', () {
    List<String> kcalCell(AnalysisDay day) {
      final result = report(days: [day]);
      final column = result.table.dayTable.headers.indexOf(
        'Kalorien (bekannt)',
      );
      final cell = result.table.dayTable.rows[4].cells[column];
      return [cell.text, cell.spoken, cell.marker.name];
    }

    test('no meal, no kcal given, partly given, complete, deliberate zero', () {
      final date = d2026(10, 1);
      expect(kcalCell(AnalysisDay(date: date)), [
        '–',
        'keine Mahlzeit',
        'notApplicable',
      ]);
      expect(kcalCell(AnalysisDay(date: date, mealEntries: 2)), [
        'Keine Angabe',
        'keine Kalorienangabe',
        'notRecorded',
      ]);
      expect(
        kcalCell(
          AnalysisDay(
            date: date,
            mealEntries: 2,
            mealsWithKcal: 1,
            knownKcal: 400,
          ),
        ),
        [
          '400${nb}kcal (Kalorien unvollständig)',
          '400 Kilokalorien, Kalorien unvollständig',
          'recorded',
        ],
      );
      expect(
        kcalCell(
          AnalysisDay(
            date: date,
            mealEntries: 2,
            mealsWithKcal: 2,
            knownKcal: 900,
          ),
        ),
        ['900${nb}kcal', '900 Kilokalorien', 'recorded'],
      );
      expect(
        kcalCell(
          AnalysisDay(
            date: date,
            mealEntries: 1,
            mealsWithKcal: 1,
            knownKcal: 0,
          ),
        ),
        ['0${nb}kcal', '0 Kilokalorien', 'recorded'],
      );
    });
  });

  group('30 and 90 day tables', () {
    test('one row per day of the period', () {
      expect(
        report(length: AnalysisPeriodLength.days30).table.dayTable.rows,
        hasLength(30),
      );
      final ninety = report(length: AnalysisPeriodLength.days90);
      expect(ninety.table.dayTable.rows, hasLength(90));
      expect(ninety.table.dayTable.rows.first.date, d2026(7, 6));
      expect(ninety.table.dayTable.rows.last.date, refToday);
      expect(
        ninety.table.dayTable.caption,
        'Werte pro Tag, 06.07. bis 03.10.2026, inklusive heute',
      );
    });
  });
}
