import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late WeightRepository weights;
  late AppDatabase db;

  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    weights = WeightRepository(
      database: harness.database,
      runner: harness.runner,
    );
    db = harness.database;
  });
  tearDown(() => harness.dispose());

  Future<String> addWeight(DateTime at, {int grams = 71500}) async {
    final outcome = await weights.create(
      commandId: harness.ids.newId(),
      draft: WeightDraft(weightGrams: grams, occurredAtUtc: at),
    );
    return outcome.entityId!;
  }

  Future<List<XpAwardRow>> awards() => db.select(db.xpAwards).get();

  Future<void> insertWater(
    String id,
    int ml,
    int minute, {
    bool eligible = true,
  }) => db
      .into(db.waterEntries)
      .insert(
        WaterEntriesCompanion.insert(
          id: id,
          amountMl: ml,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6, minute),
          localDate: today,
          timezoneId: 'Europe/Berlin',
          gamificationEligible: eligible,
          createdAtUtc: DateTime.utc(2026, 10, 3, 6, minute),
          updatedAtUtc: DateTime.utc(2026, 10, 3, 6, minute),
        ),
      );

  /// Syncs snapshots and XP of [day] exactly like a command would.
  Future<void> sync(LocalDate day) => harness.projections.syncDays({day});

  group('weight command with the real projection (AT10 style, AT23, AT26)', () {
    test(
      'the first measurement of a day earns 10 XP, a second one nothing more',
      () async {
        await addWeight(DateTime.utc(2026, 10, 3, 6));
        expect(await harness.totalXp(), 10);
        final stored = await awards();
        expect(stored.single.awardKey, 'weight:2026-10-03');
        expect(stored.single.sourceKind, 'weight');
        expect(stored.single.points, 10);
        expect(stored.single.localDate, today);
        expect(stored.single.ruleVersion, 1);

        await addWeight(DateTime.utc(2026, 10, 3, 7), grams: 71400);
        expect(await harness.totalXp(), 10, reason: 'once per day');
        expect(await awards(), hasLength(1));
      },
    );

    test('deleting the measurement takes the XP back, undo restores it (AT23, AT10)', () async {
      final id = await addWeight(DateTime.utc(2026, 10, 3, 6));
      expect(await harness.totalXp(), 10);
      final deleted = await weights.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(await harness.totalXp(), 0);
      expect(await awards(), isEmpty);
      await deleted.undo!.run(harness.ids.newId());
      expect(await harness.totalXp(), 10);
    });

    test(
      'moving a measurement to another day moves the award (both days synced)',
      () async {
        final id = await addWeight(DateTime.utc(2026, 10, 3, 6));
        final entry = (await weights.findById(id))!;
        await weights.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: WeightDraft(
            weightGrams: entry.weightGrams,
            occurredAtUtc: DateTime.utc(2026, 10, 1, 6),
          ),
          expectedRowVersion: entry.rowVersion,
        );
        final stored = await awards();
        expect(stored.single.awardKey, 'weight:2026-10-01');
        expect(await harness.totalXp(), 10, reason: 'no double award');
      },
    );

    test('a replayed command never awards twice (AT12)', () async {
      await weights.create(
        commandId: 'once',
        draft: WeightDraft(
          weightGrams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
        ),
      );
      await weights.create(
        commandId: 'once',
        draft: WeightDraft(
          weightGrams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
        ),
      );
      expect(await harness.totalXp(), 10);
    });

    test('created while gamification is off: never awarded, not even after switching it on (AT26)', () async {
      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'off',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
              localDate: today,
              enabled: false,
            ),
          );
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      expect(
        (await weights.watchActive().first).single.gamificationEligible,
        isFalse,
      );
      expect(await harness.totalXp(), 0);

      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'on',
              moduleId: ModuleId.gamification.key,
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 30),
              localDate: today,
              enabled: true,
            ),
          );
      await sync(today);
      expect(await harness.totalXp(), 0, reason: 'no retroactive payout');

      // A NEW activity after reactivation is eligible as normal.
      await addWeight(DateTime.utc(2026, 10, 2, 6), grams: 71000);
      expect(await harness.totalXp(), 10);
    });

    test(
      'already earned XP survives deactivating gamification (AT26)',
      () async {
        await addWeight(DateTime.utc(2026, 10, 3, 6));
        expect(await harness.totalXp(), 10);
        await db
            .into(db.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: 'off',
                moduleId: ModuleId.gamification.key,
                effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
                localDate: today,
                enabled: false,
              ),
            );
        await sync(today);
        expect(
          await harness.totalXp(),
          10,
          reason: 'projection ignores the switch',
        );
        // Correcting the source data still removes the points.
        final id = (await weights.watchActive().first).single.id;
        await weights.delete(commandId: harness.ids.newId(), id: id);
        expect(await harness.totalXp(), 0);
      },
    );
  });

  group('events before the profile start earn nothing', () {
    test('a back-dated measurement before the start day is stored but earns no XP and no snapshot', () async {
      await addWeight(DateTime.utc(2026, 8, 20, 6));
      expect(await weights.watchActive().first, hasLength(1));
      expect(await harness.totalXp(), 0);
      final snapshots = await db.select(db.dailyGoalSnapshots).get();
      expect(
        snapshots.where((s) => s.localDate.isBefore(LocalDate(2026, 9, 1))),
        isEmpty,
      );
    });
  });

  group('XP projector reads every fact table correctly', () {
    test('water: first four entries >= 100 ml earn 5 XP each; the 5th and small ones nothing (AT11)', () async {
      await insertWater('w1', 250, 1);
      await insertWater('w2', 99, 2);
      for (var i = 3; i <= 7; i++) {
        await insertWater('w$i', 250, i);
      }
      await sync(today);
      final water = (await awards())
          .where((a) => a.sourceKind == 'water')
          .toList();
      expect(water, hasLength(4));
      expect(water.fold<int>(0, (sum, a) => sum + a.points), 20);
      expect(
        water.map((a) => a.awardKey),
        isNot(contains('water:w2')),
        reason: '99 ml does not qualify',
      );
      expect(
        water.map((a) => a.awardKey),
        isNot(contains('water:w7')),
        reason: 'fifth qualifying entry',
      );

      // Deleting an earlier entry lets the next one move up; the total stays 20.
      await (db.update(db.waterEntries)..where((w) => w.id.equals('w1'))).write(
        WaterEntriesCompanion(
          deletedAtUtc: Value(DateTime.utc(2026, 10, 3, 9)),
        ),
      );
      await sync(today);
      final after = (await awards())
          .where((a) => a.sourceKind == 'water')
          .toList();
      expect(after, hasLength(4));
      expect(after.map((a) => a.awardKey).toSet(), {
        'water:w3',
        'water:w4',
        'water:w5',
        'water:w6',
      }, reason: 'w6 moves up into the freed place, w7 stays out');
      expect(
        after.fold<int>(0, (sum, a) => sum + a.points),
        20,
        reason: 'never more than 20',
      );
    });

    test('ineligible water earns nothing and does not take a place', () async {
      await insertWater('x1', 250, 1, eligible: false);
      await insertWater('x2', 250, 2);
      await sync(today);
      final water = (await awards())
          .where((a) => a.sourceKind == 'water')
          .toList();
      expect(water.single.awardKey, 'water:x2');
    });

    test(
      'tasks, focus, workouts and habit checks use their own rules and flags',
      () async {
        final base = DateTime.utc(2026, 10, 3, 6);
        // Tasks completed today: 6 eligible -> only the first 5 count (50 XP).
        for (var i = 1; i <= 6; i++) {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: 't$i',
                  title: 'Aufgabe $i',
                  completedAtUtc: Value(base.add(Duration(minutes: i))),
                  completedLocalDate: Value(today),
                  timezoneId: const Value('Europe/Berlin'),
                  completionEligibility: const Value(true),
                  createdAtUtc: base,
                  updatedAtUtc: base,
                ),
              );
        }
        // A task completed on another day does not count today.
        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 't-old',
                title: 'alt',
                completedAtUtc: Value(DateTime.utc(2026, 10, 2, 6)),
                completedLocalDate: Value(LocalDate(2026, 10, 2)),
                timezoneId: const Value('Europe/Berlin'),
                completionEligibility: const Value(true),
                createdAtUtc: base,
                updatedAtUtc: base,
              ),
            );
        // Focus: 299 s earns nothing, 300 s earns 10 XP.
        Future<void> focus(String id, int seconds, {bool eligible = true}) => db
            .into(db.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: id,
                category: 'reading',
                plannedSeconds: 1500,
                accumulatedSeconds: Value(seconds),
                startedAtUtc: base,
                endedAtUtc: Value(base.add(const Duration(hours: 1))),
                completedLocalDate: Value(today),
                timezoneId: 'Europe/Berlin',
                status: 'completed',
                gamificationEligible: Value(eligible),
                createdAtUtc: base,
                updatedAtUtc: base,
              ),
            );
        await focus('f1', 299);
        await focus('f2', 300);
        await focus('f3', 1500, eligible: false);
        // Workout once per day (15 XP) regardless of how many entries.
        for (final id in ['wo1', 'wo2']) {
          await db
              .into(db.workoutEntries)
              .insert(
                WorkoutEntriesCompanion.insert(
                  id: id,
                  trainingCategory: 'cardio',
                  durationMinutes: 30,
                  occurredAtUtc: base.add(
                    Duration(minutes: id == 'wo1' ? 1 : 2),
                  ),
                  localDate: today,
                  timezoneId: 'Europe/Berlin',
                  gamificationEligible: true,
                  createdAtUtc: base,
                  updatedAtUtc: base,
                ),
              );
        }
        // Habit checks: 2 habits, one archived-tomorrow, one soft-deleted habit's check does not count.
        for (final id in ['h1', 'h2', 'h-deleted']) {
          await db
              .into(db.habits)
              .insert(
                HabitsCompanion.insert(
                  id: id,
                  title: id,
                  startedLocalDate: LocalDate(2026, 9, 1),
                  deletedAtUtc: Value(id == 'h-deleted' ? base : null),
                  createdAtUtc: base,
                  updatedAtUtc: base,
                ),
              );
          await db
              .into(db.habitChecks)
              .insert(
                HabitChecksCompanion.insert(
                  id: 'c-$id',
                  habitId: id,
                  localDate: today,
                  checkedAtUtc: base.add(const Duration(minutes: 5)),
                  timezoneId: 'Europe/Berlin',
                  eligibility: true,
                  createdAtUtc: base,
                  updatedAtUtc: base,
                ),
              );
        }
        await sync(today);

        final bySource = <String, List<XpAwardRow>>{};
        for (final award in await awards()) {
          bySource.putIfAbsent(award.sourceKind, () => []).add(award);
        }
        expect(bySource['task']!.length, 5);
        expect(bySource['task']!.fold<int>(0, (s, a) => s + a.points), 50);
        expect(
          bySource['task']!.map((a) => a.awardKey),
          isNot(contains('task:t6')),
        );
        expect(
          bySource['task']!.map((a) => a.awardKey),
          isNot(contains('task:t-old')),
        );
        expect(bySource['focus']!.map((a) => a.awardKey), ['focus:f2']);
        expect(bySource['workout']!.single.points, 15);
        expect(bySource['workout']!.single.awardKey, 'workout:2026-10-03');
        expect(bySource['habit']!.map((a) => a.awardKey).toSet(), {
          'habit:h1:2026-10-03',
          'habit:h2:2026-10-03',
        });
        // Idempotent: syncing again changes nothing.
        final before = await harness.totalXp();
        await sync(today);
        expect(await harness.totalXp(), before);
      },
    );

    test(
      'steps: the award needs the frozen eligibility and threshold',
      () async {
        Future<void> steps(int value, {bool? eligible, int? target}) async {
          await db.delete(db.stepDays).go();
          await db
              .into(db.stepDays)
              .insert(
                StepDaysCompanion.insert(
                  id: 's',
                  localDate: today,
                  steps: value,
                  timezoneId: 'Europe/Berlin',
                  reachedGoalEligible: Value(eligible),
                  xpGoalTargetSteps: Value(target),
                  createdAtUtc: DateTime.utc(2026, 10, 3, 6),
                  updatedAtUtc: DateTime.utc(2026, 10, 3, 6),
                ),
              );
          await sync(today);
        }

        await steps(9000);
        expect(
          await harness.totalXp(),
          0,
          reason: 'no claim before the goal was reached',
        );
        await steps(10000, eligible: true, target: 10000);
        expect(await harness.totalXp(), 10);
        await steps(9500, eligible: true, target: 10000);
        expect(
          await harness.totalXp(),
          0,
          reason: 'corrected below the frozen threshold',
        );
        await steps(12000, eligible: false, target: 10000);
        expect(
          await harness.totalXp(),
          0,
          reason: 'reached while gamification was off',
        );
      },
    );
  });

  group('goal snapshots', () {
    test('the first command of a day creates that day\'s snapshot with the daily goals', () async {
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      final rows = await (db.select(
        db.dailyGoalSnapshots,
      )..where((s) => s.localDate.equalsValue(today))).get();
      expect(rows.map((r) => r.goalKey).toSet(), {
        for (final type in GoalType.dailyTypes) type.key,
      });
      final water = rows.singleWhere((r) => r.goalKey == 'water');
      expect(water.targetInteger, 2500);
      expect(water.applicable, isTrue);
      expect(water.moduleId, 'nutrition');
    });

    test(
      'snapshots are frozen: a later goal version never rewrites a past day',
      () async {
        await addWeight(DateTime.utc(2026, 10, 3, 6));
        await db
            .into(db.goalVersions)
            .insert(
              GoalVersionsCompanion.insert(
                id: 'new-water',
                goalType: 'water',
                targetInteger: const Value(3000),
                enabled: true,
                effectiveFromDate: LocalDate(2026, 10, 4),
                createdAtUtc: DateTime.utc(2026, 10, 3, 7),
              ),
            );
        // Re-sync today and view tomorrow.
        await sync(today);
        harness.clock.advance(const Duration(days: 1));
        final repo = harness.dayStatusRepository();
        final yesterday = (await repo.statusFor(today))!;
        final tomorrow = (await repo.statusFor(LocalDate(2026, 10, 4)))!;
        expect(
          yesterday.goals.singleWhere((g) => g.goalKey == 'water').target,
          2500,
          reason: 'the day keeps its frozen threshold (AT24)',
        );
        expect(
          tomorrow.goals.singleWhere((g) => g.goalKey == 'water').target,
          3000,
        );
      },
    );

    test('a module switched off today masks today immediately; reactivation restores it', () async {
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      Future<bool> waterApplicable() async =>
          (await (db.select(db.dailyGoalSnapshots)..where(
                    (s) =>
                        s.localDate.equalsValue(today) &
                        s.goalKey.equals('water'),
                  ))
                  .getSingle())
              .applicable;
      expect(await waterApplicable(), isTrue);

      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'nut-off',
              moduleId: 'nutrition',
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
              localDate: today,
              enabled: false,
            ),
          );
      await sync(today);
      expect(await waterApplicable(), isFalse);
      final target =
          (await (db.select(db.dailyGoalSnapshots)..where(
                    (s) =>
                        s.localDate.equalsValue(today) &
                        s.goalKey.equals('water'),
                  ))
                  .getSingle())
              .targetInteger;
      expect(target, 2500, reason: 'the frozen original target is kept');

      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'nut-on',
              moduleId: 'nutrition',
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 20),
              localDate: today,
              enabled: true,
            ),
          );
      await sync(today);
      expect(await waterApplicable(), isTrue);
    });

    test('catching up creates every missing day in batches and none for the future', () async {
      final repo = harness.dayStatusRepository();
      final statuses = await repo.statusesBetween(LocalDate(2026, 9, 1), today);
      expect(statuses.length, 33, reason: '2026-09-01 .. 2026-10-03');
      expect(statuses.keys.every((day) => !day.isAfter(today)), isTrue);
      expect(
        await repo.statusFor(today.addDays(1)),
        isNull,
        reason: 'future day',
      );
      expect(
        await repo.statusFor(LocalDate(2026, 8, 31)),
        isNull,
        reason: 'before the profile start',
      );
    });

    test(
      'long catch-up respects the 365 day batches and stays consistent',
      () async {
        harness.clock.setNow(DateTime.utc(2028, 3, 1, 12));
        final repo = harness.dayStatusRepository();
        final statuses = await repo.statusesBetween(
          LocalDate(2026, 9, 1),
          LocalDate(2028, 3, 1),
        );
        // 2026-09-01 .. 2028-03-01 inclusive (2028 is a leap year).
        expect(
          statuses.length,
          LocalDate(2026, 9, 1).daysUntil(LocalDate(2028, 3, 1)) + 1,
        );
        final rows = await db.select(db.dailyGoalSnapshots).get();
        expect(
          rows.length,
          statuses.length * GoalType.dailyTypes.length,
          reason:
              'one item per daily goal type per day (six, "Workout heute" '
              'is stored as off), no habits',
        );
        expect(GoalType.dailyTypes, hasLength(6));
      },
    );
  });

  group('deleted habits', () {
    test('a deleted habit disappears from past day statuses and comes back on undo', () async {
      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              title: 'Lesen',
              startedLocalDate: LocalDate(2026, 9, 1),
              createdAtUtc: DateTime.utc(2026, 9, 1),
              updatedAtUtc: DateTime.utc(2026, 9, 1),
            ),
          );
      final repo = harness.dayStatusRepository();
      final yesterday = LocalDate(2026, 10, 2);
      final before = (await repo.statusFor(yesterday))!;
      expect(before.goals.map((g) => g.goalKey), contains('habit:h1'));
      expect(before.applicableCount, 6);

      await (db.update(db.habits)..where((h) => h.id.equals('h1'))).write(
        HabitsCompanion(deletedAtUtc: Value(DateTime.utc(2026, 10, 3, 9))),
      );
      final deleted = (await repo.statusFor(yesterday))!;
      expect(deleted.goals.map((g) => g.goalKey), isNot(contains('habit:h1')));
      expect(
        deleted.applicableCount,
        5,
        reason: 'a deleted habit never existed for the statistics',
      );

      await (db.update(db.habits)..where((h) => h.id.equals('h1'))).write(
        const HabitsCompanion(deletedAtUtc: Value(null)),
      );
      expect(
        (await repo.statusFor(yesterday))!.applicableCount,
        6,
        reason: 'undo restores it',
      );
    });

    test(
      'a habit without any row (a backup does not carry deleted habits) is not '
      'a goal that nobody can fulfil',
      () async {
        await db
            .into(db.habits)
            .insert(
              HabitsCompanion.insert(
                id: 'h1',
                title: 'Lesen',
                startedLocalDate: LocalDate(2026, 9, 1),
                createdAtUtc: DateTime.utc(2026, 9, 1),
                updatedAtUtc: DateTime.utc(2026, 9, 1),
              ),
            );
        final repo = harness.dayStatusRepository();
        final before = (await repo.statusFor(today))!;
        expect(before.goals.map((g) => g.goalKey), contains('habit:h1'));
        expect(before.applicableCount, 6);

        // The state after export and import of a deleted habit: the snapshot
        // rows are still there, the habit row is not.
        await (db.delete(db.habits)..where((h) => h.id.equals('h1'))).go();
        final after = (await repo.statusFor(today))!;
        expect(after.goals.map((g) => g.goalKey), isNot(contains('habit:h1')));
        expect(after.applicableCount, 5);
        expect(
          (await db.select(db.dailyGoalSnapshots).get()).where(
            (row) => row.goalKey == 'habit:h1',
          ),
          isNotEmpty,
          reason: 'the history rows stay in the database',
        );
      },
    );
  });

  group('day status and streak from real data', () {
    test('no applicable goal means no ring and no active day', () async {
      final empty = await DataHarness.create(realProjection: true);
      addTearDown(empty.dispose);
      await empty.seedOnboarded(
        enabledModules: const {},
        startedOn: LocalDate(2026, 9, 1),
      );
      final status = (await empty.dayStatusRepository().statusFor(today))!;
      expect(status.applicableCount, 0);
      expect(status.ringFraction, isNull);
      expect(status.isActive, isFalse);
      expect(status.isComplete, isFalse);
    });

    test('a weight entry fulfils the weight goal: ring 1 of 5, active day (AT01 style)', () async {
      final repo = harness.dayStatusRepository();
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      final status = (await repo.statusFor(today))!;
      expect(status.applicableCount, 5);
      expect(status.fulfilledCount, 1);
      expect(status.isActive, isTrue);
      expect(status.isComplete, isFalse);
      expect(status.ringFraction, closeTo(0.2, 1e-9));
    });

    test('yesterday active, today still open: the streak survives until midnight (AT22)', () async {
      // Active yesterday (a weight entry on 2026-10-02), nothing today yet.
      await addWeight(DateTime.utc(2026, 10, 2, 6));
      final repo = harness.dayStatusRepository();
      final streak = (await repo.computeStreakSummary())!;
      expect(streak.todayActive, isFalse);
      expect(streak.current, 1, reason: 'yesterday counts, today still open');
      expect(streak.longest, 1);
      expect(streak.activeDays, 1);
      expect(streak.nextMilestone, 3);
    });

    test('correcting the past lowers the streak consistently (AT23)', () async {
      final yesterdayId = await addWeight(DateTime.utc(2026, 10, 2, 6));
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      final repo = harness.dayStatusRepository();
      expect((await repo.computeStreakSummary())!.current, 2);
      expect(await harness.totalXp(), 20);
      await weights.delete(commandId: harness.ids.newId(), id: yesterdayId);
      expect((await repo.computeStreakSummary())!.current, 1);
      expect(await harness.totalXp(), 10);
    });

    test('the streak stream recomputes on changes', () async {
      final repo = harness.dayStatusRepository();
      final values = <int?>[];
      final subscription = repo.watchStreak().listen(
        (s) => values.add(s?.current),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await addWeight(DateTime.utc(2026, 10, 3, 6));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await subscription.cancel();
      expect(values.first, 0);
      expect(values.last, 1);
    });
  });
}
