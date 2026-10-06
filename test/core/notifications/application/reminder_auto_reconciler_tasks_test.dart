import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_auto_reconciler.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

/// The trigger that reconciles after every committed change now listens to the
/// tasks too (BS-111): the real task commands (create, edit, complete, delete,
/// undo) reach the system without anybody calling `reconcile` by hand.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late ReminderHarness h;
  late ReminderAutoReconciler trigger;

  setUp(() async {
    h = await ReminderHarness.create();
    await h.setWanted(true);
    trigger = ReminderAutoReconciler(database: h.database, service: h.service)
      ..start(reconcileNow: false);
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

  DateTime inHours(int hours) =>
      h.data.clock.nowUtc().add(Duration(hours: hours));

  group('a task reminder reaches the system by itself (BS-111)', () {
    test('creating a task with a reminder plans it, creating one without '
        'changes nothing', () async {
      await h.createTask();
      await settle();
      expect(await h.rows(), isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);

      final id = await h.createTask(reminderAt: inHours(3));
      await settle();
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });

    test('moving and removing the reminder, with undo', () async {
      final id = await h.createTask(reminderAt: inHours(3));
      await settle();
      final planned = (await h.rows()).single.notificationId;

      final moved = await h.setReminder(id, inHours(7));
      await settle();
      expect((await h.rows()).single.notificationId, planned);
      expect(h.platform.alarms[planned]!.fireAtUtc, inHours(7));

      await h.undo(moved);
      await settle();
      expect(h.platform.alarms[planned]!.fireAtUtc, inHours(3));

      final removed = await h.setReminder(id, null);
      await settle();
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);

      await h.undo(removed);
      await settle();
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });

    test('completing, reopening, deleting and restoring (T01)', () async {
      final id = await h.createTask(reminderAt: inHours(3));
      await settle();
      expect(await h.rows(), hasLength(1));

      final completed = await h.completeTask(id);
      await settle();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);

      await h.undo(completed);
      await settle();
      expect(await h.rows(), hasLength(1));

      final deleted = await h.deleteTask(id);
      await settle();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);

      await h.undo(deleted);
      await settle();
      expect(await h.rows(), hasLength(1));

      await h.completeTask(id);
      await settle();
      await h.reopenTask(id);
      await settle();
      expect(await h.rows(), hasLength(1));
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });

    test('a write to the task table that changes nothing for the plan makes '
        'the engine read and then call nothing', () async {
      await h.createTask(reminderAt: inHours(3));
      await settle();
      h.platform.clearCalls();

      final other = await h.createTask(title: 'Ohne Erinnerung');
      await settle();
      await h.completeTask(other);
      await settle();

      expect(h.platform.pendingIdsCalls, greaterThan(0), reason: 'it ran');
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
      expect(await h.rows(), hasLength(1));
    });

    test('switching the module tasks off and on again', () async {
      final id = await h.createTask(reminderAt: inHours(3));
      await settle();
      await h.setModule(ModuleId.tasks, enabled: false);
      await settle();
      expect(await h.rows(), isEmpty);

      h.data.clock.advance(const Duration(minutes: 1));
      await h.setModule(ModuleId.tasks, enabled: true);
      await settle();
      expect(await h.rowKeys(), ['task:$id']);
    });
  });

  group('habits are not affected (BS-111, regression)', () {
    test('a habit keeps its notifications while tasks come and go', () async {
      final habit = await h.addHabit(time: const LocalTime(20, 0));
      await settle();
      final before = [
        for (final row in await h.rows()) (row.notificationId, row.fireAtUtc),
      ];
      expect(before, hasLength(7));

      final id = await h.createTask(reminderAt: inHours(3));
      await settle();
      await h.completeTask(id);
      await settle();
      await h.deleteTask(id);
      await settle();

      final after = [
        for (final row in await h.rows())
          if (row.kind == ReminderKind.habit)
            (row.notificationId, row.fireAtUtc),
      ];
      expect(after, before);
      expect(
        (await h.rows()).every((r) => r.semanticKey.startsWith('habit:$habit')),
        isTrue,
      );
    });
  });
}
