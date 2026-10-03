import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_cards.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  final allModules = ModuleId.values.toSet();

  AnalysisReport report({
    AnalysisPeriodLength length = AnalysisPeriodLength.days7,
    Iterable<AnalysisDay>? days,
    LocalDate? usageStart,
    bool noUsageStart = false,
    Set<ModuleId>? modules,
    int? target = 3,
    bool? goalsEver,
  }) => buildAnalysisReport(
    period: refPeriod(length),
    days: days ?? referenceDays(),
    usageStart: noUsageStart ? null : (usageStart ?? refUsageStart),
    activeModules: modules ?? allModules,
    workoutWeeklyTarget: target,
    hasApplicableGoalEver: goalsEver,
  );

  AnalysisFigure figure(AnalysisReport r, String key) => r.cards
      .expand((card) => card.figures)
      .firstWhere((figure) => figure.key == key);

  group('reference report of 7 days (all values computed by hand)', () {
    final r = report();

    test('header, previous period and cards in a fixed order', () {
      expect(r.periodText, '27.09. bis 03.10.2026, inklusive heute');
      expect(r.previousPeriodText, 'Vorherige 7 Tage: 20.09. bis 26.09.2026');
      expect(r.cards.map((card) => card.metric), [
        AnalysisMetric.dailyGoals,
        AnalysisMetric.steps,
        AnalysisMetric.water,
        AnalysisMetric.weight,
        AnalysisMetric.workouts,
        AnalysisMetric.focus,
        AnalysisMetric.tasks,
        AnalysisMetric.habits,
        AnalysisMetric.meals,
      ]);
      expect(r.workoutWeek, isNotNull);
      expect(r.hasCards, isTrue);
      expect(r.hasAnyData, isTrue);
      expect(r.noModuleActive, isFalse);
      expect(r.previousPeriodComparable, isTrue);
      expect(r.comparisonNote, isNull);
      expect(r.comparisonBaseProblem, isNull);
      for (final card in r.cards) {
        expect(card.hasData, isTrue, reason: card.title);
        expect(card.figures, isNotEmpty);
        expect(card.primary, same(card.figures.first));
        expect(card.semanticsLabel, isNotEmpty);
      }
    });

    test('card titles and owning modules', () {
      expect(r.cardFor(AnalysisMetric.steps)!.title, 'Schritte');
      expect(r.cardFor(AnalysisMetric.steps)!.module, ModuleId.body);
      expect(r.cardFor(AnalysisMetric.water)!.module, ModuleId.nutrition);
      expect(r.cardFor(AnalysisMetric.weight)!.module, ModuleId.body);
      expect(r.cardFor(AnalysisMetric.workouts)!.module, ModuleId.focus);
      expect(r.cardFor(AnalysisMetric.focus)!.title, 'Fokuszeit');
      expect(r.cardFor(AnalysisMetric.tasks)!.module, ModuleId.tasks);
      expect(r.cardFor(AnalysisMetric.habits)!.module, ModuleId.tasks);
      expect(r.cardFor(AnalysisMetric.meals)!.module, ModuleId.nutrition);
      expect(r.cardFor(AnalysisMetric.dailyGoals)!.module, isNull);
      expect(r.cardFor(AnalysisMetric.dailyGoals)!.title, 'Tagesziele');
      expect(r.cardFor(AnalysisMetric.workoutWeek), isNull);
    });

    test('steps: average over the 5 recorded days, coverage 5/7', () {
      final average = figure(r, AnalysisFigureKeys.stepsAverage);
      expect(average.label, 'Ø pro Tag');
      expect(average.currentText, '7.000');
      expect(average.previousText, '5.000');
      expect(average.current, 7000);
      expect(average.previous, 5000);
      expect(average.changeText, '+40$nb% (+2.000)');
      expect(
        average.comparisonText,
        '+40$nb% (+2.000) gegenüber den vorherigen 7 Tagen',
      );
      expect(average.coverage!.text, '5/7 Tage erfasst');
      expect(average.coverage!.spoken, 'an 5 von 7 Tagen erfasst');
      expect(average.previousCoverage!.text, '3/7 Tage erfasst');
      expect(average.explanation, isNull);
      expect(average.hasComparison, isTrue);
      final total = figure(r, AnalysisFigureKeys.stepsTotal);
      expect(total.currentText, '35.000');
      expect(total.previousText, '15.000');
      expect(total.isCompared, isFalse, reason: 'totals are not compared');
      expect(total.comparisonText, isNull);
      expect(total.changeText, '–');
      expect(total.comparison, isNull);
    });

    test('water: 1687.5 ml average over 4 recorded days', () {
      final average = figure(r, AnalysisFigureKeys.waterAverage);
      expect(average.currentText, '1,69${nb}l');
      expect(average.previousText, '1,5${nb}l');
      expect(average.changeText, '+13$nb% (+0,19${nb}l)');
      expect(average.coverage!.text, '4/7 Tage erfasst');
      expect(average.previousCoverage!.text, '2/7 Tage erfasst');
      final total = figure(r, AnalysisFigureKeys.waterTotal);
      expect(total.currentText, '6,75${nb}l');
      expect(total.previousText, '3${nb}l');
    });

    test('weight: change from the first to the last measured day', () {
      final change = figure(r, AnalysisFigureKeys.weightChange);
      expect(change.currentText, '${minus}0,3${nb}kg');
      expect(change.previousText, '${minus}0,5${nb}kg');
      expect(change.changeText, '+0,2${nb}kg');
      expect(change.coverage!.text, '3/7 Tage gemessen');
      expect(change.comparison!.percent, isNull, reason: 'never a percentage');
      final last = figure(r, AnalysisFigureKeys.weightLast);
      expect(last.currentText, '71,5${nb}kg');
      expect(last.previousText, '71,9${nb}kg');
      expect(last.changeText, '${minus}0,4${nb}kg');
      final card = r.cardFor(AnalysisMetric.weight)!;
      expect(
        card.details.single.text,
        'Von 71,8${nb}kg (27.09.) auf 71,5${nb}kg (03.10.)',
      );
      expect(
        card.details.single.spoken,
        'Von 71,8 Kilogramm am Sonntag, 27.09.2026 auf 71,5 Kilogramm am '
        'Samstag, 03.10.2026',
      );
    });

    test('workouts: count and minutes', () {
      final count = figure(r, AnalysisFigureKeys.workoutsCount);
      expect(count.currentText, '3');
      expect(count.previousText, '2');
      expect(count.changeText, '+50$nb% (+1)');
      final minutes = figure(r, AnalysisFigureKeys.workoutsMinutes);
      expect(minutes.currentText, '2${nb}h 15${nb}min');
      expect(minutes.previousText, '1${nb}h 30${nb}min');
      expect(minutes.changeText, '+50$nb% (+45${nb}min)');
    });

    test('focus: completed time and sessions', () {
      final time = figure(r, AnalysisFigureKeys.focusMinutes);
      expect(time.currentText, '1${nb}h 5${nb}min');
      expect(time.previousText, '50${nb}min');
      expect(time.changeText, '+30$nb% (+15${nb}min)');
      final sessions = figure(r, AnalysisFigureKeys.focusSessions);
      expect(sessions.currentText, '3');
      expect(sessions.previousText, '1');
      expect(sessions.changeText, '+200$nb% (+2)');
    });

    test('tasks: completed by completion day', () {
      final tasks = figure(r, AnalysisFigureKeys.tasksCompleted);
      expect(tasks.currentText, '6');
      expect(tasks.previousText, '4');
      expect(tasks.changeText, '+50$nb% (+2)');
    });

    test(
      'habits: fulfilled over applicable habit-days, in percentage points',
      () {
        final habits = figure(r, AnalysisFigureKeys.habitsFulfilment);
        expect(habits.currentText, '75$nb%');
        expect(habits.previousText, '29$nb%');
        expect(habits.changeText, '+46${nb}Prozentpunkte');
        expect(habits.coverage!.text, '6 von 8 Habit-Tagen erfüllt');
        expect(habits.previousCoverage!.text, '2 von 7 Habit-Tagen erfüllt');
        expect(habits.comparison!.percent, isNull);
      },
    );

    test('meals: count compared, calories only known values, incomplete', () {
      final count = figure(r, AnalysisFigureKeys.mealsCount);
      expect(count.currentText, '5');
      expect(count.previousText, '2');
      expect(count.changeText, '+150$nb% (+3)');
      final kcal = figure(r, AnalysisFigureKeys.mealsKcal);
      expect(kcal.currentText, '1.500${nb}kcal');
      expect(kcal.previousText, '1.000${nb}kcal');
      expect(kcal.changeText, 'Noch kein Vergleich');
      expect(kcal.comparison!.reason, NoComparisonReason.incompleteCalories);
      expect(
        kcal.explanation,
        'Kalorien sind nicht in beiden Zeiträumen vollständig.',
      );
      expect(
        kcal.coverage!.text,
        'Kalorien unvollständig: 4 von 5 Mahlzeiten mit Angabe',
      );
      expect(
        kcal.previousCoverage!.text,
        'Kalorien vollständig (2 Mahlzeiten)',
      );
      final card = r.cardFor(AnalysisMetric.meals)!;
      expect(card.statusText, 'Kalorien unvollständig');
      expect(
        card.details.single.text,
        '1 von 5 Mahlzeiten ohne Kalorienangabe. Die Summe enthält nur '
        'bekannte Werte.',
      );
    });

    test('daily goals: complete days kept apart from active days', () {
      final complete = figure(r, AnalysisFigureKeys.goalsComplete);
      expect(complete.currentText, '50$nb%');
      expect(complete.previousText, '29$nb%');
      expect(complete.changeText, '+21${nb}Prozentpunkte');
      expect(complete.coverage!.text, '3 von 6 Tagen komplett');
      expect(complete.previousCoverage!.text, '2 von 7 Tagen komplett');
      final active = figure(r, AnalysisFigureKeys.goalsActive);
      expect(active.currentText, '83$nb%');
      expect(active.previousText, '71$nb%');
      expect(active.changeText, '+12${nb}Prozentpunkte');
      expect(active.coverage!.text, '5 von 6 Tagen aktiv');
      expect(active.previousCoverage!.text, '5 von 7 Tagen aktiv');
      expect(r.current.goals.completeDays, 3);
      expect(r.current.goals.activeDays, 5);
    });

    test('the workout week is separate and compares week to date', () {
      final week = r.workoutWeek!;
      expect(week.entries, 3);
      expect(week.previousEntries, 2);
      expect(week.ringPercent, 100);
      expect(
        r.cards.map((card) => card.metric),
        isNot(contains(AnalysisMetric.workoutWeek)),
      );
    });

    test('every card sentence for screen readers carries the numbers', () {
      final steps = r.cardFor(AnalysisMetric.steps)!;
      expect(
        steps.semanticsLabel,
        'Schritte, Ø pro erfasstem Tag: 7.000 Schritte, an 5 von 7 Tagen '
        'erfasst. Vorherige 7 Tage: 5.000 Schritte, an 3 von 7 Tagen erfasst. '
        'plus 40 Prozent, plus 2.000 Schritte gegenüber den vorherigen 7 '
        'Tagen. '
        'Schritte, gesamt: 35.000 Schritte, an 5 von 7 Tagen erfasst. '
        'Vorherige 7 Tage: 15.000 Schritte, an 3 von 7 Tagen erfasst.',
      );
    });
  });

  group('periods of 30 and 90 days use their own base labels', () {
    for (final length in [
      AnalysisPeriodLength.days30,
      AnalysisPeriodLength.days90,
    ]) {
      test(
        '${length.days} days: "vorherige ${length.days} Tage", never "Vorwoche"',
        () {
          final n = length.days;
          // steps in both periods so that the comparison exists; the
          // reference days give the workout week its data
          final r = report(
            length: length,
            days: [
              ...referenceDays(),
              AnalysisDay(date: refToday.addDays(-3), stepsRecorded: 6000),
              AnalysisDay(date: refToday.addDays(-n - 3), stepsRecorded: 5000),
            ],
          );
          final steps = figure(r, AnalysisFigureKeys.stepsAverage);
          expect(steps.hasComparison, isTrue);
          expect(
            steps.comparisonText,
            endsWith('gegenüber den vorherigen $n Tagen'),
          );
          expect(steps.spokenText, contains('Vorherige ${length.days} Tage:'));
          expect(r.table.periodTable.headers, [
            'Kennzahl',
            'Letzte ${length.days} Tage',
            'Vorherige ${length.days} Tage',
            'Veränderung',
            'Erfassung',
          ]);
          for (final card in r.cards) {
            for (final f in card.figures) {
              expect(f.spokenText.toLowerCase(), isNot(contains('vorwoche')));
              expect(
                f.comparisonText?.toLowerCase() ?? '',
                isNot(contains('vorwoche')),
              );
            }
          }
          expect(
            r.workoutWeek!.countFigure.comparisonText,
            contains('Vorwoche'),
            reason: 'only the workout week card compares calendar weeks',
          );
        },
      );
    }

    test(
      '30 days: all reference data lies in the current period, none before',
      () {
        // current 30 days 09-04 .. 10-03 hold all 14 reference days, the
        // previous 30 days 08-05 .. 09-03 hold nothing: 8 recorded days with
        // 15000 + 35000 = 50000 steps, average 6250
        final r = report(length: AnalysisPeriodLength.days30);
        final steps = figure(r, AnalysisFigureKeys.stepsAverage);
        expect(steps.currentText, '6.250');
        expect(r.current.steps.recordedDays, 8);
        expect(r.previous.steps.hasData, isFalse);
        expect(steps.previousText, '–');
        expect(steps.comparison!.reason, NoComparisonReason.noPreviousData);
        expect(steps.changeText, 'Noch kein Vergleich');
      },
    );
  });

  group('usage window: the previous period must lie inside it', () {
    test('a previous period starting exactly on the usage start is fine', () {
      final r = report(usageStart: d2026(9, 20));
      expect(r.previousPeriodComparable, isTrue);
      expect(figure(r, AnalysisFigureKeys.stepsAverage).hasComparison, isTrue);
    });

    test('one day later every comparison reads "Noch kein Vergleich"', () {
      final r = report(usageStart: d2026(9, 21));
      expect(r.previousPeriodComparable, isFalse);
      expect(
        r.comparisonBaseProblem,
        NoComparisonReason.previousPeriodBeforeStart,
      );
      expect(
        r.comparisonNote,
        'Ein Vergleich mit den vorherigen 7 Tagen ist ab dem 04.10.2026 '
        'möglich.',
      );
      var compared = 0;
      for (final card in r.cards) {
        for (final f in card.figures) {
          if (!f.isCompared) {
            continue;
          }
          compared++;
          expect(f.hasComparison, isFalse, reason: f.key);
          expect(
            f.comparison!.reason,
            NoComparisonReason.previousPeriodBeforeStart,
            reason: f.key,
          );
          expect(f.changeText, 'Noch kein Vergleich', reason: f.key);
          expect(f.comparisonText, 'Noch kein Vergleich', reason: f.key);
          expect(
            f.explanation,
            'Der Vergleichszeitraum liegt nicht vollständig in der '
            'Nutzungszeit (Start: 21.09.2026).',
            reason: f.key,
          );
        }
      }
      expect(compared, 14, reason: 'all compared figures of the 9 cards');
    });

    test('the values of the current period are still shown', () {
      final r = report(usageStart: d2026(9, 27));
      final steps = figure(r, AnalysisFigureKeys.stepsAverage);
      expect(steps.currentText, '7.000');
      expect(steps.hasComparison, isFalse);
      expect(r.cardFor(AnalysisMetric.steps)!.hasData, isTrue);
    });

    test('a new profile of today: current period, no base', () {
      final r = report(usageStart: refToday);
      expect(r.previousPeriodComparable, isFalse);
      expect(r.workoutWeek!.countFigure.hasComparison, isFalse);
      expect(
        r.workoutWeek!.countFigure.comparison!.reason,
        NoComparisonReason.previousPeriodBeforeStart,
      );
    });

    test('an unknown usage start allows no comparison', () {
      final r = report(noUsageStart: true);
      expect(r.comparisonBaseProblem, NoComparisonReason.noUsageStart);
      expect(r.comparisonNote, 'Der Nutzungsstart ist noch nicht bekannt.');
      expect(figure(r, AnalysisFigureKeys.stepsAverage).hasComparison, isFalse);
    });

    test('30 and 90 day periods need a longer usage window', () {
      // usage start 2026-08-05: the previous 30 days start exactly there
      expect(
        report(
          length: AnalysisPeriodLength.days30,
          usageStart: d2026(8, 5),
        ).previousPeriodComparable,
        isTrue,
      );
      final late = report(
        length: AnalysisPeriodLength.days30,
        usageStart: d2026(8, 6),
      );
      expect(late.previousPeriodComparable, isFalse);
      expect(
        late.comparisonNote,
        'Ein Vergleich mit den vorherigen 30 Tagen ist ab dem 04.10.2026 '
        'möglich.',
        reason: '2026-08-06 + 59 days',
      );
      expect(
        report(
          length: AnalysisPeriodLength.days90,
          usageStart: d2026(4, 7),
        ).previousPeriodComparable,
        isTrue,
      );
      expect(
        report(
          length: AnalysisPeriodLength.days90,
          usageStart: d2026(4, 8),
        ).previousPeriodComparable,
        isFalse,
      );
    });
  });

  group('missing data on either side', () {
    test(
      'data only in the previous period: no comparison, empty current card',
      () {
        final r = report(
          days: referenceDays().where((d) => d.date.isBefore(d2026(9, 27))),
        );
        final steps = figure(r, AnalysisFigureKeys.stepsAverage);
        expect(r.cardFor(AnalysisMetric.steps)!.hasData, isFalse);
        expect(steps.currentText, '–');
        expect(steps.previousText, '5.000');
        expect(steps.comparison!.reason, NoComparisonReason.noCurrentData);
        expect(steps.changeText, 'Noch kein Vergleich');
        expect(
          steps.explanation,
          'Im aktuellen Zeitraum liegen keine Daten vor.',
        );
      },
    );

    test('data only in the current period: no comparison', () {
      final r = report(
        days: referenceDays().where((d) => !d.date.isBefore(d2026(9, 27))),
      );
      final steps = figure(r, AnalysisFigureKeys.stepsAverage);
      expect(steps.currentText, '7.000');
      expect(steps.previousText, '–');
      expect(steps.comparison!.reason, NoComparisonReason.noPreviousData);
      expect(
        steps.explanation,
        'Im Vergleichszeitraum liegen keine Daten vor.',
      );
    });

    test('a previous average of zero steps is a zero base', () {
      final r = report(
        days: [
          AnalysisDay(date: d2026(9, 21), stepsRecorded: 0),
          AnalysisDay(date: d2026(9, 22), stepsRecorded: 0),
          AnalysisDay(date: d2026(10, 3), stepsRecorded: 5000),
        ],
      );
      final steps = figure(r, AnalysisFigureKeys.stepsAverage);
      expect(steps.previousText, '0');
      expect(steps.current, 5000);
      expect(steps.comparison!.reason, NoComparisonReason.previousIsZero);
      expect(steps.changeText, 'Noch kein Vergleich');
      expect(steps.explanation, 'Der Vergleichswert ist 0.');
    });

    test(
      'a single weight measurement: the change reads "Noch kein Vergleich"',
      () {
        final r = report(
          days: [
            AnalysisDay(date: d2026(10, 1), weightGrams: 71500),
            AnalysisDay(date: d2026(9, 22), weightGrams: 72000),
            AnalysisDay(date: d2026(9, 24), weightGrams: 71800),
          ],
        );
        final change = figure(r, AnalysisFigureKeys.weightChange);
        expect(change.currentText, 'Noch kein Vergleich');
        expect(change.previousText, '${minus}0,2${nb}kg');
        expect(change.current, isNull);
        expect(change.comparison!.reason, NoComparisonReason.noCurrentData);
        final last = figure(r, AnalysisFigureKeys.weightLast);
        expect(last.currentText, '71,5${nb}kg');
        expect(last.changeText, '${minus}0,3${nb}kg');
        final card = r.cardFor(AnalysisMetric.weight)!;
        expect(card.hasData, isTrue);
        expect(card.details.single.text, 'Eine Messung: 71,5${nb}kg (01.10.)');
      },
    );

    test('no calories at all: no sum, never 0 kcal', () {
      final r = report(
        days: [
          AnalysisDay(date: d2026(10, 1), mealEntries: 2, mealsWithKcal: 0),
        ],
      );
      final kcal = figure(r, AnalysisFigureKeys.mealsKcal);
      expect(kcal.currentText, '–');
      expect(kcal.current, isNull);
      expect(
        kcal.coverage!.text,
        'Kalorien unvollständig: 0 von 2 Mahlzeiten mit Angabe',
      );
      final card = r.cardFor(AnalysisMetric.meals)!;
      expect(card.statusText, 'Kalorien unvollständig');
      expect(card.hasData, isTrue);
      expect(figure(r, AnalysisFigureKeys.mealsCount).currentText, '2');
    });

    test('a deliberate 0 kcal meal is a real 0', () {
      final r = report(
        days: [
          AnalysisDay(
            date: d2026(10, 1),
            mealEntries: 1,
            mealsWithKcal: 1,
            knownKcal: 0,
          ),
        ],
      );
      final kcal = figure(r, AnalysisFigureKeys.mealsKcal);
      expect(kcal.currentText, '0${nb}kcal');
      expect(
        r.cardFor(AnalysisMetric.meals)!.statusText,
        isNull,
        reason: 'complete',
      );
    });

    test('calories of two complete periods are compared', () {
      final r = report(
        days: [
          AnalysisDay(
            date: d2026(10, 1),
            mealEntries: 2,
            mealsWithKcal: 2,
            knownKcal: 1500,
          ),
          AnalysisDay(
            date: d2026(9, 24),
            mealEntries: 2,
            mealsWithKcal: 2,
            knownKcal: 1200,
          ),
        ],
      );
      final kcal = figure(r, AnalysisFigureKeys.mealsKcal);
      expect(kcal.changeText, '+25$nb% (+300${nb}kcal)');
    });

    test('calories with an incomplete previous period are not compared', () {
      final r = report(
        days: [
          AnalysisDay(
            date: d2026(10, 1),
            mealEntries: 2,
            mealsWithKcal: 2,
            knownKcal: 1500,
          ),
          AnalysisDay(
            date: d2026(9, 24),
            mealEntries: 2,
            mealsWithKcal: 1,
            knownKcal: 700,
          ),
        ],
      );
      expect(
        figure(r, AnalysisFigureKeys.mealsKcal).comparison!.reason,
        NoComparisonReason.incompleteCalories,
      );
      expect(
        figure(r, AnalysisFigureKeys.mealsCount).hasComparison,
        isTrue,
        reason: 'the meal count has no calorie problem',
      );
    });
  });

  group('module filter: only cards of active modules', () {
    List<AnalysisMetric> metrics(AnalysisReport r) =>
        r.cards.map((card) => card.metric).toList();

    test('only the body module', () {
      final r = report(modules: {ModuleId.body});
      expect(metrics(r), [
        AnalysisMetric.dailyGoals,
        AnalysisMetric.steps,
        AnalysisMetric.weight,
      ]);
      expect(r.workoutWeek, isNull);
      expect(r.charts.map((c) => c.metric), [
        AnalysisMetric.steps,
        AnalysisMetric.weight,
      ]);
    });

    test('only the nutrition module', () {
      final r = report(modules: {ModuleId.nutrition});
      expect(metrics(r), [
        AnalysisMetric.dailyGoals,
        AnalysisMetric.water,
        AnalysisMetric.meals,
      ]);
      expect(r.workoutWeek, isNull);
      expect(r.charts.map((c) => c.metric), [AnalysisMetric.water]);
    });

    test('only the focus module: focus time, workouts and the week card', () {
      final r = report(modules: {ModuleId.focus});
      expect(metrics(r), [
        AnalysisMetric.dailyGoals,
        AnalysisMetric.workouts,
        AnalysisMetric.focus,
      ]);
      expect(r.workoutWeek, isNotNull);
      expect(r.charts.map((c) => c.metric), [
        AnalysisMetric.workouts,
        AnalysisMetric.focus,
      ]);
    });

    test('only the tasks module: tasks and habits', () {
      final r = report(modules: {ModuleId.tasks});
      expect(metrics(r), [
        AnalysisMetric.dailyGoals,
        AnalysisMetric.tasks,
        AnalysisMetric.habits,
      ]);
      expect(r.workoutWeek, isNull);
      expect(r.charts.map((c) => c.metric), [
        AnalysisMetric.tasks,
        AnalysisMetric.habits,
      ]);
    });

    test('gamification has no analysis card', () {
      final r = report(modules: {ModuleId.gamification});
      expect(metrics(r), [AnalysisMetric.dailyGoals]);
      expect(r.charts, isEmpty);
      expect(r.workoutWeek, isNull);
    });

    test(
      'no module at all: only the goals card of the day statuses remains',
      () {
        final r = report(modules: const {});
        expect(r.noModuleActive, isTrue);
        expect(metrics(r), [AnalysisMetric.dailyGoals]);
        expect(r.charts, isEmpty);
        expect(r.workoutWeek, isNull);
        expect(r.table.weekTable, isNull);
        expect(r.table.dayTable.headers, ['Tagesziele']);
      },
    );

    test('the daily goals card needs at least one applicable goal ever', () {
      final without = report(goalsEver: false);
      expect(metrics(without), isNot(contains(AnalysisMetric.dailyGoals)));
      expect(without.cardFor(AnalysisMetric.dailyGoals), isNull);
      final noGoalsInData = report(
        days: referenceDays().map(
          (d) => AnalysisDay(date: d.date, stepsRecorded: d.stepsRecorded),
        ),
      );
      expect(
        metrics(noGoalsInData),
        isNot(contains(AnalysisMetric.dailyGoals)),
        reason: 'derived from the days when the flag is not given',
      );
      final withEver = report(goalsEver: true, days: const []);
      expect(metrics(withEver), contains(AnalysisMetric.dailyGoals));
      final goals = withEver.cardFor(AnalysisMetric.dailyGoals)!;
      expect(goals.hasData, isFalse);
      expect(goals.emptyText, 'Keine Tagesziele in diesem Zeitraum');
    });

    test('hidden modules keep their data in the typed aggregates', () {
      final r = report(modules: {ModuleId.tasks});
      expect(r.cardFor(AnalysisMetric.steps), isNull);
      expect(r.current.steps.totalSteps, 35000, reason: 'not deleted');
      expect(r.table.periodTable.rows.map((f) => f.metric).toSet(), {
        AnalysisMetric.dailyGoals,
        AnalysisMetric.tasks,
        AnalysisMetric.habits,
      });
    });
  });

  group('empty report: honest empty states', () {
    final empty = report(days: const [], goalsEver: true);

    test('no card has data and there is no fake number', () {
      expect(empty.hasAnyData, isFalse);
      expect(empty.cards, hasLength(9));
      for (final card in empty.cards) {
        expect(card.hasData, isFalse, reason: card.title);
        expect(
          card.emptyText,
          card.metric == AnalysisMetric.dailyGoals
              ? 'Keine Tagesziele in diesem Zeitraum'
              : 'Noch keine Daten',
        );
        expect(card.semanticsLabel, '${card.title}. ${card.emptyText}.');
        for (final f in card.figures) {
          expect(f.current, isNull, reason: f.key);
          expect(f.previous, isNull, reason: f.key);
          expect(f.currentText, '–', reason: f.key);
          expect(f.previousText, '–', reason: f.key);
          if (f.isCompared) {
            expect(f.changeText, 'Noch kein Vergleich', reason: f.key);
          }
        }
      }
    });

    test('goals that applied without anything recorded are no data', () {
      // a fresh start: the goals exist, nothing is done yet
      final fresh = report(
        days: [
          for (var i = 0; i < 14; i++)
            AnalysisDay(
              date: d2026(9, 20).addDays(i),
              applicableGoals: 5,
              fulfilledGoals: 0,
            ),
        ],
      );
      expect(fresh.cardFor(AnalysisMetric.dailyGoals)!.hasData, isTrue);
      expect(
        fresh.cardFor(AnalysisMetric.dailyGoals)!.primary.currentText,
        '0$nb%',
        reason: 'a true 0: the goals applied and none was complete',
      );
      expect(fresh.hasAnyData, isFalse, reason: 'nothing was recorded');
      final started = report(
        days: [
          for (var i = 0; i < 14; i++)
            AnalysisDay(
              date: d2026(9, 20).addDays(i),
              applicableGoals: 5,
              fulfilledGoals: i == 13 ? 1 : 0,
            ),
        ],
      );
      expect(
        started.hasAnyData,
        isTrue,
        reason: 'one goal was fulfilled today',
      );
    });

    test('the average is null, not 0, without recorded days', () {
      expect(empty.current.steps.average, isNull);
      expect(empty.current.water.average, isNull);
      expect(empty.current.weight.changeGrams, isNull);
      expect(empty.current.meals.kcalTotal, isNull);
      expect(empty.current.habits.ratioPercent, isNull);
    });

    test('the workout week still shows the ring at 0 of 3', () {
      final week = empty.workoutWeek!;
      expect(week.entries, 0);
      expect(week.ringPercent, 0);
      expect(week.progressText, '0 von 3 Workouts');
      expect(week.hasData, isFalse);
    });

    test('no sleep, kilometres or calories without data anywhere', () {
      final texts = _allTexts(empty);
      for (final text in texts) {
        expect(text, isNot(contains('0${nb}kcal')));
        expect(text.toLowerCase(), isNot(contains('schlaf')));
        expect(text.toLowerCase(), isNot(contains('kilometer')));
      }
    });
  });

  group('honesty rules for all texts of the reference report', () {
    final r = report();
    final texts = _allTexts(r);

    test('no sleep, no distance, no medical or judging words', () {
      expect(texts, isNotEmpty);
      const forbidden = [
        'schlaf',
        'kilometer',
        ' km',
        'gesund',
        'krank',
        'diagnose',
        'übergewicht',
        'abnehm',
        'zunehm',
        'gut',
        'schlecht',
        'leider',
        'super',
        'toll',
        'glückwunsch',
        'erfolg',
        'verfehlt',
        'versagt',
        'bmi',
      ];
      for (final text in texts) {
        final lower = text.toLowerCase();
        for (final word in forbidden) {
          expect(lower, isNot(contains(word)), reason: '"$word" in "$text"');
        }
      }
    });

    test('no emojis', () {
      for (final text in texts) {
        for (final rune in text.runes) {
          final isEmoji =
              (rune >= 0x1F000 && rune <= 0x1FAFF) ||
              (rune >= 0x2600 && rune <= 0x27BF && rune != 0x2713) ||
              (rune >= 0xFE00 && rune <= 0xFE0F);
          expect(
            isEmoji,
            isFalse,
            reason: 'U+${rune.toRadixString(16)} in "$text"',
          );
        }
      }
    });

    test('negative numbers use the true minus, never a hyphen', () {
      final negative = RegExp(r'(^|[\s(])-\d');
      for (final text in texts) {
        expect(negative.hasMatch(text), isFalse, reason: text);
      }
    });

    test('units are bound to their numbers by a no-break space', () {
      final loose = RegExp(r'\d (kg|ml|l|min|h|kcal|%)(?![A-Za-zäöüß])');
      for (final text in texts) {
        expect(loose.hasMatch(text), isFalse, reason: text);
      }
    });
  });

  group('purity and robustness', () {
    test('the same inputs give the same report', () {
      final a = report();
      final b = report();
      expect(_allTexts(a), _allTexts(b));
    });

    test('the input order does not matter', () {
      final a = report();
      final b = report(days: referenceDays().reversed);
      expect(_allTexts(a), _allTexts(b));
    });

    test(
      'a date given twice: the last entry wins, nothing is counted twice',
      () {
        final days = [
          ...referenceDays(),
          AnalysisDay(date: d2026(10, 3), stepsRecorded: 1000),
        ];
        final r = report(days: days);
        expect(r.current.steps.totalSteps, 35000 - 9000 + 1000);
        expect(r.current.steps.recordedDays, 5);
      },
    );

    test('days outside the two periods are ignored', () {
      final days = [
        ...referenceDays(),
        AnalysisDay(date: d2026(9, 19), stepsRecorded: 99999),
        AnalysisDay(date: d2026(10, 4), stepsRecorded: 99999),
      ];
      final r = report(days: days);
      expect(r.current.steps.totalSteps, 35000);
      expect(r.previous.steps.totalSteps, 15000);
    });

    test(
      'periods include the boundary days -6/-29/-89 and exclude -7/-30/-90',
      () {
        for (final length in AnalysisPeriodLength.values) {
          final n = length.days;
          final r = report(
            length: length,
            days: [
              AnalysisDay(date: refToday.addDays(-(n - 1)), stepsRecorded: 100),
              AnalysisDay(date: refToday.addDays(-n), stepsRecorded: 7),
              AnalysisDay(
                date: refToday.addDays(-(2 * n - 1)),
                stepsRecorded: 5,
              ),
              AnalysisDay(
                date: refToday.addDays(-(2 * n)),
                stepsRecorded: 3000,
              ),
            ],
          );
          expect(
            r.current.steps.totalSteps,
            100,
            reason: '$n days: day -${n - 1}',
          );
          expect(r.current.steps.recordedDays, 1);
          expect(
            r.previous.steps.totalSteps,
            12,
            reason: '$n days: -$n and -${2 * n - 1}',
          );
          expect(r.previous.steps.recordedDays, 2);
        }
      },
    );
  });
}

/// Every visible and spoken text of the report (cards, figures, details,
/// week card, charts, tables).
List<String> _allTexts(AnalysisReport report) {
  final texts = <String>[
    report.periodText,
    report.previousPeriodText,
    ?report.comparisonNote,
  ];
  void addFigure(AnalysisFigure f) {
    texts
      ..add(f.label)
      ..add(f.tableLabel)
      ..add(f.currentText)
      ..add(f.previousText)
      ..add(f.changeText)
      ..add(f.spokenText);
    if (f.comparisonText != null) {
      texts.add(f.comparisonText!);
    }
    if (f.explanation != null) {
      texts.add(f.explanation!);
    }
    if (f.coverage != null) {
      texts
        ..add(f.coverage!.text)
        ..add(f.coverage!.spoken);
    }
    if (f.previousCoverage != null) {
      texts
        ..add(f.previousCoverage!.text)
        ..add(f.previousCoverage!.spoken);
    }
  }

  for (final AnalysisCard card in report.cards) {
    texts
      ..add(card.title)
      ..add(card.emptyText)
      ..add(card.semanticsLabel)
      ..addAll(card.details.expand((line) => [line.text, line.spoken]));
    if (card.statusText != null) {
      texts.add(card.statusText!);
    }
    card.figures.forEach(addFigure);
  }
  final week = report.workoutWeek;
  if (week != null) {
    texts
      ..add(week.title)
      ..add(week.progressText)
      ..add(week.rangeText)
      ..add(week.previousRangeText)
      ..add(week.semanticsLabel);
    week.figures.forEach(addFigure);
  }
  for (final series in report.charts) {
    texts
      ..add(series.title)
      ..add(series.summary)
      ..addAll(
        series.points.expand(
          (point) => [point.valueText, point.semanticsLabel, point.dayLabel],
        ),
      );
  }
  final table = report.table;
  texts
    ..add(table.periodTable.caption)
    ..addAll(table.periodTable.headers)
    ..add(table.dayTable.caption)
    ..addAll(table.dayTable.headers);
  if (table.weekTable != null) {
    texts
      ..add(table.weekTable!.caption)
      ..addAll(table.weekTable!.headers);
  }
  for (final row in table.dayTable.rows) {
    texts
      ..add(row.dayText)
      ..add(row.semanticsLabel)
      ..addAll(row.cells.expand((cell) => [cell.text, cell.spoken]));
  }
  return texts;
}
