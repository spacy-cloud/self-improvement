import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_auto_reconciler.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/db_fixtures.dart';
import '../support/reminder_harness.dart';

/// The trigger that reconciles after every committed change that influences
/// the plan. Each run reads the pending list once, so `pendingIdsCalls` counts
/// the runs.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late ReminderHarness h;
  late ReminderAutoReconciler trigger;

  setUp(() async {
    h = await ReminderHarness.create();
    trigger = ReminderAutoReconciler(database: h.database, service: h.service);
  });
  tearDown(() async {
    await trigger.dispose();
    await h.dispose();
  });

  /// Lets the database notification reach the trigger and the runs finish.
  Future<void> settle() async {
    for (var round = 0; round < 3; round++) {
      await pumpEventQueue();
      await h.service.whenIdle();
    }
  }

  group('start', () {
    test('runs once right away, which is the app start trigger', () async {
      trigger.start();
      await settle();
      expect(h.platform.pendingIdsCalls, 1);
    });

    test('can start without a first run', () async {
      trigger.start(reconcileNow: false);
      await settle();
      expect(h.platform.pendingIdsCalls, 0);
    });

    test('starting twice listens once', () async {
      trigger.start(reconcileNow: false);
      trigger.start(reconcileNow: false);
      await h.setWanted(true);
      await settle();
      expect(h.platform.pendingIdsCalls, 1);
    });

    test('after dispose nothing reacts', () async {
      trigger.start(reconcileNow: false);
      await trigger.dispose();
      await h.setWanted(true);
      await settle();
      expect(h.platform.pendingIdsCalls, 0);
    });
  });

  group('changes that reconcile', () {
    setUp(() async {
      trigger.start(reconcileNow: false);
    });

    test('switching reminders on schedules the water slots', () async {
      await h.setWaterHours({10, 12});
      await settle();
      expect(await h.rows(), isEmpty, reason: 'still off');

      await h.setWanted(true);
      await settle();
      expect(await h.rows(), hasLength(14));
    });

    test('changing a water slot', () async {
      await h.setWanted(true);
      await h.setWaterHours({10});
      await settle();
      expect(await h.rows(), hasLength(7));

      await h.setWaterHours({10, 14});
      await settle();
      expect(await h.rows(), hasLength(14));
    });

    test('a new habit with a reminder', () async {
      await h.setWanted(true);
      await settle();
      await h.addHabit(time: const LocalTime(18, 0));
      await settle();
      expect(await h.rows(), hasLength(7));
    });

    test('archiving and deleting a habit', () async {
      await h.setWanted(true);
      final habit = await h.addHabit(time: const LocalTime(18, 0));
      await settle();
      expect(await h.rows(), hasLength(7));

      await h.updateHabit(habit, archivedFrom: Value(LocalDate(2026, 10, 4)));
      await settle();
      expect(await h.rows(), hasLength(1));

      await h.updateHabit(habit, deletedAt: Value(h.data.clock.nowUtc()));
      await settle();
      expect(await h.rows(), isEmpty);
    });

    test('switching a module off', () async {
      await h.setWanted(true);
      await h.setWaterHours({10});
      await settle();
      expect(await h.rows(), hasLength(7));

      await h.setModule(ModuleId.nutrition, enabled: false);
      await settle();
      expect(await h.rows(), isEmpty);
    });

    test('the life of a focus session', () async {
      await h.setWanted(true);
      await settle();
      final session = await h.addFocus(
        planned: 1800,
        segmentStart: h.data.clock.nowUtc(),
      );
      await settle();
      expect((await h.rows()).single.kind, ReminderKind.focusEnd);

      h.data.clock.advance(const Duration(minutes: 10));
      await h.pauseFocus(session, accumulated: 600);
      await settle();
      expect(await h.rows(), isEmpty);

      h.data.clock.advance(const Duration(minutes: 2));
      await h.resumeFocus(session);
      await settle();
      expect(
        (await h.rows()).single.fireAtUtc,
        DateTime.utc(2026, 10, 3, 7, 2),
      );

      await h.closeFocus(session, completed: true);
      await settle();
      expect(await h.rows(), isEmpty);
    });

    test('a water entry re-evaluates the goal fact', () async {
      await h.setWanted(true);
      await h.setWaterHours({10, 12});
      await settle();
      expect(await h.rows(), hasLength(14));

      h.goal.reached = true;
      await h.database.into(h.database.waterEntries).insert(waterRow());
      await settle();
      expect(
        (await h.rowKeys()).where((k) => k.startsWith('water:2026-10-03')),
        isEmpty,
      );
      expect(await h.rows(), hasLength(12));
    });

    test('a goal change re-evaluates the goal fact', () async {
      await h.setWanted(true);
      await h.setWaterHours({10, 12});
      await settle();
      h.goal.reached = true;
      await h.database
          .into(h.database.goalVersions)
          .insert(
            GoalVersionsCompanion.insert(
              id: 'g1',
              goalType: 'water',
              enabled: true,
              targetInteger: const Value(500),
              effectiveFromDate: LocalDate(2026, 10, 3),
              createdAtUtc: h.data.clock.nowUtc(),
            ),
          );
      await settle();
      expect(await h.rows(), hasLength(12));
    });

    test('a day snapshot re-evaluates the goal fact', () async {
      await h.setWanted(true);
      await h.setWaterHours({10, 12});
      await settle();
      h.goal.reached = true;
      await h.database
          .into(h.database.dailyGoalSnapshots)
          .insert(
            DailyGoalSnapshotsCompanion.insert(
              id: 's1',
              localDate: LocalDate(2026, 10, 3),
              goalKey: 'water',
              moduleId: 'nutrition',
              applicable: true,
            ),
          );
      await settle();
      expect(await h.rows(), hasLength(12));
    });

    test('a data import that replaces the tables', () async {
      await h.setWanted(true);
      await h.setWaterHours({10});
      await settle();
      expect(await h.rows(), hasLength(7));

      // An import (or reset) wipes the settings and rules in one transaction.
      await h.database.transaction(() async {
        await h.database.delete(h.database.reminderRules).go();
        await (h.database.update(h.database.appSettings)).write(
          const AppSettingsCompanion(notificationsEnabled: Value(false)),
        );
      });
      await settle();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });
  });

  group('changes that do not reconcile', () {
    test('unrelated tables are ignored', () async {
      trigger.start(reconcileNow: false);
      await h.database.into(h.database.weightEntries).insert(weightRow());
      await h.database.into(h.database.mealEntries).insert(mealRow());
      await settle();
      expect(h.platform.pendingIdsCalls, 0);
    });

    test('the projection it writes does not trigger it again', () async {
      trigger.start(reconcileNow: false);
      await h.setWanted(true);
      await h.setWaterHours({10, 12});
      await settle();
      final runs = h.platform.pendingIdsCalls;
      expect(await h.rows(), hasLength(14));
      await settle();
      await settle();
      expect(h.platform.pendingIdsCalls, runs, reason: 'no feedback loop');
    });
  });

  group('bursts', () {
    test('many changes in a row end in one consistent state', () async {
      trigger.start(reconcileNow: false);
      await h.setWanted(true);
      await settle();
      final before = h.platform.pendingIdsCalls;
      for (var n = 0; n < 8; n++) {
        await h.addHabit(time: LocalTime(9 + n % 3, 0));
      }
      await settle();
      expect(
        await h.rows(),
        hasLength(40),
        reason: '8 habits * 7 days, capped',
      );
      // Far fewer runs than changes: the service coalesced them.
      expect(h.platform.pendingIdsCalls - before, lessThanOrEqualTo(8));
      expect(h.platform.alarms, hasLength(40));
    });
  });
}
