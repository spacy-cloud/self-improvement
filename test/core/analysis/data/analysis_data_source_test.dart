import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/data/analysis_data_source.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'analysis_db_helpers.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final today = LocalDate(2026, 10, 3);
  LocalDate d(int month, int day) => LocalDate(2026, month, day);

  AnalysisPeriodSpec period(AnalysisPeriodLength length, [LocalDate? anchor]) =>
      AnalysisPeriodSpec(length: length, today: anchor ?? today);

  final days7 = period(AnalysisPeriodLength.days7);

  late DataHarness harness;
  late AnalysisDb db;
  late AnalysisDataSource source;

  /// A harness whose profile (and module / goal seed rows) is older than the
  /// fixed "now" of the tests, like in a real installation.
  Future<void> startHarness({
    String seededAt = '2026-09-01T06:00:00Z',
    String nowIso = '2026-10-03T08:00:00Z',
    LocalDate? startedOn,
    Set<String>? enabledModules,
  }) async {
    harness = await DataHarness.create(nowIso: seededAt);
    await harness.seedOnboarded(
      startedOn: startedOn ?? d(9, 1),
      enabledModules: enabledModules,
    );
    harness.clock.setNow(DateTime.parse(nowIso));
    db = AnalysisDb(harness);
    source = db.source();
  }

  setUp(startHarness);
  tearDown(() => harness.dispose());

  AnalysisDay dayOf(AnalysisInputs inputs, LocalDate date) =>
      inputs.days.singleWhere((day) => day.date == date);

  group('window', () {
    test(
      'one dense entry per day of the combined range, oldest first',
      () async {
        final inputs = await source.load(days7);
        expect(inputs.days, hasLength(14));
        expect(inputs.days.first.date, d(9, 20));
        expect(inputs.days.last.date, today);
        for (var i = 1; i < inputs.days.length; i++) {
          expect(inputs.days[i - 1].date.addDays(1), inputs.days[i].date);
        }
        expect(inputs.period, days7);
      },
    );

    test(
      'an empty database gives empty days with the seeded goals only',
      () async {
        final inputs = await source.load(days7);
        for (final day in inputs.days) {
          expect(day.stepsRecorded, isNull);
          expect(day.waterEntries, 0);
          expect(day.weightGrams, isNull);
          expect(day.workoutEntries, 0);
          expect(day.focusCompletedSessions, 0);
          expect(day.tasksCompleted, 0);
          expect(day.mealEntries, 0);
          expect(
            day.applicableGoals,
            5,
            reason: '${day.date}: five daily goals',
          );
          expect(day.fulfilledGoals, 0);
          expect(day.applicableHabits, 0);
        }
        final report = inputs.toReport();
        expect(report.hasAnyData, isFalse);
        expect(report.current.goals.daysWithGoals, 7);
        expect(report.current.goals.completeDays, 0);
        expect(report.current.goals.activeDays, 0);
      },
    );

    for (final length in AnalysisPeriodLength.values) {
      final n = length.days;
      test(
        '$n days: day -${n - 1} and -$n are loaded, -${2 * n - 1} is the first, -${2 * n} is not',
        () async {
          await harness.dispose();
          await startHarness(startedOn: today.addDays(-(2 * n + 5)));
          final spec = period(length);
          await db.steps(today.addDays(-(2 * n)), 1); // outside: never loaded
          await db.steps(today.addDays(-(2 * n - 1)), 2); // first previous day
          await db.steps(today.addDays(-n), 4); // last previous day
          await db.steps(today.addDays(-(n - 1)), 8); // first current day
          await db.steps(today, 16); // today
          final inputs = await source.load(spec);
          expect(inputs.days, hasLength(2 * n));
          expect(inputs.days.first.date, today.addDays(-(2 * n - 1)));
          expect(inputs.days.first.stepsRecorded, 2);
          expect(inputs.days[n - 1].date, today.addDays(-n));
          expect(inputs.days[n - 1].stepsRecorded, 4);
          expect(inputs.days[n].date, today.addDays(-(n - 1)));
          expect(inputs.days[n].stepsRecorded, 8);
          expect(inputs.days.last.stepsRecorded, 16);
          expect(
            inputs.days.where((day) => day.stepsRecorded != null),
            hasLength(4),
            reason: 'the row 2N days back is not part of the window',
          );
          final report = inputs.toReport();
          expect(report.current.steps.totalSteps, 8 + 16);
          expect(report.current.steps.recordedDays, 2);
          expect(report.previous.steps.totalSteps, 2 + 4);
          expect(report.previous.steps.recordedDays, 2);
        },
      );
    }
  });

  group('facts per table', () {
    test(
      'steps: a recorded 0 is a value, a deleted record is not recorded',
      () async {
        await db.steps(d(9, 27), 0);
        await db.steps(d(9, 28), 7450);
        await db.steps(d(9, 29), 99999, deleted: true);
        final inputs = await source.load(days7);
        expect(dayOf(inputs, d(9, 27)).stepsRecorded, 0);
        expect(dayOf(inputs, d(9, 27)).stepsAreRecorded, isTrue);
        expect(dayOf(inputs, d(9, 28)).stepsRecorded, 7450);
        expect(dayOf(inputs, d(9, 29)).stepsRecorded, isNull);
        expect(dayOf(inputs, d(9, 30)).stepsRecorded, isNull);
      },
    );

    test('water: sum and number of the active entries only', () async {
      await db.water(d(9, 28), 250);
      await db.water(d(9, 28), 500);
      await db.water(d(9, 28), 2000, deleted: true);
      await db.water(d(9, 29), 1000, deleted: true);
      final inputs = await source.load(days7);
      final monday = dayOf(inputs, d(9, 28));
      expect(monday.waterMl, 750);
      expect(monday.waterEntries, 2);
      expect(monday.waterIsRecorded, isTrue);
      final tuesday = dayOf(inputs, d(9, 29));
      expect(tuesday.waterMl, 0);
      expect(tuesday.waterEntries, 0);
      expect(tuesday.waterIsRecorded, isFalse, reason: 'only a deleted entry');
    });

    test(
      'weight: the last measurement of the day, whatever the insert order',
      () async {
        await db.weight(
          d(9, 27),
          71800,
          occurredAt: DateTime.utc(2026, 9, 27, 18),
        );
        await db.weight(
          d(9, 27),
          71900,
          occurredAt: DateTime.utc(2026, 9, 27, 6),
        );
        await db.weight(
          d(9, 27),
          99900,
          occurredAt: DateTime.utc(2026, 9, 27, 20),
          deleted: true,
        );
        await db.weight(d(9, 28), 71700);
        await db.weight(d(9, 29), 99900, deleted: true);
        final inputs = await source.load(days7);
        expect(dayOf(inputs, d(9, 27)).weightGrams, 71800);
        expect(dayOf(inputs, d(9, 28)).weightGrams, 71700);
        expect(dayOf(inputs, d(9, 29)).weightGrams, isNull);
      },
    );

    test('workouts: number and minutes of the active entries', () async {
      await db.workout(d(10, 1), 30);
      await db.workout(d(10, 1), 60);
      await db.workout(d(10, 1), 120, deleted: true);
      await db.workout(d(10, 2), 45);
      final inputs = await source.load(days7);
      expect(dayOf(inputs, d(10, 1)).workoutEntries, 2);
      expect(dayOf(inputs, d(10, 1)).workoutMinutes, 90);
      expect(dayOf(inputs, d(10, 2)).workoutEntries, 1);
      expect(dayOf(inputs, d(10, 2)).workoutMinutes, 45);
      expect(dayOf(inputs, d(10, 3)).workoutEntries, 0);
      expect(
        dayOf(inputs, d(10, 1)).focusCompletedSeconds,
        0,
        reason: 'workouts are not focus time',
      );
    });

    test(
      'focus: completed sessions only, counted on their completion day',
      () async {
        // completed on 09-28
        await db.focus(seconds: 1500, completedOn: d(9, 28));
        // started 23:50 local on 09-30, confirmed on 10-01: counts on 10-01
        await db.focus(
          seconds: 900,
          completedOn: d(10, 1),
          startedAt: DateTime.utc(2026, 9, 30, 21, 50),
        );
        // not counted: discarded, open, deleted
        await db.focus(seconds: 1000, status: 'discarded');
        await db.focus(seconds: 300, status: 'paused');
        await db.focus(seconds: 999, completedOn: d(9, 28), deleted: true);
        final inputs = await source.load(days7);
        expect(dayOf(inputs, d(9, 28)).focusCompletedSeconds, 1500);
        expect(dayOf(inputs, d(9, 28)).focusCompletedSessions, 1);
        expect(dayOf(inputs, d(9, 30)).focusCompletedSessions, 0);
        expect(dayOf(inputs, d(10, 1)).focusCompletedSeconds, 900);
        expect(dayOf(inputs, d(10, 1)).focusCompletedSessions, 1);
        expect(
          inputs.days.fold<int>(
            0,
            (sum, day) => sum + day.focusCompletedSessions,
          ),
          2,
        );
      },
    );

    test(
      'tasks: by current completion date, open and deleted ones excluded',
      () async {
        await db.task(completedOn: d(9, 28));
        await db.task(completedOn: d(9, 28));
        await db.task(completedOn: d(9, 30));
        await db.task(completedOn: d(10, 1), deleted: true);
        await db.task(); // open (or reopened): no completion
        final inputs = await source.load(days7);
        expect(dayOf(inputs, d(9, 28)).tasksCompleted, 2);
        expect(dayOf(inputs, d(9, 30)).tasksCompleted, 1);
        expect(dayOf(inputs, d(10, 1)).tasksCompleted, 0);
        expect(
          inputs.days.fold<int>(0, (sum, day) => sum + day.tasksCompleted),
          3,
        );
      },
    );

    test(
      'meals: count, meals with kcal and the sum of the known values',
      () async {
        await db.meal(d(9, 28), kcal: 500);
        await db.meal(d(9, 28), kcal: 700);
        await db.meal(d(9, 28)); // no kcal
        await db.meal(d(10, 1), kcal: 0); // a deliberate 0
        await db.meal(d(10, 1), kcal: 300);
        await db.meal(d(10, 2), kcal: 999, deleted: true);
        final inputs = await source.load(days7);
        final monday = dayOf(inputs, d(9, 28));
        expect(monday.mealEntries, 3);
        expect(monday.mealsWithKcal, 2);
        expect(monday.knownKcal, 1200);
        final thursday = dayOf(inputs, d(10, 1));
        expect(thursday.mealEntries, 2);
        expect(thursday.mealsWithKcal, 2, reason: 'a deliberate 0 is known');
        expect(thursday.knownKcal, 300);
        final friday = dayOf(inputs, d(10, 2));
        expect(friday.mealEntries, 0);
        expect(friday.mealsWithKcal, 0);
        expect(friday.knownKcal, 0);
      },
    );

    test(
      'rows of days before the window and after today are not loaded',
      () async {
        await db.steps(d(9, 19), 111);
        await db.steps(d(10, 4), 222);
        final inputs = await source.load(days7);
        expect(inputs.days.where((day) => day.stepsRecorded != null), isEmpty);
      },
    );
  });

  group('goals, habits and the day status (reference database scenario)', () {
    /// Synthetic scenario for 2026-09-20 .. 2026-10-03, computed by hand.
    ///
    /// Default goals: water 2500 ml, steps 10000, weight entry, focus 25 min
    /// (1500 s), task completion; habits count as goals. H1 started
    /// 2026-09-01, H2 started 2026-09-30, H3 started 2026-09-29. The tasks
    /// module was off on 2026-10-02 (and on again on 10-03): on that day the
    /// task goal and all habits do not apply.
    Future<({String h1, String h2, String h3})> build() async {
      // previous period 09-20 .. 09-26
      await db.weight(d(9, 21), 72400);
      await db.task(completedOn: d(9, 23));
      await db.task(completedOn: d(9, 23));
      await db.task(completedOn: d(9, 23));
      await db.task(completedOn: d(9, 23));
      await db.focus(seconds: 3000, completedOn: d(9, 24));
      await db.meal(d(9, 24), kcal: 400);
      await db.meal(d(9, 24), kcal: 600);
      await db.steps(d(9, 26), 5000);
      // current period 09-27 .. 10-03
      await db.steps(d(9, 27), 8000);
      await db.weight(
        d(9, 27),
        71900,
        occurredAt: DateTime.utc(2026, 9, 27, 6),
      );
      await db.weight(
        d(9, 27),
        71800,
        occurredAt: DateTime.utc(2026, 9, 27, 18),
      );
      await db.steps(d(9, 28), 0);
      await db.water(d(9, 28), 250);
      await db.water(d(9, 28), 500);
      await db.focus(seconds: 1500, completedOn: d(9, 28));
      await db.task(completedOn: d(9, 28));
      await db.task(completedOn: d(9, 28));
      await db.meal(d(9, 28), kcal: 500);
      await db.meal(d(9, 28), kcal: 700);
      await db.meal(d(9, 28));
      await db.water(d(9, 29), 1000);
      await db.water(d(9, 29), 500);
      await db.water(d(9, 29), 500);
      await db.workout(d(9, 29), 45);
      await db.steps(d(9, 30), 12000);
      await db.weight(d(9, 30), 71600);
      await db.water(d(9, 30), 500, deleted: true);
      await db.focus(seconds: 1800, completedOn: d(9, 30));
      await db.task(completedOn: d(9, 30));
      await db.water(d(10, 1), 1000);
      await db.water(d(10, 1), 500);
      await db.workout(d(10, 1), 30);
      await db.workout(d(10, 1), 60);
      await db.focus(
        seconds: 900,
        completedOn: d(10, 1),
        startedAt: DateTime.utc(2026, 9, 30, 21, 50),
      );
      await db.meal(d(10, 1), kcal: 0);
      await db.meal(d(10, 1), kcal: 300);
      await db.steps(d(10, 1), 99999, deleted: true);
      await db.task(completedOn: d(10, 1), deleted: true);
      await db.steps(d(10, 2), 6000);
      await db.focus(seconds: 600, completedOn: d(10, 2));
      await db.weight(d(10, 2), 99900, deleted: true);
      await db.task(); // reopened / open
      await db.steps(d(10, 3), 10000);
      await db.water(d(10, 3), 1500);
      await db.water(d(10, 3), 1000);
      await db.weight(d(10, 3), 71500);
      await db.focus(seconds: 1500, completedOn: d(10, 3));
      await db.focus(seconds: 999, completedOn: d(10, 3), deleted: true);
      await db.task(completedOn: d(10, 3));
      await db.task(completedOn: d(10, 3));
      await db.task(completedOn: d(10, 3));
      // habits and checks
      final h1 = await db.habit(d(9, 1));
      final h2 = await db.habit(d(9, 30));
      final h3 = await db.habit(d(9, 29));
      for (final date in [
        d(9, 21),
        d(9, 22),
        d(9, 28),
        d(9, 30),
        d(10, 1),
        d(10, 2), // the tasks module is off: not applicable, not counted
        d(10, 3),
      ]) {
        await db.habitCheck(h1, date);
      }
      await db.habitCheck(h2, d(9, 30));
      await db.habitCheck(h2, d(10, 3));
      await db.habitCheck(h3, d(9, 29));
      await db.habitCheck(h3, d(9, 30));
      // the tasks module is off on 10-02 and on again on 10-03
      await db.moduleStatus(
        ModuleId.tasks,
        d(10, 2),
        false,
        effectiveAt: DateTime.utc(2026, 10, 2, 9),
      );
      await db.moduleStatus(
        ModuleId.tasks,
        d(10, 3),
        true,
        effectiveAt: DateTime.utc(2026, 10, 3, 6),
      );
      return (h1: h1, h2: h2, h3: h3);
    }

    /// The expected per-day inputs. [h3Live]: the third habit exists (it is
    /// soft-deleted otherwise and must not count at all).
    List<AnalysisDay> expected({required bool h3Live}) => [
      AnalysisDay(
        date: d(9, 20),
        applicableGoals: 6,
        fulfilledGoals: 0,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 21),
        weightGrams: 72400,
        applicableGoals: 6,
        fulfilledGoals: 2,
        applicableHabits: 1,
        fulfilledHabits: 1,
      ),
      AnalysisDay(
        date: d(9, 22),
        applicableGoals: 6,
        fulfilledGoals: 1,
        applicableHabits: 1,
        fulfilledHabits: 1,
      ),
      AnalysisDay(
        date: d(9, 23),
        tasksCompleted: 4,
        applicableGoals: 6,
        fulfilledGoals: 1,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 24),
        focusCompletedSeconds: 3000,
        focusCompletedSessions: 1,
        mealEntries: 2,
        mealsWithKcal: 2,
        knownKcal: 1000,
        applicableGoals: 6,
        fulfilledGoals: 1,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 25),
        applicableGoals: 6,
        fulfilledGoals: 0,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 26),
        stepsRecorded: 5000,
        applicableGoals: 6,
        fulfilledGoals: 0,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 27),
        stepsRecorded: 8000,
        weightGrams: 71800,
        applicableGoals: 6,
        fulfilledGoals: 1,
        applicableHabits: 1,
        fulfilledHabits: 0,
      ),
      AnalysisDay(
        date: d(9, 28),
        stepsRecorded: 0,
        waterMl: 750,
        waterEntries: 2,
        focusCompletedSeconds: 1500,
        focusCompletedSessions: 1,
        tasksCompleted: 2,
        mealEntries: 3,
        mealsWithKcal: 2,
        knownKcal: 1200,
        applicableGoals: 6,
        fulfilledGoals: 3,
        applicableHabits: 1,
        fulfilledHabits: 1,
      ),
      AnalysisDay(
        date: d(9, 29),
        waterMl: 2000,
        waterEntries: 3,
        workoutEntries: 1,
        workoutMinutes: 45,
        applicableGoals: h3Live ? 7 : 6,
        fulfilledGoals: h3Live ? 1 : 0,
        applicableHabits: h3Live ? 2 : 1,
        fulfilledHabits: h3Live ? 1 : 0,
      ),
      AnalysisDay(
        date: d(9, 30),
        stepsRecorded: 12000,
        weightGrams: 71600,
        focusCompletedSeconds: 1800,
        focusCompletedSessions: 1,
        tasksCompleted: 1,
        applicableGoals: h3Live ? 8 : 7,
        fulfilledGoals: h3Live ? 7 : 6,
        applicableHabits: h3Live ? 3 : 2,
        fulfilledHabits: h3Live ? 3 : 2,
      ),
      AnalysisDay(
        date: d(10, 1),
        waterMl: 1500,
        waterEntries: 2,
        workoutEntries: 2,
        workoutMinutes: 90,
        focusCompletedSeconds: 900,
        focusCompletedSessions: 1,
        mealEntries: 2,
        mealsWithKcal: 2,
        knownKcal: 300,
        applicableGoals: h3Live ? 8 : 7,
        fulfilledGoals: 1,
        applicableHabits: h3Live ? 3 : 2,
        fulfilledHabits: 1,
      ),
      AnalysisDay(
        date: d(10, 2),
        stepsRecorded: 6000,
        focusCompletedSeconds: 600,
        focusCompletedSessions: 1,
        applicableGoals: 4,
        fulfilledGoals: 0,
      ),
      AnalysisDay(
        date: d(10, 3),
        stepsRecorded: 10000,
        waterMl: 2500,
        waterEntries: 2,
        weightGrams: 71500,
        focusCompletedSeconds: 1500,
        focusCompletedSessions: 1,
        tasksCompleted: 3,
        applicableGoals: h3Live ? 8 : 7,
        fulfilledGoals: 7,
        applicableHabits: h3Live ? 3 : 2,
        fulfilledHabits: 2,
      ),
    ];

    void expectDays(AnalysisInputs inputs, List<AnalysisDay> expectedDays) {
      expect(inputs.days, hasLength(expectedDays.length));
      for (var i = 0; i < expectedDays.length; i++) {
        expect(
          inputs.days[i],
          expectedDays[i],
          reason: 'day ${expectedDays[i].date}',
        );
      }
    }

    test('every fact table and the day status are read correctly', () async {
      final habits = await build();
      await db.setHabitDeleted(habits.h3, deleted: true);
      final inputs = await source.load(days7);
      expectDays(inputs, expected(h3Live: false));
    });

    test('the loaded numbers give the reference aggregates', () async {
      final habits = await build();
      await db.setHabitDeleted(habits.h3, deleted: true);
      final report = (await source.load(days7)).toReport();
      final current = report.current;
      expect(current.steps.recordedDays, 5);
      expect(current.steps.totalSteps, 36000);
      expect(current.water.recordedDays, 4);
      expect(current.water.totalMl, 6750);
      expect(current.water.average, 1687.5);
      expect(current.weight.measuredDays, 3);
      expect(current.weight.changeGrams, -300);
      expect(current.workouts.entries, 3);
      expect(current.workouts.minutes, 135);
      expect(current.focus.completedSessions, 5);
      expect(current.focus.completedSeconds, 6300);
      expect(current.tasks.completed, 6);
      expect(current.meals.meals, 5);
      expect(current.meals.mealsWithKcal, 4);
      expect(current.meals.kcalTotal, 1500);
      expect(current.habits.applicableHabitDays, 9);
      expect(current.habits.fulfilledHabitDays, 6);
      expect(current.goals.daysWithGoals, 7);
      expect(current.goals.completeDays, 1, reason: 'only 10-03');
      expect(current.goals.activeDays, 5);
      final previous = report.previous;
      expect(previous.steps.totalSteps, 5000);
      expect(previous.weight.measuredDays, 1);
      expect(previous.tasks.completed, 4);
      expect(previous.focus.completedSeconds, 3000);
      expect(previous.habits.applicableHabitDays, 7);
      expect(previous.habits.fulfilledHabitDays, 2);
      expect(previous.goals.daysWithGoals, 7);
      expect(previous.goals.completeDays, 0);
      expect(previous.goals.activeDays, 4);
      expect(previous.meals.kcalTotal, 1000);
    });

    test(
      'a habit started inside the period and the tasks module off for a day',
      () async {
        final habits = await build();
        await db.setHabitDeleted(habits.h3, deleted: true);
        final inputs = await source.load(days7);
        expect(
          inputs.days.map((day) => day.applicableHabits).skip(7).toList(),
          [1, 1, 1, 2, 2, 0, 2],
          reason:
              'H1 all days, H2 from 09-30, none while the tasks module is off',
        );
        expect(
          inputs.days.map((day) => day.fulfilledHabits).skip(7).toList(),
          [0, 1, 0, 2, 1, 0, 2],
          reason: 'the check of 10-02 does not count: not applicable that day',
        );
      },
    );

    test('deleting a habit removes it from habit-days and complete days; undo brings it back', () async {
      final habits = await build();
      final live = await source.load(days7);
      expectDays(live, expected(h3Live: true));
      final liveStats = live.toReport().current;
      expect(liveStats.habits.applicableHabitDays, 13);
      expect(liveStats.habits.fulfilledHabitDays, 8);
      expect(liveStats.goals.completeDays, 0, reason: 'H3 is open on 10-03');
      expect(liveStats.goals.activeDays, 6);

      await db.setHabitDeleted(habits.h3, deleted: true);
      final deleted = await source.load(days7);
      expectDays(deleted, expected(h3Live: false));
      final deletedStats = deleted.toReport().current;
      expect(deletedStats.habits.applicableHabitDays, 9);
      expect(deletedStats.habits.fulfilledHabitDays, 6);
      expect(
        deletedStats.goals.completeDays,
        1,
        reason: 'the deleted habit no longer spoils 10-03',
      );
      expect(
        deletedStats.goals.activeDays,
        5,
        reason: '09-29 loses its only check',
      );

      await db.setHabitDeleted(habits.h3, deleted: false);
      final restored = await source.load(days7);
      expectDays(restored, expected(h3Live: true));
      expect(restored, live, reason: 'undo restores the exact inputs');
    });
  });

  group('habit snapshots created after the habit was deleted', () {
    test(
      'a habit that is deleted before any snapshot exists never appears',
      () async {
        final habit = await db.habit(d(9, 29));
        await db.habitCheck(habit, d(9, 29));
        await db.setHabitDeleted(habit, deleted: true);
        final inputs = await source.load(days7);
        for (final day in inputs.days) {
          expect(day.applicableHabits, 0, reason: '${day.date}');
          expect(day.applicableGoals, 5);
        }
      },
    );
  });

  group('habit start and archive dates', () {
    test('a habit archived inside the period applies until the day before', () async {
      // archived on 09-30: archiving takes effect tomorrow, archivedFrom 10-01
      final habit = await db.habit(d(9, 1), archivedFrom: d(10, 1));
      await db.habitCheck(habit, d(9, 28));
      await db.habitCheck(habit, d(9, 30));
      final inputs = await source.load(days7);
      expect(inputs.days.skip(7).map((day) => day.applicableHabits).toList(), [
        1,
        1,
        1,
        1,
        0,
        0,
        0,
      ], reason: 'applicable on the archiving day, not from tomorrow on');
      expect(inputs.days.skip(7).map((day) => day.fulfilledHabits).toList(), [
        0,
        1,
        0,
        1,
        0,
        0,
        0,
      ]);
      expect(inputs.days.take(7).map((day) => day.applicableHabits).toList(), [
        1,
        1,
        1,
        1,
        1,
        1,
        1,
      ], reason: 'the whole previous period');
      final current = inputs.toReport().current.habits;
      expect(current.applicableHabitDays, 4);
      expect(current.fulfilledHabitDays, 2);
      expect(current.ratioPercent, 50);
    });

    test(
      'a habit started inside the period applies from its start day',
      () async {
        final habit = await db.habit(d(9, 30));
        await db.habitCheck(habit, d(10, 2));
        final inputs = await source.load(days7);
        expect(
          inputs.days.skip(7).map((day) => day.applicableHabits).toList(),
          [0, 0, 0, 1, 1, 1, 1],
        );
        expect(inputs.days.skip(7).map((day) => day.fulfilledHabits).toList(), [
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
        final report = inputs.toReport();
        expect(report.previous.habits.hasData, isFalse);
        expect(report.current.habits.applicableHabitDays, 4);
      },
    );
  });

  group('tasks module off for some days', () {
    test(
      'habits and the task goal do not apply while the module is off',
      () async {
        final habit = await db.habit(d(9, 1));
        await db.moduleStatus(
          ModuleId.tasks,
          d(9, 29),
          false,
          effectiveAt: DateTime.utc(2026, 9, 29, 9),
        );
        await db.moduleStatus(
          ModuleId.tasks,
          d(10, 1),
          true,
          effectiveAt: DateTime.utc(2026, 10, 1, 9),
        );
        await db.habitCheck(habit, d(9, 29));
        await db.habitCheck(habit, d(9, 30));
        await db.habitCheck(habit, d(10, 1));
        final inputs = await source.load(days7);
        // off on 09-29 and 09-30, on again from 10-01
        expect(
          inputs.days.skip(7).map((day) => day.applicableHabits).toList(),
          [1, 1, 0, 0, 1, 1, 1],
        );
        expect(
          inputs.days.skip(7).map((day) => day.applicableGoals).toList(),
          [6, 6, 4, 4, 6, 6, 6],
          reason:
              'five daily goals + the habit, minus the task goal and the '
              'habit while the module is off',
        );
        expect(inputs.days.skip(7).map((day) => day.fulfilledHabits).toList(), [
          0,
          0,
          0,
          0,
          1,
          0,
          0,
        ], reason: 'checks on days the habit did not apply are not counted');
      },
    );
  });

  group('is there any applicable goal ever', () {
    test('with the seeded goals: yes', () async {
      expect((await source.load(days7)).hasApplicableGoalEver, isTrue);
    });

    test('all modules off from the start: no goal ever applied', () async {
      await harness.dispose();
      await startHarness(enabledModules: const {});
      await db.habit(d(9, 1));
      final inputs = await source.load(days7);
      expect(inputs.hasApplicableGoalEver, isFalse);
      expect(inputs.activeModules, isEmpty);
      for (final day in inputs.days) {
        expect(day.applicableGoals, 0);
        expect(day.hasApplicableGoals, isFalse);
      }
      expect(inputs.toReport().noModuleActive, isTrue);
    });

    test(
      'only a habit applies: it counts while live, not while deleted',
      () async {
        await harness.dispose();
        await startHarness(enabledModules: {ModuleId.tasks.key});
        // switch the task goal off: only habits remain as goals
        await (db.db.update(db.db.goalVersions)
              ..where((v) => v.goalType.equals(GoalType.taskCompletion.key)))
            .write(const GoalVersionsCompanion(enabled: Value(false)));
        final habit = await db.habit(d(9, 1));
        final live = await source.load(days7);
        expect(live.hasApplicableGoalEver, isTrue);
        expect(live.days.last.applicableGoals, 1);

        await db.setHabitDeleted(habit, deleted: true);
        final deleted = await source.load(days7);
        expect(
          deleted.hasApplicableGoalEver,
          isFalse,
          reason: 'the stored habit items of a deleted habit do not count',
        );
        expect(deleted.days.last.applicableGoals, 0);

        await db.setHabitDeleted(habit, deleted: false);
        expect((await source.load(days7)).hasApplicableGoalEver, isTrue);
      },
    );
  });

  group('profile, modules and the weekly workout target', () {
    test('usage start and active modules', () async {
      final inputs = await source.load(days7);
      expect(inputs.usageStart, d(9, 1));
      expect(inputs.activeModules, ModuleId.values.toSet());
    });

    test('a module switched off disappears from the active set', () async {
      await db.moduleStatus(
        ModuleId.body,
        today,
        false,
        effectiveAt: DateTime.utc(2026, 10, 3, 7),
      );
      final inputs = await source.load(days7);
      expect(inputs.activeModules, isNot(contains(ModuleId.body)));
      expect(inputs.activeModules, hasLength(4));
      // the data of the module is still loaded and counted, only the cards
      // are hidden by the report
      await db.steps(d(10, 1), 5000);
      final again = await source.load(days7);
      expect(dayOf(again, d(10, 1)).stepsRecorded, 5000);
      expect(again.toReport().cardFor(AnalysisMetric.steps), isNull);
      expect(again.toReport().current.steps.totalSteps, 5000);
    });

    test('the weekly target is the version in effect today', () async {
      expect((await source.load(days7)).workoutWeeklyTarget, 3);
      await db.goalVersion(GoalType.workoutWeekly, d(9, 20), target: 5);
      expect((await source.load(days7)).workoutWeeklyTarget, 5);
      await db.goalVersion(GoalType.workoutWeekly, d(10, 4), target: 7);
      expect(
        (await source.load(days7)).workoutWeeklyTarget,
        5,
        reason: 'a version that starts tomorrow is not in effect yet',
      );
      await db.goalVersion(GoalType.workoutWeekly, today, target: 4);
      expect((await source.load(days7)).workoutWeeklyTarget, 4);
    });

    test(
      'a switched-off weekly goal has no target, a missing one defaults to 3',
      () async {
        await db.goalVersion(
          GoalType.workoutWeekly,
          d(10, 1),
          target: 6,
          enabled: false,
        );
        expect((await source.load(days7)).workoutWeeklyTarget, isNull);
        await db.db.delete(db.db.goalVersions).go();
        expect((await source.load(days7)).workoutWeeklyTarget, 3);
      },
    );
  });

  group('the workout week inputs', () {
    test('fourteen days of workouts, the target and the usage start', () async {
      await db.workout(d(9, 21), 40);
      await db.workout(d(9, 29), 45);
      await db.workout(d(10, 1), 30);
      await db.workout(d(10, 1), 60);
      await db.workout(d(9, 20), 99); // before the 14 days
      final week = await source.loadWorkoutWeek(today);
      expect(week.today, today);
      expect(week.usageStart, d(9, 1));
      expect(week.weeklyTarget, 3);
      expect(week.days, hasLength(14));
      expect(week.days.first.date, d(9, 20), reason: 'today - 13');
      expect(week.days.first.workoutEntries, 1);
      expect(week.days.last.date, today);
      expect(week.days.fold<int>(0, (sum, day) => sum + day.workoutEntries), 5);
      expect(
        week.days.singleWhere((day) => day.date == d(10, 1)).workoutMinutes,
        90,
      );
    });
  });

  group('frozen local dates decide the day (never the UTC date)', () {
    test('spring clock change 2026-03-29: a 23 hour day with instants of both offsets', () async {
      await harness.dispose();
      await startHarness(
        seededAt: '2026-03-01T06:00:00Z',
        nowIso: '2026-03-31T10:00:00Z',
        startedOn: LocalDate(2026, 3, 1),
      );
      final spring = period(AnalysisPeriodLength.days7, LocalDate(2026, 3, 31));
      // A: Saturday 21:00 CET, B: 00:30 CET on the Sunday of the change,
      // C: 23:30 CEST that Sunday (22 hours later), D: 00:30 CEST on Monday.
      await db.water(
        LocalDate(2026, 3, 28),
        250,
        occurredAt: DateTime.utc(2026, 3, 28, 20),
      );
      await db.water(
        LocalDate(2026, 3, 29),
        250,
        occurredAt: DateTime.utc(2026, 3, 28, 23, 30),
      );
      await db.water(
        LocalDate(2026, 3, 29),
        250,
        occurredAt: DateTime.utc(2026, 3, 29, 21, 30),
      );
      await db.water(
        LocalDate(2026, 3, 30),
        250,
        occurredAt: DateTime.utc(2026, 3, 29, 22, 30),
      );
      final inputs = await source.load(spring);
      expect(inputs.days, hasLength(14));
      expect(inputs.days.first.date, LocalDate(2026, 3, 18));
      expect(inputs.days.last.date, LocalDate(2026, 3, 31));
      int entries(LocalDate date) => dayOf(inputs, date).waterEntries;
      expect(entries(LocalDate(2026, 3, 27)), 0);
      expect(entries(LocalDate(2026, 3, 28)), 1);
      expect(entries(LocalDate(2026, 3, 29)), 2);
      expect(entries(LocalDate(2026, 3, 30)), 1);
      expect(entries(LocalDate(2026, 3, 31)), 0);
      final report = inputs.toReport();
      expect(report.current.water.recordedDays, 3);
      expect(report.current.water.totalMl, 1000);
      expect(report.previous.water.recordedDays, 0);
    });

    test('autumn clock change 2026-10-25: a 25 hour day', () async {
      await harness.dispose();
      await startHarness(
        seededAt: '2026-10-01T06:00:00Z',
        nowIso: '2026-10-27T10:00:00Z',
        startedOn: LocalDate(2026, 10, 1),
      );
      final autumn = period(
        AnalysisPeriodLength.days7,
        LocalDate(2026, 10, 27),
      );
      // A: Saturday 22:00 CEST, B: 00:30 CEST Sunday, C: 23:30 CET Sunday,
      // D: 00:30 CET Monday.
      await db.water(
        LocalDate(2026, 10, 24),
        500,
        occurredAt: DateTime.utc(2026, 10, 24, 20),
      );
      await db.water(
        LocalDate(2026, 10, 25),
        500,
        occurredAt: DateTime.utc(2026, 10, 24, 22, 30),
      );
      await db.water(
        LocalDate(2026, 10, 25),
        500,
        occurredAt: DateTime.utc(2026, 10, 25, 22, 30),
      );
      await db.water(
        LocalDate(2026, 10, 26),
        500,
        occurredAt: DateTime.utc(2026, 10, 25, 23, 30),
      );
      final inputs = await source.load(autumn);
      int entries(LocalDate date) => dayOf(inputs, date).waterEntries;
      expect(entries(LocalDate(2026, 10, 24)), 1);
      expect(entries(LocalDate(2026, 10, 25)), 2);
      expect(entries(LocalDate(2026, 10, 26)), 1);
      expect(inputs.days.first.date, LocalDate(2026, 10, 14));
      expect(inputs.toReport().current.water.totalMl, 2000);
    });

    test('year boundary: the period reaches back into the old year', () async {
      await harness.dispose();
      await startHarness(
        seededAt: '2025-06-01T06:00:00Z',
        nowIso: '2026-01-03T10:00:00Z',
        startedOn: LocalDate(2025, 6, 1),
      );
      final spec = period(AnalysisPeriodLength.days7, LocalDate(2026, 1, 3));
      await db.steps(LocalDate(2025, 12, 21), 1000); // first previous day
      await db.steps(LocalDate(2025, 12, 27), 2000); // last previous day
      await db.steps(LocalDate(2025, 12, 28), 3000); // first current day
      await db.steps(LocalDate(2025, 12, 31), 4000);
      await db.steps(LocalDate(2026, 1, 1), 5000);
      await db.steps(LocalDate(2025, 12, 20), 9999); // outside
      final inputs = await source.load(spec);
      expect(inputs.days.first.date, LocalDate(2025, 12, 21));
      expect(inputs.days.last.date, LocalDate(2026, 1, 3));
      final report = inputs.toReport();
      expect(report.current.steps.totalSteps, 3000 + 4000 + 5000);
      expect(report.current.steps.recordedDays, 3);
      expect(report.previous.steps.totalSteps, 1000 + 2000);
      expect(report.periodText, '28.12.2025 bis 03.01.2026, inklusive heute');
    });

    test('leap year: 2028-02-29 is a day of the window', () async {
      await harness.dispose();
      await startHarness(
        seededAt: '2028-01-10T06:00:00Z',
        nowIso: '2028-03-02T10:00:00Z',
        startedOn: LocalDate(2028, 1, 10),
      );
      final spec = period(AnalysisPeriodLength.days7, LocalDate(2028, 3, 2));
      await db.steps(LocalDate(2028, 2, 29), 777);
      final inputs = await source.load(spec);
      expect(inputs.days, hasLength(14));
      expect(inputs.days.first.date, LocalDate(2028, 2, 18));
      expect(dayOf(inputs, LocalDate(2028, 2, 29)).stepsRecorded, 777);
      expect(
        inputs.days.map((day) => day.date),
        contains(LocalDate(2028, 2, 29)),
      );
    });
  });

  group('input values', () {
    test('equal inputs compare equal, a change makes them differ', () async {
      final a = await source.load(days7);
      final b = await source.load(days7);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      await db.steps(d(10, 1), 5000);
      final c = await source.load(days7);
      expect(c, isNot(a));
      expect(await source.load(period(AnalysisPeriodLength.days30)), isNot(a));
    });
  });
}
