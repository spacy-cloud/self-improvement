import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/core/analysis/domain/period_stats.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  final start = d2026(9, 27);
  final end = d2026(10, 3);
  final previousStart = d2026(9, 20);
  final previousEnd = d2026(9, 26);

  PeriodStats stats(
    Iterable<AnalysisDay> days, {
    LocalDate? from,
    LocalDate? to,
  }) => computePeriodStats(days: days, start: from ?? start, end: to ?? end);

  AnalysisDay day(
    int month,
    int dayOfMonth, {
    int? steps,
    int waterMl = 0,
    int waterEntries = 0,
    int? weight,
    int workouts = 0,
    int workoutMinutes = 0,
    int focusSeconds = 0,
    int focusSessions = 0,
    int tasks = 0,
    int meals = 0,
    int mealsWithKcal = 0,
    int kcal = 0,
    int goals = 0,
    int fulfilled = 0,
    int habits = 0,
    int habitsDone = 0,
  }) => AnalysisDay(
    date: d2026(month, dayOfMonth),
    stepsRecorded: steps,
    waterMl: waterMl,
    waterEntries: waterEntries,
    weightGrams: weight,
    workoutEntries: workouts,
    workoutMinutes: workoutMinutes,
    focusCompletedSeconds: focusSeconds,
    focusCompletedSessions: focusSessions,
    tasksCompleted: tasks,
    mealEntries: meals,
    mealsWithKcal: mealsWithKcal,
    knownKcal: kcal,
    applicableGoals: goals,
    fulfilledGoals: fulfilled,
    applicableHabits: habits,
    fulfilledHabits: habitsDone,
  );

  group('reference scenario (hand computed)', () {
    final all = referenceDays();
    final current = stats(all);
    final previous = stats(all, from: previousStart, to: previousEnd);

    test('period length', () {
      expect(current.periodDays, 7);
      expect(previous.periodDays, 7);
    });

    test('steps: a recorded zero counts, missing days do not', () {
      expect(current.steps.recordedDays, 5);
      expect(current.steps.unrecordedDays, 2);
      expect(current.steps.totalSteps, 35000);
      expect(current.steps.average, 7000);
      expect(current.steps.averageRounded, 7000);
      expect(previous.steps.recordedDays, 3);
      expect(previous.steps.totalSteps, 15000);
      expect(previous.steps.average, 5000);
    });

    test('water: average over recorded days only', () {
      expect(current.water.recordedDays, 4);
      expect(current.water.totalMl, 6750);
      expect(current.water.average, 1687.5);
      expect(current.water.averageRounded, 1688);
      expect(previous.water.recordedDays, 2);
      expect(previous.water.totalMl, 3000);
      expect(previous.water.average, 1500);
    });

    test('weight: first to last measured day', () {
      expect(current.weight.measuredDays, 3);
      expect(current.weight.first!.date, d2026(9, 27));
      expect(current.weight.first!.grams, 71800);
      expect(current.weight.last!.date, d2026(10, 3));
      expect(current.weight.last!.grams, 71500);
      expect(current.weight.changeGrams, -300);
      expect(previous.weight.measuredDays, 2);
      expect(previous.weight.first!.grams, 72400);
      expect(previous.weight.last!.grams, 71900);
      expect(previous.weight.changeGrams, -500);
    });

    test('workouts, focus and tasks', () {
      expect(current.workouts.entries, 3);
      expect(current.workouts.minutes, 135);
      expect(current.workouts.activeDays, 2);
      expect(previous.workouts.entries, 2);
      expect(previous.workouts.minutes, 90);

      expect(current.focus.completedSessions, 3);
      expect(current.focus.completedSeconds, 3900);
      expect(current.focus.completedMinutes, 65);
      expect(current.focus.activeDays, 3);
      expect(previous.focus.completedSessions, 1);
      expect(previous.focus.completedSeconds, 3000);

      expect(current.tasks.completed, 6);
      expect(current.tasks.activeDays, 3);
      expect(previous.tasks.completed, 4);
    });

    test('habits: fulfilled over applicable habit-days', () {
      expect(current.habits.applicableHabitDays, 8);
      expect(current.habits.fulfilledHabitDays, 6);
      expect(current.habits.ratioPercent, 75);
      expect(current.habits.ratioPercentRounded, 75);
      expect(previous.habits.applicableHabitDays, 7);
      expect(previous.habits.fulfilledHabitDays, 2);
      expect(previous.habits.ratioPercentRounded, 29, reason: '28.57 %');
    });

    test('meals: known kcal and completeness', () {
      expect(current.meals.meals, 5);
      expect(current.meals.mealsWithKcal, 4);
      expect(current.meals.mealsWithoutKcal, 1);
      expect(current.meals.knownKcal, 1500);
      expect(current.meals.kcalTotal, 1500);
      expect(current.meals.completeness, MealCompleteness.incomplete);
      expect(current.meals.daysWithMeals, 2);
      expect(previous.meals.meals, 2);
      expect(previous.meals.kcalTotal, 1000);
      expect(previous.meals.completeness, MealCompleteness.complete);
    });

    test('daily goals: complete days are not active days', () {
      expect(current.goals.daysWithGoals, 6, reason: '09-27 has no goal');
      expect(current.goals.completeDays, 3);
      expect(current.goals.activeDays, 5);
      expect(current.goals.completeRatioFraction!.value, 50);
      expect(current.goals.activeRatioFraction!.value, closeTo(83.3333, 1e-3));
      expect(previous.goals.daysWithGoals, 7);
      expect(previous.goals.completeDays, 2);
      expect(previous.goals.activeDays, 5);
      expect(previous.goals.completeRatioFraction!.rounded, 29);
      expect(previous.goals.activeRatioFraction!.rounded, 71);
    });
  });

  group('steps', () {
    test('a recorded zero is recorded and lowers the average', () {
      final result = stats([day(9, 27, steps: 0), day(9, 28, steps: 6000)])
          .steps;
      expect(result.recordedDays, 2);
      expect(result.totalSteps, 6000);
      expect(result.average, 3000, reason: '6000 / 2 recorded days');
    });

    test('without a recorded day there is no average, never a fake 0', () {
      final result = stats([day(9, 28), day(9, 29)]).steps;
      expect(result.hasData, isFalse);
      expect(result.recordedDays, 0);
      expect(result.totalSteps, 0);
      expect(result.average, isNull);
      expect(result.averageRounded, isNull);
      expect(result.averageFraction, isNull);
    });

    test('the average is not divided by the period length', () {
      final result = stats([day(10, 3, steps: 7000)]).steps;
      expect(result.periodDays, 7);
      expect(result.average, 7000, reason: 'not 7000 / 7');
      expect(result.unrecordedDays, 6);
    });

    test('the average rounds half up to whole steps', () {
      expect(
        stats([day(9, 27, steps: 3), day(9, 28, steps: 2)])
            .steps
            .averageRounded,
        3,
        reason: '2.5 -> 3',
      );
      expect(
        stats([
          day(9, 27, steps: 1),
          day(9, 28, steps: 1),
          day(9, 29, steps: 2),
        ]).steps.averageRounded,
        1,
        reason: '1.33 -> 1',
      );
    });
  });

  group('water', () {
    test('recorded means at least one entry, the day total is the sum', () {
      final result = stats([
        day(9, 27, waterMl: 750, waterEntries: 3),
        day(9, 28),
        day(9, 29, waterMl: 250, waterEntries: 1),
      ]).water;
      expect(result.recordedDays, 2);
      expect(result.totalMl, 1000);
      expect(result.average, 500);
    });

    test('no entry in the period: no average', () {
      final result = stats([day(9, 27, steps: 5)]).water;
      expect(result.hasData, isFalse);
      expect(result.average, isNull);
      expect(result.totalMl, 0);
    });
  });

  group('weight', () {
    test('a single measurement gives no change', () {
      final result = stats([day(10, 1, weight: 71500)]).weight;
      expect(result.measuredDays, 1);
      expect(result.hasData, isTrue);
      expect(result.first!.grams, 71500);
      expect(result.last!.grams, 71500);
      expect(result.changeGrams, isNull);
    });

    test('no measurement: no values at all, no zero', () {
      final result = stats([day(10, 1)]).weight;
      expect(result.hasData, isFalse);
      expect(result.first, isNull);
      expect(result.last, isNull);
      expect(result.changeGrams, isNull);
    });

    test('gaps between measured days are ignored', () {
      final result = stats([
        day(9, 27, weight: 71800),
        day(9, 29),
        day(9, 30),
        day(10, 2, weight: 71200),
      ]).weight;
      expect(result.measuredDays, 2);
      expect(result.changeGrams, -600);
    });

    test('first and last come from the dates, not from the input order', () {
      final result = stats([
        day(10, 3, weight: 71000),
        day(9, 27, weight: 72000),
        day(9, 30, weight: 99999),
      ]).weight;
      expect(result.first!.date, d2026(9, 27));
      expect(result.last!.date, d2026(10, 3));
      expect(result.changeGrams, -1000);
    });

    test('an increase is a positive change', () {
      expect(
        stats([day(9, 27, weight: 70000), day(10, 3, weight: 70500)])
            .weight
            .changeGrams,
        500,
      );
    });
  });

  group('workouts, focus, tasks', () {
    test('workouts are counted and summed; focus time is separate', () {
      final result = stats([
        day(9, 28, workouts: 2, workoutMinutes: 75),
        day(9, 29, workouts: 1, workoutMinutes: 20),
        day(9, 30, focusSessions: 1, focusSeconds: 1500),
      ]);
      expect(result.workouts.entries, 3);
      expect(result.workouts.minutes, 95);
      expect(result.workouts.activeDays, 2);
      expect(result.focus.completedSeconds, 1500);
      expect(result.focus.completedSessions, 1);
    });

    test('empty periods have no data', () {
      final result = stats(const []);
      expect(result.workouts.hasData, isFalse);
      expect(result.focus.hasData, isFalse);
      expect(result.tasks.hasData, isFalse);
      expect(result.habits.hasData, isFalse);
      expect(result.meals.hasData, isFalse);
      expect(result.goals.hasData, isFalse);
      expect(result.steps.hasData, isFalse);
      expect(result.water.hasData, isFalse);
      expect(result.weight.hasData, isFalse);
    });

    test('focus minutes are whole completed minutes', () {
      final result = stats([day(9, 28, focusSessions: 1, focusSeconds: 119)])
          .focus;
      expect(result.completedMinutes, 1);
      expect(
        stats([day(9, 28, focusSessions: 1, focusSeconds: 59)])
            .focus
            .completedMinutes,
        0,
      );
    });
  });

  group('habits', () {
    test('a habit that starts inside the period counts from its start day', () {
      // H1 applies on all 7 days, H2 starts on 09-30 (4 days): 3 x 1 + 4 x 2
      // = 11 applicable habit-days; one fulfilled habit on each day = 7.
      final result = stats([
        AnalysisDay(
          date: d2026(9, 27),
          applicableHabits: 1,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(9, 28),
          applicableHabits: 1,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(9, 29),
          applicableHabits: 1,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(9, 30),
          applicableHabits: 2,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(10, 1),
          applicableHabits: 2,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(10, 2),
          applicableHabits: 2,
          fulfilledHabits: 1,
        ),
        AnalysisDay(
          date: d2026(10, 3),
          applicableHabits: 2,
          fulfilledHabits: 1,
        ),
      ]).habits;
      expect(result.applicableHabitDays, 11);
      expect(result.fulfilledHabitDays, 7);
      expect(result.ratioPercentRounded, 64, reason: '7/11 = 63.64 %');
    });

    test('the ratio is 100 percent only when every habit-day is fulfilled', () {
      int? percent(int fulfilled, int applicable) => HabitStats(
        applicableHabitDays: applicable,
        fulfilledHabitDays: fulfilled,
      ).ratioPercentRounded;
      expect(percent(449, 450), 99, reason: '99,78 would round up to 100');
      expect(percent(199, 200), 99, reason: '99,5 would round up to 100');
      expect(percent(450, 450), 100);
      expect(percent(0, 10), 0);
    });

    test(
      'a habit archived inside the period stops counting after archiving',
      () {
        // Archived from 10-01 on (archiving takes effect tomorrow): applicable
        // on 09-27 .. 09-30 only.
        final result = stats([
          AnalysisDay(
            date: d2026(9, 27),
            applicableHabits: 1,
            fulfilledHabits: 1,
          ),
          AnalysisDay(
            date: d2026(9, 28),
            applicableHabits: 1,
            fulfilledHabits: 0,
          ),
          AnalysisDay(
            date: d2026(9, 29),
            applicableHabits: 1,
            fulfilledHabits: 1,
          ),
          AnalysisDay(
            date: d2026(9, 30),
            applicableHabits: 1,
            fulfilledHabits: 1,
          ),
          AnalysisDay(date: d2026(10, 1)),
          AnalysisDay(date: d2026(10, 2)),
          AnalysisDay(date: d2026(10, 3)),
        ]).habits;
        expect(result.applicableHabitDays, 4);
        expect(result.fulfilledHabitDays, 3);
        expect(result.ratioPercent, 75);
      },
    );

    test('days without an applicable habit (module off) add nothing', () {
      final result = stats([
        AnalysisDay(
          date: d2026(9, 27),
          applicableHabits: 1,
          fulfilledHabits: 1,
        ),
        AnalysisDay(date: d2026(9, 28)),
        AnalysisDay(date: d2026(9, 29)),
      ]).habits;
      expect(result.applicableHabitDays, 1);
      expect(result.fulfilledHabitDays, 1);
      expect(result.ratioPercent, 100);
    });

    test('no applicable habit-day: no ratio, not 0 percent', () {
      final result = stats([day(9, 27)]).habits;
      expect(result.hasData, isFalse);
      expect(result.ratioPercent, isNull);
      expect(result.ratioPercentRounded, isNull);
      expect(result.ratioPercentFraction, isNull);
    });
  });

  group('meals', () {
    test('no meal: status none, no kcal sum', () {
      final result = stats([day(9, 27)]).meals;
      expect(result.completeness, MealCompleteness.none);
      expect(result.meals, 0);
      expect(result.kcalTotal, isNull);
      expect(result.hasData, isFalse);
    });

    test('all meals with kcal: complete, sum of the values', () {
      final result = stats([
        day(9, 28, meals: 2, mealsWithKcal: 2, kcal: 900),
        day(9, 29, meals: 1, mealsWithKcal: 1, kcal: 450),
      ]).meals;
      expect(result.completeness, MealCompleteness.complete);
      expect(result.kcalTotal, 1350);
      expect(result.mealsWithoutKcal, 0);
    });

    test('one meal without kcal makes the period incomplete', () {
      final result = stats([day(9, 28, meals: 3, mealsWithKcal: 2, kcal: 1200)])
          .meals;
      expect(result.completeness, MealCompleteness.incomplete);
      expect(result.kcalTotal, 1200, reason: 'only the known values');
      expect(result.mealsWithoutKcal, 1);
    });

    test('all meals without kcal: incomplete and NO sum (null, not 0)', () {
      final result = stats([day(9, 28, meals: 2), day(9, 29, meals: 1)]).meals;
      expect(result.completeness, MealCompleteness.incomplete);
      expect(result.meals, 3);
      expect(result.kcalTotal, isNull);
    });

    test('a deliberate 0 kcal is a known value: the sum is a real 0', () {
      final result = stats([day(9, 28, meals: 1, mealsWithKcal: 1, kcal: 0)])
          .meals;
      expect(result.completeness, MealCompleteness.complete);
      expect(result.kcalTotal, 0);
    });
  });

  group('daily goals', () {
    test('complete and active days stay strictly apart', () {
      final result = stats([
        day(9, 27, goals: 5, fulfilled: 5), // complete
        day(9, 28, goals: 5, fulfilled: 4), // active only
        day(9, 29, goals: 5, fulfilled: 1), // active only
        day(9, 30, goals: 5, fulfilled: 0), // neither
      ]).goals;
      expect(result.daysWithGoals, 4);
      expect(result.completeDays, 1);
      expect(result.activeDays, 3);
      expect(result.completeRatioFraction!.value, 25);
      expect(result.activeRatioFraction!.value, 75);
    });

    test(
      'days without an applicable goal are no complete day and no denominator',
      () {
        final result = stats([
          day(9, 27),
          day(9, 28, goals: 1, fulfilled: 1),
          day(9, 29),
        ]).goals;
        expect(result.daysWithGoals, 1);
        expect(result.completeDays, 1);
        expect(result.activeDays, 1);
        expect(result.completeRatioFraction!.value, 100);
      },
    );

    test('no goal in the period: no ratio', () {
      final result = stats([day(9, 27), day(9, 28)]).goals;
      expect(result.hasData, isFalse);
      expect(result.completeRatioFraction, isNull);
      expect(result.activeRatioFraction, isNull);
    });
  });

  group('range handling', () {
    test('days outside the range are ignored', () {
      final result = stats([
        day(9, 26, steps: 99999), // one day before the range
        day(9, 27, steps: 1000), // first day
        day(10, 3, steps: 2000), // last day
        day(10, 4, steps: 99999), // one day after the range
      ]).steps;
      expect(result.recordedDays, 2);
      expect(result.totalSteps, 3000);
    });

    test('Fraction rounds half away from zero exactly', () {
      expect(const Fraction(7, 2).rounded, 4);
      expect(const Fraction(-7, 2).rounded, -4);
      expect(const Fraction(5, 3).rounded, 2);
      expect(const Fraction(1, 3).rounded, 0);
      expect(const Fraction(-1, 3).rounded, 0);
      expect(const Fraction(1, 2).rounded, 1);
      expect(const Fraction(0, 5).rounded, 0);
      expect(const Fraction(1, 4).value, 0.25);
      expect(roundedQuotient(125, 10), 13);
    });
  });
}
