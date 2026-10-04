import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/nutrition_test_kit.dart';

/// Water with the REAL projection: snapshots and XP run inside the commands
/// like in the app (AT10, AT11, AT12, AT24, AT26, AT27).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late WaterRepository repository;

  setUp(() async {
    kit = await NutritionKit.create(realProjection: true, onboarded: true);
    repository = kit.water;
  });
  tearDown(() => kit.dispose());

  Future<String> add(int ml, DateTime when) async {
    final outcome = await repository.create(
      commandId: kit.newId(),
      draft: WaterDraft(amountMl: ml, occurredAtUtc: when),
    );
    return outcome.entityId!;
  }

  /// Drinks [totalMl] as entries of at most 1300 ml, starting at [start].
  Future<void> drink(int totalMl, DateTime start) async {
    var left = totalMl;
    var minute = 0;
    while (left > 0) {
      final part = left > 1300 ? 1300 : left;
      await add(part, start.add(Duration(minutes: minute++)));
      left -= part;
    }
  }

  Future<int> xp() => kit.harness.totalXp();

  group('AT10: quick add and undo', () {
    test('+250 ml adds the amount and 5 XP; undo removes both', () async {
      final outcome = await repository.quickAdd(
        commandId: kit.newId(),
        amountMl: 250,
      );
      expect((await repository.loadToday(kitToday)).totalMl, 250);
      expect(await xp(), 5);
      expect(await kit.awardKeys('water'), ['water:${outcome.entityId}']);

      await outcome.undo!.run(kit.newId());
      expect((await repository.loadToday(kitToday)).totalMl, 0);
      expect(await xp(), 0);
      expect(await kit.awards(), isEmpty);
    });

    test('+500 ml: amount and XP, undo removes exactly that entry', () async {
      await repository.quickAdd(commandId: kit.newId(), amountMl: 250);
      final outcome = await repository.quickAdd(
        commandId: kit.newId(),
        amountMl: 500,
      );
      expect((await repository.loadToday(kitToday)).totalMl, 750);
      expect(await xp(), 10);

      await outcome.undo!.run(kit.newId());
      final today = await repository.loadToday(kitToday);
      expect(today.totalMl, 250, reason: 'only the 500 ml entry is gone');
      expect(await xp(), 5);
    });

    test('an entry below 100 ml is stored but earns nothing', () async {
      await add(50, at(5));
      await add(99, at(6));
      expect((await repository.loadToday(kitToday)).totalMl, 149);
      expect(await xp(), 0);
      await add(100, at(7));
      expect(await xp(), 5, reason: '100 ml is the smallest qualifying amount');
    });

    test(
      'quick add is one command: the dashboard needs no second call',
      () async {
        await repository.quickAdd(commandId: kit.newId(), amountMl: 250);
        final receipts = await kit.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandType, WaterRepository.quickAddType);
      },
    );
  });

  group('AT11: at most 20 XP per day, a later entry moves up', () {
    test('five qualifying entries earn 20 XP in total', () async {
      for (var hour = 1; hour <= 5; hour++) {
        await add(250, at(hour));
      }
      expect(await xp(), 20);
      expect((await kit.awardKeys('water')).length, 4);
      expect(
        (await repository.loadToday(kitToday)).entryCount,
        5,
        reason: 'all five entries exist and count for the total',
      );
    });

    test('deleting an earlier entry lets the fifth move up, still 20 XP', () async {
      final ids = <String>[];
      for (var hour = 1; hour <= 5; hour++) {
        ids.add(await add(250, at(hour)));
      }
      expect(
        await kit.awardKeys('water'),
        [for (final id in ids.take(4)) 'water:$id']..sort(),
      );

      final deleted = await repository.delete(
        commandId: kit.newId(),
        id: ids.first,
      );
      expect(await xp(), 20, reason: 'the fifth entry took the free place');
      expect(
        await kit.awardKeys('water'),
        [for (final id in ids.skip(1)) 'water:$id']..sort(),
      );

      // Undo: the first entry takes its place back, the fifth drops out again.
      await deleted.undo!.run(kit.newId());
      expect(await xp(), 20);
      expect(
        await kit.awardKeys('water'),
        [for (final id in ids.take(4)) 'water:$id']..sort(),
      );
    });

    test('with only three entries deleting one takes its 5 XP away', () async {
      final ids = [for (var h = 1; h <= 3; h++) await add(250, at(h))];
      expect(await xp(), 15);
      await repository.delete(commandId: kit.newId(), id: ids.first);
      expect(await xp(), 10);
    });

    test('small entries never take one of the four places', () async {
      await add(50, at(1));
      await add(80, at(2));
      for (var hour = 3; hour <= 6; hour++) {
        await add(250, at(hour));
      }
      expect(await xp(), 20);
      expect((await kit.awardKeys('water')).length, 4);
    });

    test('the limit is per stored local day', () async {
      for (var hour = 1; hour <= 5; hour++) {
        await add(250, at(hour));
      }
      for (var hour = 1; hour <= 5; hour++) {
        await add(250, at(hour, 0, 2));
      }
      expect(await xp(), 40, reason: '20 XP on each of two days');
    });
  });

  group('AT12: idempotent commands', () {
    test('the same command id twice is one entry and one award', () async {
      final first = await repository.quickAdd(commandId: 'once', amountMl: 250);
      final second = await repository.quickAdd(
        commandId: 'once',
        amountMl: 250,
      );
      expect(second.replayed, isTrue);
      expect(second.entityId, first.entityId);
      expect(await kit.waterRows(), hasLength(1));
      expect(await xp(), 5);
      expect(await kit.awards(), hasLength(1));
    });

    test(
      'a new id is a new input: two quick taps are two entries and two awards',
      () async {
        await repository.quickAdd(commandId: 'tap-1', amountMl: 250);
        await repository.quickAdd(commandId: 'tap-2', amountMl: 250);
        expect(await kit.waterRows(), hasLength(2));
        expect(await xp(), 10);
      },
    );

    test('rapid independent taps in parallel are all stored once', () async {
      final taps = [
        for (var i = 0; i < 6; i++)
          repository.quickAdd(commandId: 'tap-$i', amountMl: 250),
      ];
      await Future.wait(taps);
      expect(await kit.waterRows(), hasLength(6));
      expect((await repository.loadToday(kitToday)).totalMl, 1500);
      expect(await xp(), 20, reason: 'capped at four awards per day');
    });

    test('replaying an undo never removes anything twice', () async {
      final outcome = await repository.quickAdd(commandId: 'a', amountMl: 250);
      await repository.quickAdd(commandId: 'b', amountMl: 250);
      await outcome.undo!.run('undo-a');
      await outcome.undo!.run('undo-a');
      expect((await repository.loadToday(kitToday)).totalMl, 250);
      expect(await xp(), 5);
    });
  });

  group('AT24: a changed target applies from tomorrow', () {
    late GoalsCommands goals;

    setUp(() {
      goals = GoalsCommands(
        runner: kit.harness.runner,
        versions: GoalVersionRepository(kit.database),
      );
    });

    Future<void> setTarget(int ml) => goals
        .update(
          commandId: kit.newId(),
          changes: {GoalType.water: GoalSetting(target: ml)},
        )
        .then((_) {});

    test('today keeps the old threshold, tomorrow uses the new one', () async {
      // Today the user reached 2600 ml of the 2500 ml target.
      await drink(2600, at(5));
      await setTarget(4000);
      var today = await repository.loadToday(kitToday);
      expect(today.targetMl, 2500, reason: 'today keeps its frozen threshold');
      expect(today.goalReached, isTrue);

      // The next day: new threshold 4000, the old day still shows 2500.
      kit.harness.clock.advance(const Duration(days: 1));
      final tomorrow = kit.harness.clock.today();
      expect(tomorrow, LocalDate(2026, 10, 4));
      today = await repository.loadToday(tomorrow);
      expect(
        today.targetMl,
        4000,
        reason: 'no snapshot yet: the version applies',
      );
      expect(today.totalMl, 0);

      await drink(2600, DateTime.utc(2026, 10, 4, 5));
      today = await repository.loadToday(tomorrow);
      expect(today.targetMl, 4000, reason: 'the new day froze 4000');
      expect(today.goalReached, isFalse, reason: '2600 of 4000');

      final yesterday = await repository.loadHistory(today: tomorrow, days: 7);
      final oct3 = yesterday.daysNewestFirst.last;
      expect(oct3.date, kitToday);
      expect(oct3.targetMl, 2500);
      expect(oct3.goalReached, isTrue, reason: 'the old day keeps its result');
    });

    test(
      'the ring of today follows the frozen threshold, not the new goal',
      () async {
        await drink(2600, at(5));
        await setTarget(4000);
        final status = (await kit.harness.dayStatusRepository().statusFor(
          kitToday,
        ))!;
        final water = status.goals.singleWhere((g) => g.goalKey == 'water');
        expect(water.target, 2500);
        expect(water.fulfilled, isTrue);
      },
    );

    test(
      'a target change before any entry today still applies only tomorrow',
      () async {
        await setTarget(3000);
        expect((await repository.loadToday(kitToday)).targetMl, 2500);
        await add(250, at(6));
        expect(
          (await repository.loadToday(kitToday)).targetMl,
          2500,
          reason: 'the snapshot created by the first entry freezes today',
        );
      },
    );
  });

  group('AT27: a storage failure stores nothing', () {
    test(
      'no amount, no XP, no snapshot; a retry with the same id works',
      () async {
        final failing = FlakyProjection(kit.harness.projections);
        final runner = buildRunner(kit.harness, failing);
        final flaky = buildWaterRepository(kit.harness, runner: runner);

        failing.failAfterSync = StateError('disk full');
        await expectLater(
          flaky.quickAdd(commandId: 'tap', amountMl: 250),
          throwsA(isA<StorageFailure>()),
        );
        expect(await kit.waterRows(), isEmpty, reason: 'no amount');
        expect(
          await kit.awards(),
          isEmpty,
          reason: 'no XP survives the rollback',
        );
        expect(await xp(), 0);
        expect(await kit.receipts(), isEmpty);
        expect(
          await kit.database.select(kit.database.dailyGoalSnapshots).get(),
          isEmpty,
          reason:
              'the snapshots written inside the transaction rolled back too',
        );

        failing.failAfterSync = null;
        final outcome = await flaky.quickAdd(commandId: 'tap', amountMl: 250);
        expect(outcome.replayed, isFalse);
        expect(await kit.waterRows(), hasLength(1));
        expect(await xp(), 5);

        // A third try with the same id is a replay, not a second entry.
        final again = await flaky.quickAdd(commandId: 'tap', amountMl: 250);
        expect(again.replayed, isTrue);
        expect(await kit.waterRows(), hasLength(1));
        expect(await xp(), 5);
      },
    );

    test('a failing delete keeps the entry and its XP', () async {
      final failing = FlakyProjection(kit.harness.projections);
      final flaky = buildWaterRepository(
        kit.harness,
        runner: buildRunner(kit.harness, failing),
      );
      final outcome = await flaky.quickAdd(commandId: 'tap', amountMl: 250);
      failing.failAfterSync = StateError('disk full');
      await expectLater(
        flaky.delete(commandId: 'del', id: outcome.entityId!),
        throwsA(isA<StorageFailure>()),
      );
      failing.failAfterSync = null;
      expect((await repository.loadToday(kitToday)).totalMl, 250);
      expect(await xp(), 5);
    });
  });

  group('AT23: correcting the past', () {
    test(
      'editing across midnight moves the amount and its award to the other day',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 10, 3, 23));
        final id = await add(300, DateTime.utc(2026, 10, 3, 21, 30)); // 23:30
        await add(200, DateTime.utc(2026, 10, 3, 21, 0)); // 23:00
        final oct3 = LocalDate(2026, 10, 3);
        final oct4 = LocalDate(2026, 10, 4);
        expect((await repository.loadToday(oct3)).totalMl, 500);
        expect(await xp(), 10);

        await repository.update(
          commandId: kit.newId(),
          id: id,
          draft: WaterDraft(
            amountMl: 300,
            occurredAtUtc: DateTime.utc(
              2026,
              10,
              3,
              22,
              30,
            ), // 00:30 on the 4th
          ),
          expectedRowVersion: 1,
        );
        expect((await repository.loadToday(oct3)).totalMl, 200);
        expect((await repository.loadToday(oct4)).totalMl, 300);
        final awards = await kit.awards();
        final byId = {for (final a in awards) a.awardKey: a.localDate};
        expect(
          byId['water:$id'],
          oct4,
          reason: 'the award moved with the entry',
        );
        expect(await xp(), 10, reason: 'nothing was awarded twice');
      },
    );

    test(
      'deleting a back-dated entry takes its XP back, undo restores it',
      () async {
        final id = await add(250, DateTime.utc(2026, 10, 1, 8));
        expect(await xp(), 5);
        final deleted = await repository.delete(commandId: kit.newId(), id: id);
        expect(await xp(), 0);
        await deleted.undo!.run(kit.newId());
        expect(await xp(), 5);
      },
    );

    test(
      'an entry before the profile start is stored but earns nothing',
      () async {
        await add(250, DateTime.utc(2026, 8, 20, 8));
        expect(
          (await repository.loadHistory(today: kitToday, days: 60)).isEmpty,
          isFalse,
        );
        expect(await xp(), 0);
      },
    );

    test(
      'a stale undo after another edit leaves entry and XP untouched',
      () async {
        final outcome = await repository.quickAdd(
          commandId: 'a',
          amountMl: 250,
        );
        await repository.update(
          commandId: kit.newId(),
          id: outcome.entityId!,
          draft: WaterDraft(amountMl: 400, occurredAtUtc: at(8)),
          expectedRowVersion: 1,
        );
        await expectLater(
          outcome.undo!.run(kit.newId()),
          throwsA(
            isA<ConflictFailure>().having(
              (f) => f.kind,
              'kind',
              ConflictKind.staleVersion,
            ),
          ),
        );
        expect((await repository.loadToday(kitToday)).totalMl, 400);
        expect(await xp(), 5);
      },
    );
  });

  group('AT26: gamification switched off', () {
    test('entries created while it is off are never eligible, also after switching on', () async {
      await kit.database
          .into(kit.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'off',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: kit.harness.clock.nowUtc(),
              localDate: kitToday,
              enabled: false,
            ),
          );
      final outcome = await repository.quickAdd(commandId: 'a', amountMl: 250);
      expect(
        (await repository.findById(outcome.entityId!))!.gamificationEligible,
        isFalse,
      );
      expect(await xp(), 0);
      expect((await repository.loadToday(kitToday)).totalMl, 250);

      kit.harness.clock.advance(const Duration(minutes: 5));
      await kit.database
          .into(kit.database.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'on',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: kit.harness.clock.nowUtc(),
              localDate: kitToday,
              enabled: true,
            ),
          );
      await kit.harness.projections.syncDays({kitToday});
      expect(await xp(), 0, reason: 'no retroactive payout');

      await repository.quickAdd(commandId: 'b', amountMl: 250);
      expect(
        await xp(),
        5,
        reason: 'a new entry after reactivation is eligible',
      );
    });
  });

  group('reaching the target', () {
    test('creates no extra record and no extra award', () async {
      for (var i = 0; i < 5; i++) {
        kit.harness.clock.advance(const Duration(minutes: 1));
        await repository.quickAdd(commandId: 'tap-$i', amountMl: 500);
      }
      final today = await repository.loadToday(kitToday);
      expect(today.totalMl, 2500);
      expect(today.goalReached, isTrue);
      expect(today.percent, 100);
      expect(
        await kit.waterRows(),
        hasLength(5),
        reason: 'exactly the five taps',
      );
      expect(await xp(), 20);
      final status = (await kit.harness.dayStatusRepository().statusFor(
        kitToday,
      ))!;
      expect(
        status.goals.singleWhere((g) => g.goalKey == 'water').fulfilled,
        isTrue,
      );
    });

    test('exceeding it keeps the real total and the capped bar', () async {
      for (var i = 0; i < 6; i++) {
        kit.harness.clock.advance(const Duration(minutes: 1));
        await repository.quickAdd(commandId: 'tap-$i', amountMl: 500);
      }
      final today = await repository.loadToday(kitToday);
      expect(today.totalMl, 3000);
      expect(today.fraction, 1.0);
      expect(today.percent, 120);
    });

    test(
      'undoing the entry that reached the goal reverts the goal state',
      () async {
        for (var i = 0; i < 4; i++) {
          kit.harness.clock.advance(const Duration(minutes: 1));
          await repository.quickAdd(commandId: 'tap-$i', amountMl: 500);
        }
        kit.harness.clock.advance(const Duration(minutes: 1));
        final last = await repository.quickAdd(
          commandId: 'last',
          amountMl: 500,
        );
        expect((await repository.loadToday(kitToday)).goalReached, isTrue);
        await last.undo!.run(kit.newId());
        final today = await repository.loadToday(kitToday);
        expect(today.goalReached, isFalse);
        expect(today.totalMl, 2000);
        expect(today.percent, 80);
      },
    );
  });
}
