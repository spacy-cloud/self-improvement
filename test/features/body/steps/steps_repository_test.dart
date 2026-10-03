import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/steps/data/steps_repository.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late StepsRepository steps;

  final today = LocalDate(2026, 10, 3);

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

  Future<void> save(int value, {LocalDate? date}) => steps.setSteps(
    commandId: harness.ids.newId(),
    date: date ?? today,
    steps: value,
  );

  group('replace semantics (AT15)', () {
    test('7.450 followed by 8.000 is 8.000, never 15.450', () async {
      await save(7450);
      await save(8000);
      expect((await steps.findDay(today))!.steps, 8000);
      expect(await steps.watchAll().first, hasLength(1));
    });

    test('zero is a recorded value, a missing day has no record', () async {
      expect(await steps.findDay(today), isNull);
      await save(0);
      final day = (await steps.findDay(today))!;
      expect(day.steps, 0);
      expect(day.rowVersion, 1);
      expect(
        await steps.findDay(today.addDays(-1)),
        isNull,
        reason: '"Nicht erfasst"',
      );
    });

    test('a replace bumps the version and keeps one row per date', () async {
      await save(1000);
      await save(2000);
      await save(3000);
      final rows = await harness.database
          .select(harness.database.stepDays)
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.rowVersion, 3);
    });

    test(
      'back-dating is allowed, the future is not, nor before 2000',
      () async {
        await save(500, date: today.addDays(-30));
        expect((await steps.findDay(today.addDays(-30)))!.steps, 500);
        await expectLater(
          save(500, date: today.addDays(1)),
          throwsA(isA<ValidationFailure>()),
        );
        await expectLater(
          save(500, date: LocalDate(1999, 12, 31)),
          throwsA(isA<ValidationFailure>()),
        );
      },
    );

    test('value bounds 0 / 100.000 / 100.001', () async {
      await save(0);
      await save(100000);
      await expectLater(save(100001), throwsA(isA<ValidationFailure>()));
      await expectLater(save(-1), throwsA(isA<ValidationFailure>()));
      expect(
        (await steps.findDay(today))!.steps,
        100000,
        reason: 'a rejected save changes nothing',
      );
    });

    test('a replayed command id is one effect', () async {
      await steps.setSteps(commandId: 'a', date: today, steps: 1000);
      await steps.setSteps(commandId: 'a', date: today, steps: 9000);
      expect((await steps.findDay(today))!.steps, 1000);
    });
  });

  group('XP with the frozen threshold (AT24, AT26)', () {
    Future<int> xp() => harness.totalXp();

    test('below the goal: no claim; reaching it earns 10 XP once', () async {
      await save(9000);
      expect(await xp(), 0);
      final below = (await steps.findDay(today))!;
      expect(
        below.reachedGoalEligible,
        isNull,
        reason: 'early input creates no claim',
      );
      await save(10000);
      final reached = (await steps.findDay(today))!;
      expect(reached.reachedGoalEligible, isTrue);
      expect(reached.xpGoalTargetSteps, 10000);
      expect(await xp(), 10);
      await save(15000);
      expect(await xp(), 10, reason: 'still once per day');
    });

    test('a correction below the frozen threshold removes the award, going back restores it', () async {
      await save(10000);
      expect(await xp(), 10);
      await save(9500);
      expect(await xp(), 0, reason: 'must still reach the frozen threshold');
      expect(
        (await steps.findDay(today))!.reachedGoalEligible,
        isTrue,
        reason: 'decision is kept',
      );
      await save(10000);
      expect(await xp(), 10);
    });

    test(
      'reached while gamification was off is never paid out later (AT26)',
      () async {
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
        await save(10000);
        final day = (await steps.findDay(today))!;
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
        await save(12000);
        expect(
          await xp(),
          0,
          reason: 'the decision was frozen when the goal was first reached',
        );
      },
    );

    test(
      'a goal changed for tomorrow does not move today\'s threshold (AT24)',
      () async {
        final goals = GoalsCommands(
          runner: harness.runner,
          versions: GoalVersionRepository(harness.database),
        );
        await save(9000);
        await goals.update(
          commandId: 'g',
          changes: const {GoalType.steps: GoalSetting(target: 8000)},
        );
        await save(9500);
        expect(await xp(), 0, reason: 'today still needs 10.000');
        harness.clock.advance(const Duration(days: 1));
        await save(8000, date: today.addDays(1));
        expect(await xp(), 10, reason: 'tomorrow uses 8.000');
      },
    );

    test(
      'no applicable goal (steps switched off) means no threshold and no claim',
      () async {
        await harness.database
            .into(harness.database.goalVersions)
            .insert(
              GoalVersionsCompanion.insert(
                id: 'steps-off',
                goalType: 'steps',
                targetInteger: const Value(10000),
                enabled: false,
                effectiveFromDate: LocalDate(2026, 10, 2),
                createdAtUtc: DateTime.utc(2026, 10, 2),
              ),
            );
        await save(20000);
        final day = (await steps.findDay(today))!;
        expect(day.reachedGoalEligible, isNull);
        expect(await xp(), 0);
      },
    );

    test('module off today: no applicable target', () async {
      await harness.database
          .into(harness.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'body-off',
              moduleId: 'body',
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
              localDate: today,
              enabled: false,
            ),
          );
      await save(20000);
      expect((await steps.findDay(today))!.reachedGoalEligible, isNull);
    });

    test('a back-dated day uses the threshold of THAT day (snapshot created on demand)', () async {
      await save(10000, date: LocalDate(2026, 9, 20));
      expect(
        (await steps.findDay(LocalDate(2026, 9, 20)))!.xpGoalTargetSteps,
        10000,
      );
      expect(await xp(), 10);
    });
  });

  group('delete and undo', () {
    test('deleting a day makes it "Nicht erfasst" and removes the XP; undo restores it', () async {
      await save(10000);
      expect(await harness.totalXp(), 10);
      final deleted = await steps.deleteDay(
        commandId: harness.ids.newId(),
        date: today,
      );
      expect(await steps.findDay(today), isNull);
      expect(await harness.totalXp(), 0);
      await deleted.undo!.run(harness.ids.newId());
      expect((await steps.findDay(today))!.steps, 10000);
      expect(await harness.totalXp(), 10);
    });

    test(
      'undoing a replace restores the previous value and decision',
      () async {
        await save(9000);
        final outcome = await steps.setSteps(
          commandId: 'u',
          date: today,
          steps: 10000,
        );
        expect(await harness.totalXp(), 10);
        await outcome.undo!.run(harness.ids.newId());
        final day = (await steps.findDay(today))!;
        expect(day.steps, 9000);
        expect(day.reachedGoalEligible, isNull);
        expect(await harness.totalXp(), 0);
      },
    );

    test('undoing the first save removes the day', () async {
      final outcome = await steps.setSteps(
        commandId: 'u',
        date: today,
        steps: 5000,
      );
      await outcome.undo!.run(harness.ids.newId());
      expect(await steps.findDay(today), isNull);
    });

    test('undo is refused after a later edit', () async {
      final first = await steps.setSteps(
        commandId: 'a',
        date: today,
        steps: 5000,
      );
      await save(6000);
      await expectLater(
        first.undo!.run(harness.ids.newId()),
        throwsA(
          isA<ConflictFailure>().having(
            (f) => f.kind,
            'kind',
            ConflictKind.staleVersion,
          ),
        ),
      );
      expect((await steps.findDay(today))!.steps, 6000);
    });

    test('undoing a delete is refused when the day was filled again', () async {
      await save(5000);
      final deleted = await steps.deleteDay(
        commandId: harness.ids.newId(),
        date: today,
      );
      await save(7000);
      await expectLater(
        deleted.undo!.run(harness.ids.newId()),
        throwsA(isA<ConflictFailure>()),
      );
      expect((await steps.findDay(today))!.steps, 7000);
    });

    test('deleting a missing day is not found', () async {
      await expectLater(
        steps.deleteDay(commandId: 'x', date: today),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  test('a storage failure leaves no value and no XP (AT27)', () async {
    await harness.dispose();
    final failing = RecordingProjectionSynchronizer()
      ..failure = StateError('disk');
    await start(projection: failing);
    await expectLater(
      steps.setSteps(commandId: 'f', date: today, steps: 10000),
      throwsA(isA<StorageFailure>()),
    );
    expect(await steps.findDay(today), isNull);
    failing.failure = null;
    await steps.setSteps(commandId: 'f', date: today, steps: 10000);
    expect((await steps.findDay(today))!.steps, 10000);
  });
}
