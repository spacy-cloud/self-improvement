import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

/// Runs the real projection and THEN fails, like a disk error at the very end
/// of the transaction: everything the sync wrote must be rolled back.
final class _FailAfterSync implements ProjectionSynchronizer {
  _FailAfterSync(this._inner);

  final ProjectionSynchronizer _inner;
  bool failing = true;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    await _inner.syncDays(days);
    if (failing) {
      throw StateError('disk full');
    }
  }

  @override
  Future<int> totalXp() => _inner.totalXp();
}

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late HabitRepository repository;

  final today = LocalDate(2026, 10, 3);

  Future<void> bootHarness({
    LocalDate? profileStart,
    String nowIso = '2026-10-03T08:00:00Z',
  }) async {
    harness = await DataHarness.create(realProjection: true, nowIso: nowIso);
    await harness.seedOnboarded(
      startedOn: profileStart ?? LocalDate(2026, 9, 1),
    );
    repository = HabitRepository(
      database: harness.database,
      runner: harness.runner,
    );
  }

  setUp(bootHarness);
  tearDown(() => harness.dispose());

  Future<String> create([String title = 'Lesen']) async {
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: HabitDraft(title: title),
    );
    return outcome.entityId!;
  }

  /// Creates a habit that started [start]; the clock returns to "now".
  Future<String> createStartedOn(
    LocalDate start, [
    String title = 'Lesen',
  ]) async {
    final back = harness.clock.nowUtc();
    setLocalNow(harness, start);
    final id = await create(title);
    harness.clock.setNow(back);
    return id;
  }

  Future<CommandOutcome> check(String id, LocalDate date) =>
      repository.setChecked(
        commandId: harness.ids.newId(),
        habitId: id,
        date: date,
        checked: true,
      );

  Future<CommandOutcome> uncheck(String id, LocalDate date) =>
      repository.setChecked(
        commandId: harness.ids.newId(),
        habitId: id,
        date: date,
        checked: false,
      );

  Future<int> xp() => harness.totalXp();

  Future<Map<String, int>> awards() => awardPoints(harness);

  Future<DayStatus> status(LocalDate day) async =>
      (await harness.dayStatusRepository().statusFor(day))!;

  Future<({int current, int longest})> streak() async {
    final summary = (await harness
        .dayStatusRepository()
        .computeStreakSummary())!;
    return (current: summary.current, longest: summary.longest);
  }

  Future<HabitDetail> detail(String id) async {
    final habit = (await repository.findById(id))!;
    final checks = await repository.watchChecks().first;
    return buildHabitDetail(
      habit: habit,
      checkedDates: checks.datesOf(id),
      today: harness.clock.today(),
    );
  }

  String key(String id, LocalDate date) => 'habit:$id:${date.toIso()}';

  group('AT21: check, undo, new day, archive from tomorrow', () {
    test('the whole flow gives correct checks, ring, XP and history', () async {
      final id = await create();
      expect(
        (await status(today)).applicableCount,
        6,
        reason: 'a new habit adds a daily goal',
      );
      expect((await status(today)).fulfilledCount, 0);

      // Check today: 5 XP and the ring moves.
      final checked = await check(id, today);
      expect(await xp(), 5);
      expect((await status(today)).fulfilledCount, 1);
      expect(await awards(), {key(id, today): 5});

      // Undo removes the check, the XP and the ring progress.
      await checked.undo!.run(harness.ids.newId());
      expect(await xp(), 0);
      expect((await status(today)).fulfilledCount, 0);

      // Checking again reactivates the same row (still one row for the day).
      await check(id, today);
      expect(await xp(), 5);
      final rows = await harness.database
          .select(harness.database.habitChecks)
          .get();
      expect(rows, hasLength(1));

      // A new day: the habit is open again, the series survives until midnight.
      setLocalNow(harness, LocalDate(2026, 10, 4));
      var overview = buildHabitsOverview(
        habits: await repository.watchAll().first,
        checks: await repository.watchChecks().first,
        today: LocalDate(2026, 10, 4),
      );
      expect(overview.items.single.checkedToday, isFalse);
      expect(overview.items.single.series.current, 1);
      expect((await status(LocalDate(2026, 10, 4))).applicableCount, 6);

      // Archive on the 4th: it still applies on the 4th, from the 5th it ends.
      final archived = await repository.archive(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(archived.undo, isNull);
      expect(
        (await repository.findById(id))!.archivedFrom,
        LocalDate(2026, 10, 5),
      );
      overview = buildHabitsOverview(
        habits: await repository.watchAll().first,
        checks: await repository.watchChecks().first,
        today: LocalDate(2026, 10, 4),
      );
      expect(overview.items.single.archiveHint, 'Ab morgen archiviert');
      await check(id, LocalDate(2026, 10, 4));
      expect(await xp(), 10);
      expect(
        (await status(LocalDate(2026, 10, 4))).applicableCount,
        6,
        reason: 'applicable through the archive day',
      );
      expect((await status(LocalDate(2026, 10, 4))).fulfilledCount, 1);

      // The 5th: the habit is no longer a goal, history and XP stay.
      setLocalNow(harness, LocalDate(2026, 10, 5));
      overview = buildHabitsOverview(
        habits: await repository.watchAll().first,
        checks: await repository.watchChecks().first,
        today: LocalDate(2026, 10, 5),
      );
      expect(overview.items, isEmpty);
      expect(overview.archived.single.habit.id, id);
      expect((await status(LocalDate(2026, 10, 5))).applicableCount, 5);
      expect(await xp(), 10, reason: 'archiving never takes earned XP away');
      expect(
        (await status(LocalDate(2026, 10, 4))).applicableCount,
        6,
        reason: 'the past day keeps its goals',
      );
      expect((await status(LocalDate(2026, 10, 3))).fulfilledCount, 1);
      await expectLater(
        check(id, LocalDate(2026, 10, 5)),
        throwsA(isA<ValidationFailure>()),
      );
      expect((await detail(id)).ended, isTrue);
    });

    test('the series and checks of an archived habit stay after restart-like re-reads', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 28));
      for (final date in [
        LocalDate(2026, 9, 29),
        LocalDate(2026, 9, 30),
        LocalDate(2026, 10, 1),
      ]) {
        await check(id, date);
      }
      await repository.archive(commandId: harness.ids.newId(), id: id);
      setLocalNow(harness, LocalDate(2026, 10, 10));
      final result = await detail(id);
      expect(result.ended, isTrue);
      expect(result.checkedDaysInHistory, 3);
      expect(result.series.longest, 3);
    });

    test('archived habits are never reactivated: only a new habit with a new id exists', () async {
      final id = await create();
      await repository.archive(commandId: harness.ids.newId(), id: id);
      setLocalNow(harness, LocalDate(2026, 10, 5));
      final replacement = await create('Lesen');
      expect(replacement, isNot(id));
      expect(
        (await repository.findById(id))!.archivedFrom,
        LocalDate(2026, 10, 4),
      );
      expect((await repository.findById(replacement))!.archivedFrom, isNull);
      expect(
        (await repository.findById(replacement))!.startedOn,
        LocalDate(2026, 10, 5),
      );
    });
  });

  group('habit XP (5 per valid check, first five per day)', () {
    test(
      'a check earns 5 XP on its own day, unchecking takes it back',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 25));
        await check(id, today.addDays(-2));
        expect(await awards(), {key(id, today.addDays(-2)): 5});
        await uncheck(id, today.addDays(-2));
        expect(await xp(), 0);
      },
    );

    test('check, uncheck, check never piles up XP', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      for (var i = 0; i < 3; i++) {
        await check(id, today);
        expect(await xp(), 5);
        await uncheck(id, today);
        expect(await xp(), 0);
      }
    });

    test(
      'six habits: only the first five checks of a day earn XP (25)',
      () async {
        final ids = <String>[];
        for (var i = 1; i <= 6; i++) {
          harness.clock.advance(const Duration(minutes: 1));
          ids.add(await create('H$i'));
        }
        for (final id in ids) {
          harness.clock.advance(const Duration(minutes: 1));
          await check(id, today);
        }
        expect(await xp(), 25);
        expect((await awards()).keys, {
          for (final id in ids.take(5)) key(id, today),
        });

        // Removing one of the first five lets the sixth move up.
        harness.clock.advance(const Duration(minutes: 1));
        await uncheck(ids[0], today);
        expect(await xp(), 25);
        expect((await awards()).keys, {
          for (final id in ids.skip(1)) key(id, today),
        });
      },
    );

    test('a replayed command and a repeated tap award once (AT12)', () async {
      final id = await create();
      await repository.setChecked(
        commandId: 'tap',
        habitId: id,
        date: today,
        checked: true,
      );
      await repository.setChecked(
        commandId: 'tap',
        habitId: id,
        date: today,
        checked: true,
      );
      await check(id, today); // new id, already checked
      expect(await xp(), 5);
    });

    test('two simultaneous checks of the same day with different ids check it once', () async {
      final id = await create();
      final results = await Future.wait([check(id, today), check(id, today)]);
      expect(results.where((r) => r.undo != null), hasLength(1));
      expect(
        await harness.database.select(harness.database.habitChecks).get(),
        hasLength(1),
      );
      expect(await xp(), 5);
    });

    test('a retroactive check earns on ITS day, not on today', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      await check(id, LocalDate(2026, 9, 28));
      final rows = await harness.database
          .select(harness.database.xpAwards)
          .get();
      expect(rows.single.localDate, LocalDate(2026, 9, 28));
      expect(rows.single.awardKey, key(id, LocalDate(2026, 9, 28)));
      expect(rows.single.sourceKind, 'habit');
      expect(rows.single.points, 5);
    });

    test(
      'deleting a habit takes the XP of all its days back, undo restores it',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 25));
        for (final date in [
          LocalDate(2026, 9, 26),
          LocalDate(2026, 9, 27),
          today,
        ]) {
          await check(id, date);
        }
        expect(await xp(), 15);
        final deleted = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        expect(await xp(), 0);
        expect(await awards(), isEmpty);
        await deleted.undo!.run(harness.ids.newId());
        expect(await xp(), 15);
        expect((await awards()).keys, {
          key(id, LocalDate(2026, 9, 26)),
          key(id, LocalDate(2026, 9, 27)),
          key(id, today),
        });
      },
    );

    test('the daily limit counts per stored check day (midnight)', () async {
      final ids = <String>[];
      for (var i = 1; i <= 6; i++) {
        harness.clock.advance(const Duration(minutes: 1));
        ids.add(await create('H$i'));
      }
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 21, 55)); // 23:55 Berlin
      for (final id in ids.take(5)) {
        harness.clock.advance(const Duration(seconds: 5));
        await check(id, today);
      }
      expect(await xp(), 25);
      harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 0, 30)); // 00:00:30
      await check(ids.first, LocalDate(2026, 10, 4));
      expect(await xp(), 30, reason: 'a new day, a new limit');
    });
  });

  group('eligibility is frozen per check (AT26)', () {
    test(
      'a check made while gamification is off earns nothing, not even later',
      () async {
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final id = await create();
        await check(id, today);
        expect(await xp(), 0);
        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        // Another command of the day re-runs the projection: still nothing.
        await check(await create('Zwei'), today);
        expect(await xp(), 5, reason: 'only the new habit counts');
        expect((await awards()).keys, isNot(contains(key(id, today))));
      },
    );

    test('uncheck and check again with gamification on gets a fresh, eligible flag', () async {
      await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
      final id = await create();
      await check(id, today);
      expect(await xp(), 0);
      await uncheck(id, today);
      harness.clock.advance(const Duration(minutes: 1));
      await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
      harness.clock.advance(const Duration(minutes: 1));
      await check(id, today);
      final rows = await harness.database
          .select(harness.database.habitChecks)
          .get();
      expect(
        rows,
        hasLength(1),
        reason: 'the soft-deleted row was reactivated',
      );
      expect(rows.single.eligibility, isTrue);
      expect(await xp(), 5);
    });

    test(
      'undo restores the exact flag, not the current gamification state',
      () async {
        // Case 1: checked while OFF, unchecked, switched ON, uncheck undone.
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final off = await create('Aus');
        await check(off, today);
        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: true);
        final uncheckedOff = await uncheck(off, today);
        await uncheckedOff.undo!.run(harness.ids.newId());
        expect(await xp(), 0, reason: 'the restored check is not eligible');

        // Case 2: checked while ON, switched OFF, unchecked, uncheck undone.
        harness.clock.advance(const Duration(minutes: 1));
        final on = await create('An');
        await check(on, today);
        expect(await xp(), 5);
        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        final uncheckedOn = await uncheck(on, today);
        expect(await xp(), 0);
        await uncheckedOn.undo!.run(harness.ids.newId());
        expect(await xp(), 5, reason: 'the original flag is back');
      },
    );

    test(
      'earned XP survives switching gamification off, a correction removes it',
      () async {
        final id = await create();
        await check(id, today);
        harness.clock.advance(const Duration(minutes: 1));
        await setModuleEnabled(harness, ModuleId.gamification, enabled: false);
        await check(await create('Zwei'), today); // re-runs the projection
        expect(await xp(), 5);
        await uncheck(id, today);
        expect(await xp(), 0);
      },
    );
  });

  group('AT23: correcting the past changes ring, XP and streak consistently', () {
    test(
      'backfilling and removing a check updates the day, the XP and the streak',
      () async {
        final id = await createStartedOn(LocalDate(2026, 9, 25));
        for (final date in [
          LocalDate(2026, 9, 29),
          LocalDate(2026, 10, 1),
          LocalDate(2026, 10, 2),
          today,
        ]) {
          await check(id, date);
        }
        expect(await xp(), 20);
        expect(await streak(), (current: 3, longest: 3));
        expect((await status(LocalDate(2026, 9, 30))).isActive, isFalse);

        // Backfill the gap: the days 09-29 .. 10-03 become one run of five.
        final backfill = await check(id, LocalDate(2026, 9, 30));
        expect(await xp(), 25);
        expect((await status(LocalDate(2026, 9, 30))).fulfilledCount, 1);
        expect((await status(LocalDate(2026, 9, 30))).isActive, isTrue);
        expect(await streak(), (current: 5, longest: 5));

        // Undo the backfill: everything goes back.
        await backfill.undo!.run(harness.ids.newId());
        expect(await xp(), 20);
        expect(await streak(), (current: 3, longest: 3));

        // Remove a middle day of the run: current and longest both shrink.
        await uncheck(id, LocalDate(2026, 10, 1));
        expect(await xp(), 15);
        expect((await status(LocalDate(2026, 10, 1))).fulfilledCount, 0);
        expect(await streak(), (current: 2, longest: 2));
      },
    );

    test('removing the check of a past day lowers that day only', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      final other = await createStartedOn(LocalDate(2026, 9, 25), 'Zwei');
      final yesterday = today.addDays(-1);
      await check(id, yesterday);
      await check(other, yesterday);
      await check(id, today);
      expect((await status(yesterday)).fulfilledCount, 2);
      await uncheck(id, yesterday);
      expect((await status(yesterday)).fulfilledCount, 1);
      expect(
        (await status(yesterday)).isActive,
        isTrue,
        reason: 'the other habit remains',
      );
      expect((await status(today)).fulfilledCount, 1);
      expect(await xp(), 10);
    });

    test('a check can only be corrected inside the 30 day window', () async {
      final id = await createStartedOn(LocalDate(2026, 8, 1));
      await check(id, today.addDays(-30));
      expect(await xp(), 5);
      await expectLater(
        check(id, today.addDays(-31)),
        throwsA(isA<ValidationFailure>()),
      );
      expect(await xp(), 5);
    });
  });

  group('AT24 and AT25: day boundaries (habits)', () {
    test(
      'a series and its XP across the spring DST change 2026-03-29',
      () async {
        await harness.dispose();
        await bootHarness(
          profileStart: LocalDate(2026, 3, 1),
          nowIso: '2026-03-30T10:00:00Z',
        );
        final id = await createStartedOn(LocalDate(2026, 3, 1));
        for (final date in [
          LocalDate(2026, 3, 28),
          LocalDate(2026, 3, 29),
          LocalDate(2026, 3, 30),
        ]) {
          await check(id, date);
        }
        expect(
          (await detail(id)).series,
          const HabitSeries(current: 3, longest: 3),
        );
        expect(await xp(), 15);
        expect((await awards()).keys, {
          key(id, LocalDate(2026, 3, 28)),
          key(id, LocalDate(2026, 3, 29)),
          key(id, LocalDate(2026, 3, 30)),
        });
        expect(await streak(), (current: 3, longest: 3));
      },
    );

    test(
      'a series and its XP across the autumn DST change 2026-10-25',
      () async {
        await harness.dispose();
        await bootHarness(
          profileStart: LocalDate(2026, 9, 1),
          nowIso: '2026-10-26T10:00:00Z',
        );
        final id = await createStartedOn(LocalDate(2026, 10, 1));
        for (final date in [
          LocalDate(2026, 10, 24),
          LocalDate(2026, 10, 25),
          LocalDate(2026, 10, 26),
        ]) {
          await check(id, date);
        }
        expect((await detail(id)).series.current, 3);
        expect(await xp(), 15);
        expect(await streak(), (current: 3, longest: 3));
        // The 25-hour day is one calendar day: no second award for it.
        await check(id, LocalDate(2026, 10, 25));
        expect(await xp(), 15);
      },
    );

    test('a series across a month and a year boundary', () async {
      await harness.dispose();
      await bootHarness(
        profileStart: LocalDate(2026, 9, 1),
        nowIso: '2027-01-02T10:00:00Z',
      );
      final id = await createStartedOn(LocalDate(2026, 12, 1));
      for (final date in [
        LocalDate(2026, 12, 30),
        LocalDate(2026, 12, 31),
        LocalDate(2027, 1, 1),
        LocalDate(2027, 1, 2),
      ]) {
        await check(id, date);
      }
      expect(
        (await detail(id)).series,
        const HabitSeries(current: 4, longest: 4),
      );
      expect(await streak(), (current: 4, longest: 4));
      expect(await xp(), 20);
    });

    test('a zone change moves no existing check and no award', () async {
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      await check(id, today);
      harness.clock.setTimeZone('Asia/Tokyo');
      final rows = await harness.database
          .select(harness.database.habitChecks)
          .get();
      expect(rows.single.localDate, today);
      expect(rows.single.timezoneId, 'Europe/Berlin');
      expect(await awards(), {key(id, today): 5});
    });
  });

  group('the ring (habit goals)', () {
    test('every active habit adds a daily goal, checks fulfil it', () async {
      final a = await create('A');
      await create('B');
      expect((await status(today)).applicableCount, 7);
      await check(a, today);
      final result = await status(today);
      expect(result.fulfilledCount, 1);
      expect(
        result.goals.where((g) => g.goalKey.startsWith('habit:')),
        hasLength(2),
      );
    });

    test('a habit with a check makes the day active for the streak', () async {
      final id = await create();
      expect((await status(today)).isActive, isFalse);
      await check(id, today);
      expect((await status(today)).isActive, isTrue);
      expect(await streak(), (current: 1, longest: 1));
    });

    test('a deleted habit leaves the ring of today and of past days', () async {
      final yesterday = today.addDays(-1);
      final id = await createStartedOn(LocalDate(2026, 9, 25));
      await check(id, today);
      expect((await status(today)).applicableCount, 6);
      expect(
        (await status(yesterday)).applicableCount,
        6,
        reason: 'stores the snapshot of yesterday with the habit goal',
      );
      await repository.delete(commandId: harness.ids.newId(), id: id);
      expect((await status(today)).applicableCount, 5);
      expect((await status(yesterday)).applicableCount, 5);
    });
  });

  group('atomicity (AT27): a storage failure rolls back check and XP', () {
    late _FailAfterSync failing;
    late HabitRepository failingRepository;

    setUp(() {
      failing = _FailAfterSync(harness.projections);
      final runner = CommandRunner(
        database: harness.database,
        clock: harness.clock,
        ids: harness.ids,
        projections: failing,
        events: harness.events,
        gamificationEnabled: () =>
            harness.moduleStatus.isEnabled(ModuleId.gamification),
      );
      failingRepository = HabitRepository(
        database: harness.database,
        runner: runner,
      );
    });

    test(
      'nothing is committed; the retry with the SAME id gives exactly 5 XP',
      () async {
        final id = await create();
        failing.failing = true;
        await expectLater(
          failingRepository.setChecked(
            commandId: 'fail',
            habitId: id,
            date: today,
            checked: true,
          ),
          throwsA(isA<StorageFailure>()),
        );
        expect(
          await harness.database.select(harness.database.habitChecks).get(),
          isEmpty,
        );
        expect(await xp(), 0);
        final receipts = await harness.database
            .select(harness.database.commandReceipts)
            .get();
        expect(receipts.where((r) => r.commandId == 'fail'), isEmpty);
        failing.failing = false;
        final outcome = await failingRepository.setChecked(
          commandId: 'fail',
          habitId: id,
          date: today,
          checked: true,
        );
        expect(outcome.replayed, isFalse);
        expect(await xp(), 5);
      },
    );

    test('a failing uncheck keeps the check and its XP', () async {
      final id = await create();
      await check(id, today);
      failing.failing = true;
      await expectLater(
        failingRepository.setChecked(
          commandId: 'fail-un',
          habitId: id,
          date: today,
          checked: false,
        ),
        throwsA(isA<StorageFailure>()),
      );
      expect(await repository.findCheck(id, today), isNotNull);
      expect(await xp(), 5);
    });

    test('a failing delete keeps the habit, its checks and its XP', () async {
      final id = await create();
      await check(id, today);
      failing.failing = true;
      await expectLater(
        failingRepository.delete(commandId: 'fail-del', id: id),
        throwsA(isA<StorageFailure>()),
      );
      expect(await repository.findById(id), isNotNull);
      expect(await xp(), 5);
    });
  });
}
