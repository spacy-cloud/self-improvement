import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/steps/data/steps_repository.dart';
import 'package:self_improvement/features/body/steps/domain/step_source.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The comparison with the health interface against a real in-memory database
/// (clock 2026-10-03 10:00 Europe/Berlin, daily goal 10.000 steps): the
/// conflict rule, the stored source, atomicity, and what the values of Health
/// do to goal, XP and streak (BS-97, decision D-032).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late StepsRepository steps;

  final today = LocalDate(2026, 10, 3);
  final yesterday = today.addDays(-1);

  Future<void> start({RecordingProjectionSynchronizer? projection}) async {
    harness = await DataHarness.create(
      realProjection: projection == null,
      projections: projection,
    );
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    steps = StepsRepository(
      database: harness.database,
      runner: harness.runner,
      snapshots: GoalSnapshotService(
        database: harness.database,
        clock: harness.clock,
        ids: harness.ids,
      ),
    );
  }

  setUp(start);
  tearDown(() => harness.dispose());

  Future<HealthApplyResult> health(Map<LocalDate, int?> totals) =>
      steps.applyHealthTotals(commandId: harness.ids.newId(), totals: totals);

  Future<void> save(int value, {LocalDate? date}) => steps.setSteps(
    commandId: harness.ids.newId(),
    date: date ?? today,
    steps: value,
  );

  Future<List<StepDayRow>> rows() =>
      harness.database.select(harness.database.stepDays).get();

  Future<int> receipts() async =>
      (await harness.database.select(harness.database.commandReceipts).get())
          .length;

  group('a day without a value (BS-97, AT15)', () {
    test('gets the total with the source health', () async {
      final result = await health({today: 7450});
      expect(result.created, 1);
      expect(result.changed, 1);
      final day = (await steps.findDay(today))!;
      expect(day.steps, 7450);
      expect(day.source, StepSource.health);
      final row = (await rows()).single;
      expect(row.source, 'health');
      expect(row.timezoneId, 'Europe/Berlin');
      expect(row.rowVersion, 1);
    });

    test('a reported 0 is a value, no data is none', () async {
      final result = await health({today: 0, yesterday: null});
      expect(result.created, 1);
      expect(result.noData, 1);
      expect((await steps.findDay(today))!.steps, 0);
      expect(await steps.findDay(yesterday), isNull);
    });

    test('a total above the range of the app is limited to 100.000', () async {
      await health({today: 120000});
      expect((await steps.findDay(today))!.steps, 100000);
    });
  });

  group('a value typed in has priority (BS-97, AT15)', () {
    test('typed in first: Health never overwrites it', () async {
      await save(5000);
      final before = await receipts();
      final result = await health({today: 9000});
      expect(result.keptManual, 1);
      expect(result.changed, 0);
      final day = (await steps.findDay(today))!;
      expect(day.steps, 5000);
      expect(day.source, StepSource.manual);
      expect((await rows()).single.rowVersion, 1);
      expect(await receipts(), before, reason: 'nothing to write, no command');
    });

    test('typed in first: Health with a lower total or none leaves it '
        'too', () async {
      await save(5000);
      await health({today: 100});
      await health({today: 0});
      await health({today: null});
      final day = (await steps.findDay(today))!;
      expect(day.steps, 5000);
      expect(day.source, StepSource.manual);
    });

    test('a manual 0 is a value too and stays', () async {
      await save(0);
      await health({today: 8000});
      final day = (await steps.findDay(today))!;
      expect(day.steps, 0);
      expect(day.source, StepSource.manual);
    });

    test('Health first, then typed in: the day becomes manual and stays '
        'manual', () async {
      await health({today: 7450});
      await save(8000);
      var day = (await steps.findDay(today))!;
      expect(day.steps, 8000);
      expect(day.source, StepSource.manual);
      expect((await rows()).single.rowVersion, 2);

      final result = await health({today: 9000});
      expect(result.keptManual, 1);
      day = (await steps.findDay(today))!;
      expect(day.steps, 8000);
      expect(day.source, StepSource.manual);
    });

    test('undo of a typed-in value on a Health day restores the value and '
        'the source', () async {
      await health({today: 7000});
      final outcome = await steps.setSteps(
        commandId: harness.ids.newId(),
        date: today,
        steps: 8000,
      );
      expect((await steps.findDay(today))!.source, StepSource.manual);
      await outcome.undo!.run(harness.ids.newId());
      final day = (await steps.findDay(today))!;
      expect(day.steps, 7000);
      expect(
        day.source,
        StepSource.health,
        reason: 'the undo writes the source back with the value',
      );
      expect((await rows()).single.rowVersion, 3);
    });

    test('after the undo Health owns the day again and updates it', () async {
      await health({today: 7000});
      final outcome = await steps.setSteps(
        commandId: harness.ids.newId(),
        date: today,
        steps: 8000,
      );
      await outcome.undo!.run(harness.ids.newId());
      final result = await health({today: 7600});
      expect(result.updated, 1);
      expect((await steps.findDay(today))!.steps, 7600);
    });

    test('undo of a typed-in value that is a day of its own removes it and '
        'Health may fill it afterwards', () async {
      final outcome = await steps.setSteps(
        commandId: harness.ids.newId(),
        date: today,
        steps: 4000,
      );
      await outcome.undo!.run(harness.ids.newId());
      expect(await steps.findDay(today), isNull);
      await health({today: 4100});
      expect((await steps.findDay(today))!.source, StepSource.health);
    });
  });

  group('Health updates only its own values (BS-97)', () {
    test('a changed total updates the value and keeps the source', () async {
      await health({today: 5000});
      final result = await health({today: 7000});
      expect(result.updated, 1);
      final day = (await steps.findDay(today))!;
      expect(day.steps, 7000);
      expect(day.source, StepSource.health);
      expect((await rows()).single.rowVersion, 2);
    });

    test('a lower total updates it too (Health is the source of the '
        'day)', () async {
      await health({today: 7000});
      await health({today: 6500});
      expect((await steps.findDay(today))!.steps, 6500);
    });

    test('the same total changes nothing and runs no command', () async {
      await health({today: 5000});
      final before = await receipts();
      final result = await health({today: 5000});
      expect(result.unchanged, 1);
      expect(result.changed, 0);
      expect((await rows()).single.rowVersion, 1);
      expect(await receipts(), before);
    });

    test('no data keeps an earlier value of Health', () async {
      await health({today: 5000});
      final result = await health({today: null});
      expect(result.noData, 1);
      expect((await steps.findDay(today))!.steps, 5000);
    });

    test('a day the user deleted is filled again by the next comparison '
        '(Health is the source while the switch is on)', () async {
      await health({today: 5000});
      await steps.deleteDay(commandId: harness.ids.newId(), date: today);
      expect(await steps.findDay(today), isNull);
      final result = await health({today: 5200});
      expect(result.created, 1);
      expect((await steps.findDay(today))!.steps, 5200);
      final all = await rows();
      expect(all, hasLength(2), reason: 'the deleted row stays, soft deleted');
      expect(all.where((row) => row.deletedAtUtc == null), hasLength(1));
    });
  });

  group('several days in one call (BS-97)', () {
    test('every day follows the rule on its own', () async {
      final manualDay = today.addDays(-6);
      final healthDay = today.addDays(-5);
      await save(3000, date: manualDay);
      await health({healthDay: 1000});
      final result = await health({
        manualDay: 9999,
        healthDay: 2000,
        today.addDays(-4): 4000,
        today.addDays(-3): null,
        today.addDays(-2): 0,
        yesterday: 1000,
        today: 8000,
      });
      expect(result.keptManual, 1);
      expect(result.updated, 1);
      expect(result.created, 4);
      expect(result.noData, 1);
      expect(result.total, 7);
      expect((await steps.findDay(manualDay))!.steps, 3000);
      expect((await steps.findDay(healthDay))!.steps, 2000);
      expect((await steps.findDay(today.addDays(-4)))!.steps, 4000);
      expect(await steps.findDay(today.addDays(-3)), isNull);
      expect((await steps.findDay(today.addDays(-2)))!.steps, 0);
      expect((await steps.findDay(yesterday))!.steps, 1000);
      expect((await steps.findDay(today))!.steps, 8000);
    });

    test('an empty call writes nothing', () async {
      final result = await health({});
      expect(result, HealthApplyResult.none);
      expect(await rows(), isEmpty);
    });

    test('only the changed days are projected', () async {
      final projection = RecordingProjectionSynchronizer();
      await harness.dispose();
      await start(projection: projection);
      await save(3000, date: today.addDays(-3));
      projection.syncs.clear();
      await health({
        today.addDays(-3): 9999, // typed in: untouched
        today.addDays(-2): 2000, // new
        yesterday: null, // no data
        today: 8000, // new
      });
      expect(projection.syncs, hasLength(1));
      expect(projection.syncs.single, {today.addDays(-2), today});
    });

    test('a second call with the same totals projects nothing', () async {
      final projection = RecordingProjectionSynchronizer();
      await harness.dispose();
      await start(projection: projection);
      await health({today: 8000, yesterday: 6000});
      projection.syncs.clear();
      await health({today: 8000, yesterday: 6000});
      expect(projection.syncs, isEmpty);
    });
  });

  group('one command per run (BS-97, AT12, AT27)', () {
    test('a replayed command id is one effect (AT12)', () async {
      await steps.applyHealthTotals(commandId: 'run', totals: {today: 1000});
      await steps.applyHealthTotals(commandId: 'run', totals: {today: 9000});
      expect((await steps.findDay(today))!.steps, 1000);
    });

    test('a failing projection rolls every day back (AT27)', () async {
      final projection = RecordingProjectionSynchronizer();
      await harness.dispose();
      await start(projection: projection);
      projection.failure = StateError('projection failed');
      await expectLater(
        health({today: 8000, yesterday: 6000, today.addDays(-2): 4000}),
        throwsA(isA<StorageFailure>()),
      );
      expect(await rows(), isEmpty, reason: 'all days or none');
      expect(await receipts(), 0);
    });

    test('the run leaves a receipt and publishes one event', () async {
      final events = <Object>[];
      final subscription = harness.events.stream.listen(events.add);
      addTearDown(subscription.cancel);
      await health({today: 8000, yesterday: 6000});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(await receipts(), 1);
    });
  });

  group('goal, XP and streak (BS-97, AT23, AT26)', () {
    Future<int> xp() => harness.totalXp();

    Future<List<XpAwardRow>> awards() =>
        harness.database.select(harness.database.xpAwards).get();

    test('a total that reaches the goal earns the XP of that day like a typed '
        'one', () async {
      await health({yesterday: 11000});
      expect(await xp(), 10);
      final award = (await awards()).single;
      expect(award.localDate, yesterday, reason: 'dated on the day, not today');
      final day = (await steps.findDay(yesterday))!;
      expect(day.reachedGoalEligible, isTrue);
      expect(day.xpGoalTargetSteps, 10000);
    });

    test('a total below the goal earns nothing and decides nothing', () async {
      await health({today: 9000});
      expect(await xp(), 0);
      expect((await steps.findDay(today))!.reachedGoalEligible, isNull);
    });

    test('a later total for a past day changes the XP of that day, both '
        'ways, and never counts twice (AT23)', () async {
      final day = today.addDays(-3);
      await health({day: 8000});
      expect(await xp(), 0);
      await health({day: 12000});
      expect(await xp(), 10, reason: 'the past day now reaches the goal');
      expect((await awards()).single.localDate, day);
      await health({day: 12500});
      expect(await xp(), 10, reason: 'still once per day');
      await health({day: 9000});
      expect(
        await xp(),
        0,
        reason: 'below the frozen threshold the award is taken back',
      );
      expect(
        (await steps.findDay(day))!.reachedGoalEligible,
        isTrue,
        reason: 'the decision stays frozen',
      );
      await health({day: 11000});
      expect(await xp(), 10);
    });

    test('syncing the same day again never adds points (AT12)', () async {
      await health({yesterday: 11000});
      await health({yesterday: 11000});
      await health({yesterday: 11000, today: 500});
      expect(await xp(), 10);
    });

    test('a goal reached while gamification was off is never paid out later '
        '(AT26)', () async {
      await harness.database
          .into(harness.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'off',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
              localDate: today,
              enabled: false,
            ),
          );
      await health({yesterday: 11000});
      final day = (await steps.findDay(yesterday))!;
      expect(day.reachedGoalEligible, isFalse);
      expect(await xp(), 0);
      await harness.database
          .into(harness.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'on',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 20),
              localDate: today,
              enabled: true,
            ),
          );
      await health({yesterday: 12000});
      expect(await xp(), 0, reason: 'frozen when the goal was first reached');
    });

    test('the day status counts a Health total for the goal (AT23)', () async {
      await health({today: 10500, yesterday: 4000});
      final status = harness.dayStatusRepository();
      final reached = (await status.statusFor(today))!;
      final steps0 = reached.goals.singleWhere(
        (goal) => goal.goalKey == GoalType.steps.key,
      );
      expect(steps0.fulfilled, isTrue);
      expect(reached.isActive, isTrue);
      final missed = (await status.statusFor(yesterday))!;
      final steps1 = missed.goals.singleWhere(
        (goal) => goal.goalKey == GoalType.steps.key,
      );
      expect(steps1.fulfilled, isFalse);
    });

    test('the streak counts days that Health filled and follows a later '
        'change of a past day (AT23)', () async {
      final status = harness.dayStatusRepository();
      await health({
        today: 10500,
        yesterday: 10200,
        today.addDays(-2): 3000,
        today.addDays(-3): 10100,
      });
      var streak = (await status.computeStreakSummary())!;
      expect(streak.current, 2, reason: 'today and yesterday, then a gap');
      // The day in between reaches the goal later: the streak jumps back in
      // time, because it is recomputed from the facts.
      await health({today.addDays(-2): 10300});
      streak = (await status.computeStreakSummary())!;
      expect(streak.current, 4);
      // And it falls again when Health lowers the value.
      await health({today.addDays(-2): 2000});
      streak = (await status.computeStreakSummary())!;
      expect(streak.current, 2);
    });

    test('a typed-in value for the same day wins in goal and XP too '
        '(AT23)', () async {
      await save(2000, date: yesterday);
      await health({yesterday: 12000});
      expect(await xp(), 0, reason: 'Health may not lift a typed-in day');
      await save(11000, date: yesterday);
      expect(await xp(), 10);
    });
  });
}
