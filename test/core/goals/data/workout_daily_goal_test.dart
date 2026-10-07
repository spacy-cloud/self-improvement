import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The optional daily goal "Workout heute" with the real database, the real
/// projection and the fake clock (BS-99): one workout, a rest day or a skipped
/// day fulfils it; the weekly goal stays separate; off by default; changes
/// apply from tomorrow.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late WorkoutRepository workouts;
  late WorkoutDayMarkRepository marks;
  late DayStatusRepository statusRepository;
  late AppDatabase db;

  // 2026-10-03 is a Saturday: its week runs from 2026-09-28 to 2026-10-04.
  final today = LocalDate(2026, 10, 3);
  final profileStart = LocalDate(2026, 9, 1);

  Future<void> start({
    bool dailyGoal = true,
    int? weeklyTarget,
    Set<String>? enabledModules,
  }) async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(
      startedOn: profileStart,
      workoutDailyGoal: dailyGoal,
      enabledModules: enabledModules,
    );
    db = harness.database;
    workouts = WorkoutRepository(database: db, runner: harness.runner);
    marks = WorkoutDayMarkRepository(database: db, runner: harness.runner);
    statusRepository = harness.dayStatusRepository();
    if (weeklyTarget != null) {
      await GoalVersionRepository(db).upsert(
        GoalVersion(
          type: GoalType.workoutWeekly,
          target: weeklyTarget,
          effectiveFrom: profileStart,
        ),
        newId: 'weekly-$weeklyTarget',
        nowUtc: harness.clock.nowUtc(),
      );
    }
  }

  tearDown(() => harness.dispose());

  Future<String> logWorkout({DateTime? at, int minutes = 45}) async {
    final outcome = await workouts.create(
      commandId: harness.ids.newId(),
      draft: WorkoutDraft(
        category: TrainingCategory.strength,
        durationMinutes: minutes,
        occurredAtUtc: at ?? harness.clock.nowUtc(),
      ),
    );
    return outcome.entityId!;
  }

  Future<String> markDay(WorkoutDayMarkKind kind, {LocalDate? date}) async {
    final outcome = await marks.mark(
      commandId: harness.ids.newId(),
      kind: kind,
      date: date,
    );
    return outcome.entityId!;
  }

  Future<DayStatus> statusOf(LocalDate day) async =>
      (await statusRepository.statusFor(day))!;

  Future<GoalProgress> dailyOf(LocalDate day) async =>
      (await statusOf(day)).progressOf(GoalType.workoutDaily)!;

  /// The week of [day] as the Workout card and the overview count it.
  Future<WorkoutWeekSummary> weekOf(LocalDate day) async {
    final entries = await workouts.fetchPage(limit: 100);
    final versions = await GoalVersionRepository(db).all();
    return buildWorkoutWeekSummary(
      entries: entries,
      today: day,
      weeklyTarget: workoutWeeklyTargetOn(versions, day),
    );
  }

  Future<int> awardCount() async => (await db.select(db.xpAwards).get()).length;

  group('one workout fulfils the daily goal, whatever the weekly goal says', () {
    for (final weeklyTarget in [3, 5]) {
      test(
        '(BS-99, AT20) weekly goal $weeklyTarget: one finished workout today reaches "Workout heute"',
        () async {
          await start(weeklyTarget: weeklyTarget);

          final open = await dailyOf(today);
          expect(open.applicable, isTrue);
          expect(open.fulfilled, isFalse);
          expect(open.current, 0);
          expect(open.target, 1);

          await logWorkout();

          final reached = await dailyOf(today);
          expect(reached.fulfilled, isTrue);
          expect(reached.current, 1);
          final status = await statusOf(today);
          expect(status.applicableCount, 6, reason: 'five goals and this one');
          expect(status.fulfilledCount, 1);
          expect(status.isActive, isTrue);

          // The week is a different question: it still wants the rest.
          final week = await weekOf(today);
          expect(week.weeklyTarget, weeklyTarget);
          expect(week.entryCount, 1);
          expect(week.targetReached, isFalse);
          expect(week.remainingToTarget, weeklyTarget - 1);
        },
      );
    }

    test('(BS-99, AT20) a second workout the same day changes nothing about the goal', () async {
      await start();
      await logWorkout();
      await logWorkout(at: DateTime.utc(2026, 10, 3, 6), minutes: 20);
      final reached = await dailyOf(today);
      expect(reached.fulfilled, isTrue);
      expect(reached.current, 2, reason: 'the count shows, the goal is one');
      expect((await statusOf(today)).fulfilledCount, 1);
    });

    test('(BS-99) deleting the only workout opens the day again; the undo reaches it again (AT23)', () async {
      await start();
      final id = await logWorkout();
      expect((await dailyOf(today)).fulfilled, isTrue);

      final deleted = await workouts.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect((await dailyOf(today)).fulfilled, isFalse);
      expect((await statusOf(today)).isActive, isFalse);

      await deleted.undo!.run(harness.ids.newId());
      expect((await dailyOf(today)).fulfilled, isTrue);
    });

    test('(BS-99, AT23) a workout logged for yesterday reaches yesterday, not today', () async {
      await start();
      await logWorkout(at: DateTime.utc(2026, 10, 2, 8));
      expect((await dailyOf(today.addDays(-1))).fulfilled, isTrue);
      expect((await dailyOf(today)).fulfilled, isFalse);
    });
  });

  group('rest day and skipped day are valid day states', () {
    for (final kind in WorkoutDayMarkKind.values) {
      test(
        '(BS-99) ${kind.key}: reaches the goal without a workout, the day is active',
        () async {
          await start();
          await markDay(kind);

          final reached = await dailyOf(today);
          expect(reached.fulfilled, isTrue);
          expect(reached.current, 1);
          final status = await statusOf(today);
          expect(status.fulfilledCount, 1);
          expect(status.applicableCount, 6);
          expect(status.isActive, isTrue);

          // A workout is not what the week counts.
          final week = await weekOf(today);
          expect(week.entryCount, 0);
          expect(week.latest, isNull);
          expect(week.targetReached, isFalse);
        },
      );
    }

    test(
      '(BS-99) earns no XP, a workout on another day still earns its 15',
      () async {
        await start();
        await markDay(WorkoutDayMarkKind.rest);
        await markDay(WorkoutDayMarkKind.skipped, date: today.addDays(-1));
        expect(await harness.totalXp(), 0);
        expect(await awardCount(), 0);

        await logWorkout(at: DateTime.utc(2026, 10, 1, 8));
        expect(await harness.totalXp(), 15);
        expect(await awardCount(), 1);
      },
    );

    test(
      '(BS-99) a mark and a workout on the same day earn only the workout XP',
      () async {
        await start();
        await markDay(WorkoutDayMarkKind.rest);
        await logWorkout();
        expect(await harness.totalXp(), 15);

        final workoutId = (await workouts.fetchPage(limit: 5)).single.id;
        await workouts.delete(commandId: harness.ids.newId(), id: workoutId);
        expect(await harness.totalXp(), 0, reason: 'the mark never earned XP');
        expect(
          (await dailyOf(today)).fulfilled,
          isTrue,
          reason: 'the rest day applies again without the workout',
        );
      },
    );

    test('(BS-99) taking the mark back opens the day; its undo marks it again (AT23)', () async {
      await start();
      final outcome = await marks.mark(
        commandId: harness.ids.newId(),
        kind: WorkoutDayMarkKind.rest,
      );
      expect((await dailyOf(today)).fulfilled, isTrue);

      final taken = await marks.unmark(
        commandId: harness.ids.newId(),
        id: outcome.entityId!,
      );
      expect((await dailyOf(today)).fulfilled, isFalse);
      expect((await statusOf(today)).isActive, isFalse);

      await taken.undo!.run(harness.ids.newId());
      expect((await dailyOf(today)).fulfilled, isTrue);

      // The undo of the original mark is stale now: the mark changed since.
      await expectLater(
        outcome.undo!.run(harness.ids.newId()),
        throwsA(isA<ConflictFailure>()),
      );
      expect((await dailyOf(today)).fulfilled, isTrue);
    });

    test(
      '(BS-99) a second entry for the day is a conflict and changes nothing',
      () async {
        await start();
        await markDay(WorkoutDayMarkKind.rest);
        await expectLater(
          marks.mark(
            commandId: harness.ids.newId(),
            kind: WorkoutDayMarkKind.skipped,
          ),
          throwsA(isA<ConflictFailure>()),
        );
        final facts = await DayFactsSource(db).factsFor(today);
        expect(facts.workoutDayMark, WorkoutDayMarkKind.rest);
        expect((await dailyOf(today)).fulfilled, isTrue);
      },
    );
  });

  group('streak', () {
    test(
      '(BS-99, G02) rest days and skipped days hold the streak, like workouts',
      () async {
        await start();
        await markDay(WorkoutDayMarkKind.rest, date: LocalDate(2026, 10, 1));
        await markDay(WorkoutDayMarkKind.skipped, date: LocalDate(2026, 10, 2));
        await logWorkout();

        final streak = (await statusRepository.computeStreakSummary())!;
        expect(streak.current, 3);
        expect(streak.longest, 3);
        expect(streak.activeDays, 3);
        expect(streak.todayActive, isTrue);
      },
    );

    test('(BS-99, G02) without the mark of the middle day the streak is broken (the mark is what holds it)', () async {
      await start();
      await markDay(WorkoutDayMarkKind.rest, date: LocalDate(2026, 10, 1));
      final middle = await markDay(
        WorkoutDayMarkKind.skipped,
        date: LocalDate(2026, 10, 2),
      );
      await logWorkout();
      expect((await statusRepository.computeStreakSummary())!.current, 3);

      await marks.unmark(commandId: harness.ids.newId(), id: middle);
      final broken = (await statusRepository.computeStreakSummary())!;
      expect(broken.current, 1, reason: 'only today is active');
      expect(broken.longest, 1);
      expect(broken.activeDays, 2);
    });

    test('(BS-99, AT22) today still open: the streak of the marked days before survives', () async {
      await start();
      await markDay(WorkoutDayMarkKind.rest, date: LocalDate(2026, 10, 1));
      await markDay(WorkoutDayMarkKind.skipped, date: LocalDate(2026, 10, 2));
      final streak = (await statusRepository.computeStreakSummary())!;
      expect(streak.todayActive, isFalse);
      expect(streak.current, 2);
    });

    test(
      '(BS-99, G02) with the goal off a mark does not hold anything',
      () async {
        await start(dailyGoal: false);
        await markDay(WorkoutDayMarkKind.rest, date: LocalDate(2026, 10, 2));
        await logWorkout();
        final streak = (await statusRepository.computeStreakSummary())!;
        expect(streak.current, 0);
        expect(streak.activeDays, 0);
      },
    );
  });

  group('the goal is off by default', () {
    test('(BS-99) it is in the snapshot but not applicable and not counted in "x von y"', () async {
      await start(dailyGoal: false);
      expect(
        await (db.select(
          db.goalVersions,
        )..where((v) => v.goalType.equals('workout_daily'))).get(),
        isEmpty,
        reason: 'no version means off',
      );

      await logWorkout();
      await markDay(WorkoutDayMarkKind.rest, date: today.addDays(-1));

      final status = await statusOf(today);
      expect(status.applicableCount, 5);
      expect(status.fulfilledCount, 0, reason: 'a workout is no daily goal');
      expect(status.ringFraction, 0.0);
      final item = status.progressOf(GoalType.workoutDaily)!;
      expect(item.applicable, isFalse);
      expect(item.fulfilled, isFalse);
      final yesterday = await statusOf(today.addDays(-1));
      expect(yesterday.applicableCount, 5);
      expect(yesterday.fulfilledCount, 0);
    });

    test('(BS-99) switched on it joins the ring: x von 6, with and without the day state', () async {
      await start();
      final open = await statusOf(today);
      expect(open.applicableCount, 6);
      expect(open.fulfilledCount, 0);
      await markDay(WorkoutDayMarkKind.rest);
      final reached = await statusOf(today);
      expect(reached.applicableCount, 6);
      expect(reached.fulfilledCount, 1);
    });

    test('(BS-99) with the focus module off it does not count even when switched on', () async {
      await start(
        enabledModules: {'body', 'nutrition', 'tasks', 'gamification'},
      );
      await markDay(WorkoutDayMarkKind.rest);
      final status = await statusOf(today);
      expect(status.progressOf(GoalType.workoutDaily)!.applicable, isFalse);
      expect(status.applicableCount, 4);
      expect(status.fulfilledCount, 0);
    });
  });

  group('a change applies from tomorrow (AT24)', () {
    test('(BS-99, AT24) switched on today: today stays without it, tomorrow has it', () async {
      await start(dailyGoal: false);
      final goals = GoalsCommands(
        runner: harness.runner,
        versions: GoalVersionRepository(db),
      );
      await goals.update(
        commandId: harness.ids.newId(),
        changes: {GoalType.workoutDaily: const GoalSetting()},
      );

      // A rest day today does not count: the goal starts tomorrow.
      await markDay(WorkoutDayMarkKind.rest);
      final todayStatus = await statusOf(today);
      expect(
        todayStatus.progressOf(GoalType.workoutDaily)!.applicable,
        isFalse,
      );
      expect(todayStatus.fulfilledCount, 0);

      harness.clock.advance(const Duration(days: 1));
      final tomorrow = harness.clock.today();
      expect(tomorrow, today.addDays(1));
      final tomorrowStatus = await statusOf(tomorrow);
      final goal = tomorrowStatus.progressOf(GoalType.workoutDaily)!;
      expect(goal.applicable, isTrue);
      expect(
        goal.fulfilled,
        isFalse,
        reason: 'the mark of today is not tomorrow\'s',
      );
      expect(tomorrowStatus.applicableCount, 6);

      await logWorkout();
      expect((await dailyOf(tomorrow)).fulfilled, isTrue);
      expect(
        (await statusOf(today)).progressOf(GoalType.workoutDaily)!.applicable,
        isFalse,
        reason: 'today keeps its frozen snapshot',
      );
    });

    test('(BS-99, AT24) switched off today: today still counts it, tomorrow does not', () async {
      await start();
      await markDay(WorkoutDayMarkKind.rest);
      expect((await dailyOf(today)).fulfilled, isTrue);

      final goals = GoalsCommands(
        runner: harness.runner,
        versions: GoalVersionRepository(db),
      );
      await goals.update(
        commandId: harness.ids.newId(),
        changes: {GoalType.workoutDaily: const GoalSetting(enabled: false)},
      );

      final stillToday = await dailyOf(today);
      expect(stillToday.applicable, isTrue);
      expect(stillToday.fulfilled, isTrue);

      harness.clock.advance(const Duration(days: 1));
      final tomorrow = harness.clock.today();
      await markDay(WorkoutDayMarkKind.skipped);
      final off = await dailyOf(tomorrow);
      expect(off.applicable, isFalse);
      expect(off.fulfilled, isFalse);
      expect(
        (await dailyOf(today)).fulfilled,
        isTrue,
        reason: 'yesterday keeps the rest day it counted',
      );
    });
  });

  group('the weekly goal stays separate', () {
    test('(BS-99) three days answered with a rest day, a skip and one workout: the week counts one', () async {
      await start(weeklyTarget: 3);
      await markDay(WorkoutDayMarkKind.rest, date: LocalDate(2026, 10, 1));
      await markDay(WorkoutDayMarkKind.skipped, date: LocalDate(2026, 10, 2));
      await logWorkout();

      for (final day in [
        LocalDate(2026, 10, 1),
        LocalDate(2026, 10, 2),
        today,
      ]) {
        expect((await dailyOf(day)).fulfilled, isTrue, reason: '$day');
      }
      final week = await weekOf(today);
      expect(week.entryCount, 1);
      expect(week.targetReached, isFalse, reason: 'one of three');
      expect(week.remainingToTarget, 2);
    });

    test('(BS-99) the weekly goal never enters the day snapshot', () async {
      await start(weeklyTarget: 5);
      await logWorkout();
      final status = await statusOf(today);
      expect(
        status.goals.map((g) => g.goalKey),
        isNot(contains('workout_weekly')),
      );
    });

    test('(BS-99) reaching the weekly goal does not change the daily goal of an open day', () async {
      await start(weeklyTarget: 3);
      for (final day in [
        LocalDate(2026, 9, 28),
        LocalDate(2026, 9, 29),
        LocalDate(2026, 9, 30),
      ]) {
        await logWorkout(at: DateTime.utc(day.year, day.month, day.day, 8));
      }
      final week = await weekOf(today);
      expect(week.entryCount, 3);
      expect(week.targetReached, isTrue);
      expect(
        (await dailyOf(today)).fulfilled,
        isFalse,
        reason: 'today itself still has neither a workout nor a mark',
      );
    });
  });

  group('time zone and day change (AT25)', () {
    test('(BS-99, AT25) the day after midnight is open again, the marked day keeps its mark', () async {
      await start();
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 30)); // 23:30 Berlin
      await markDay(WorkoutDayMarkKind.rest);
      expect((await dailyOf(today)).fulfilled, isTrue);

      harness.clock.advance(const Duration(hours: 1)); // 00:30 the next day
      final next = harness.clock.today();
      expect(next, today.addDays(1));
      expect((await dailyOf(next)).fulfilled, isFalse);
      expect((await dailyOf(today)).fulfilled, isTrue);
    });

    test('(BS-99, AT25) a later change of the zone moves neither the mark nor the workout', () async {
      await start();
      await markDay(WorkoutDayMarkKind.rest);
      await logWorkout(at: DateTime.utc(2026, 10, 3, 6));
      harness.clock.setTimeZone('Pacific/Kiritimati'); // UTC+14

      final facts = await DayFactsSource(db).factsFor(today);
      expect(facts.workoutEntries, 1);
      expect(facts.workoutDayMark, WorkoutDayMarkKind.rest);
      expect(
        (await DayFactsSource(db).factsFor(today.addDays(1))).workoutEntries,
        0,
      );
    });
  });

  group('day facts and the streams', () {
    test('(BS-99) the facts count active workouts and the active mark of the day only', () async {
      await start();
      final markId = await markDay(WorkoutDayMarkKind.skipped);
      final workoutId = await logWorkout();
      await logWorkout(at: DateTime.utc(2026, 10, 3, 6));
      final facts = await DayFactsSource(db).factsFor(today);
      expect(facts.workoutEntries, 2);
      expect(facts.workoutDayMark, WorkoutDayMarkKind.skipped);

      await workouts.delete(commandId: harness.ids.newId(), id: workoutId);
      await marks.unmark(commandId: harness.ids.newId(), id: markId);
      final after = await DayFactsSource(db).factsFor(today);
      expect(after.workoutEntries, 1, reason: 'soft deleted rows never count');
      expect(after.workoutDayMark, isNull);
      expect(
        (await DayFactsSource(db).factsFor(today.addDays(-1))).workoutEntries,
        0,
      );
    });

    test('(BS-99) the day status stream follows a mark and a workout without a restart', () async {
      await start();
      final seen = <bool>[];
      final sub = statusRepository
          .watchDay(today)
          .listen(
            (status) =>
                seen.add(status!.progressOf(GoalType.workoutDaily)!.fulfilled),
          );
      addTearDown(sub.cancel);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 60));

      await settle();
      expect(seen.last, isFalse);

      final markId = await markDay(WorkoutDayMarkKind.rest);
      await settle();
      expect(seen.last, isTrue, reason: 'the table of the marks is watched');

      await marks.unmark(commandId: harness.ids.newId(), id: markId);
      await settle();
      expect(seen.last, isFalse);

      await logWorkout();
      await settle();
      expect(seen.last, isTrue, reason: 'the table of the workouts is watched');
    });

    test('(BS-99) the streak stream follows a mark', () async {
      await start();
      final seen = <int>[];
      final sub = statusRepository.watchStreak().listen(
        (streak) => seen.add(streak?.current ?? -1),
      );
      addTearDown(sub.cancel);
      Future<void> settle() =>
          Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();
      expect(seen.last, 0);
      await markDay(WorkoutDayMarkKind.skipped);
      await settle();
      expect(seen.last, 1);
    });

    test('(BS-99) a workout row with a frozen date in the past counts for that day only', () async {
      await start();
      await db
          .into(db.workoutEntries)
          .insert(
            WorkoutEntriesCompanion.insert(
              id: 'old',
              trainingCategory: 'cardio',
              durationMinutes: 30,
              occurredAtUtc: DateTime.utc(2026, 9, 20, 7),
              localDate: LocalDate(2026, 9, 20),
              timezoneId: 'Europe/Berlin',
              gamificationEligible: false,
              createdAtUtc: DateTime.utc(2026, 9, 20, 7),
              updatedAtUtc: DateTime.utc(2026, 9, 20, 7),
            ),
          );
      final facts = await DayFactsSource(db)
          .factsBetween(LocalDate(2026, 9, 19), LocalDate(2026, 9, 21));
      expect(facts.keys, [LocalDate(2026, 9, 20)]);
      expect(facts[LocalDate(2026, 9, 20)]!.workoutEntries, 1);
    });
  });
}
