import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

/// The reminder of a single task through the whole engine (BS-111): real
/// in-memory database, the real task commands (create, edit, complete, delete,
/// undo), the real planner and service, the fake platform, an injected clock.
/// `ReminderService.reconcile` is called by hand after each change; the
/// listener that calls it after every committed change has its own tests
/// (`reminder_auto_reconciler_tasks_test.dart`).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late ReminderHarness h;

  /// 2026-10-03 06:30Z (08:30 Berlin) plus [hours].
  DateTime inHours(int hours) =>
      h.data.clock.nowUtc().add(Duration(hours: hours));

  Future<void> start({
    String nowIso = '2026-10-03T06:30:00Z',
    NotificationPermission permission = NotificationPermission.granted,
    bool wanted = true,
  }) async {
    h = await ReminderHarness.create(nowIso: nowIso, permission: permission);
    if (wanted) {
      await h.setWanted(true);
    }
  }

  tearDown(() => h.dispose());

  group('planning', () {
    test('a reminder is handed to the system at its instant, with a neutral '
        'title and the route of the task (BS-111, AT28, T01)', () async {
      await start();
      final at = inHours(3);
      final id = await h.createTask(
        title: 'Geheime Steuerunterlagen',
        reminderAt: at,
      );

      final status = await h.service.reconcile();

      expect(status.state, ReminderState.active);
      expect(status.scheduledCount, 1);
      expect(status.nextFireAtUtc, at);
      final alarm = h.platform.alarms.values.single;
      expect(alarm.fireAtUtc, at);
      expect(alarm.title, ReminderTexts.taskTitle);
      expect(alarm.payload, '/tasks/$id');
      expect(alarm.body, isNull);
      expect(alarm.timeZoneId, 'Europe/Berlin');
      // The title of the task is user text: it never reaches the system.
      expect(
        '${alarm.title} ${alarm.payload} ${alarm.body}',
        isNot(contains('Steuer')),
      );
      final row = (await h.rows()).single;
      expect(row.semanticKey, 'task:$id');
      expect(row.kind, ReminderKind.task);
      expect(row.route, '/tasks/$id');
      expect(row.sourceRuleId, isNull);
    });

    test('a task without a reminder, and a second run with nothing changed, '
        'plan and call nothing (BS-111)', () async {
      await start();
      await h.createTask();
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);

      await h.createTask(reminderAt: inHours(2));
      await h.service.reconcile();
      h.platform.clearCalls();
      await h.service.reconcile();
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
      expect(await h.rows(), hasLength(1));
    });

    test('a reminder far beyond the seven days is planned at once '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(24 * 21));
      final status = await h.service.reconcile();
      expect(status.scheduledCount, 1);
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(24 * 21));
    });

    test('several tasks give one notification each, soonest first, and the '
        'projection lists them with their kind (BS-111)', () async {
      await start();
      final late = await h.createTask(reminderAt: inHours(30));
      final soon = await h.createTask(reminderAt: inHours(1));
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$soon', 'task:$late']);
      expect((await h.rows()).map((r) => r.kind).toSet(), {ReminderKind.task});
    });
  });

  group('changing the reminder', () {
    test('moving it reschedules the notification under the same id '
        '(BS-111, AT25)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final before = (await h.rows()).single;

      await h.setReminder(id, inHours(5));
      h.platform.clearCalls();
      await h.service.reconcile();

      final after = (await h.rows()).single;
      expect(after.notificationId, before.notificationId);
      expect(after.fireAtUtc, inHours(5));
      expect(h.platform.alarms.keys, [before.notificationId]);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(5));
      // Replaced in place, not cancelled and planned anew.
      expect(h.platform.cancelCalls, isEmpty);
    });

    test('removing it cancels the notification and drops the row '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final planned = (await h.rows()).single.notificationId;

      await h.setReminder(id, null);
      await h.service.reconcile();

      expect(h.platform.alarms, isEmpty);
      expect(h.platform.cancelCalls, [planned]);
      expect(await h.rows(), isEmpty);
    });

    test('setting a reminder on a task that had none plans it '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask();
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);

      await h.setReminder(id, inHours(4));
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(4));
    });

    test('editing something else touches the system not at all '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final task = (await h.tasks.findById(id))!;

      await h.tasks.update(
        commandId: h.data.ids.newId(),
        id: id,
        draft: TaskDraft(
          title: 'Anderer Titel',
          description: task.description,
          priority: task.priority,
          dueDate: task.dueDate,
          tags: task.tags,
          reminderAtUtc: task.reminder?.atUtc,
        ),
        expectedRowVersion: task.rowVersion,
      );
      h.platform.clearCalls();
      await h.service.reconcile();

      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
      expect(await h.rowKeys(), ['task:$id']);
    });

    test('undoing a change of the reminder brings the old time back '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();

      final outcome = await h.setReminder(id, inHours(9));
      await h.service.reconcile();
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(9));

      await h.undo(outcome);
      await h.service.reconcile();
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
      expect(await h.rowKeys(), ['task:$id']);
    });

    test('undoing the removal of a reminder plans it again '
        '(BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final outcome = await h.setReminder(id, null);
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);

      await h.undo(outcome);
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });
  });

  group('completing, deleting, restoring (BS-111, T01)', () {
    test(
      'completing cancels the notification, undoing plans it again',
      () async {
        await start();
        final id = await h.createTask(reminderAt: inHours(3));
        await h.service.reconcile();
        final planned = (await h.rows()).single.notificationId;

        final outcome = await h.completeTask(id);
        await h.service.reconcile();
        expect(h.platform.alarms, isEmpty);
        expect(h.platform.cancelCalls, [planned]);
        expect(await h.rows(), isEmpty);
        // The reminder itself stays on the completed task.
        expect((await h.tasks.findById(id))!.reminder, isNotNull);

        await h.undo(outcome);
        await h.service.reconcile();
        expect(await h.rowKeys(), ['task:$id']);
        expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
      },
    );

    test('reopening a completed task plans its reminder again when it is still '
        'ahead', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.completeTask(id);
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);

      await h.reopenTask(id);
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);
    });

    test('reopening after the reminder has passed plans nothing', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(1));
      await h.completeTask(id);
      h.data.clock.advance(const Duration(hours: 2));
      await h.reopenTask(id);
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);
    });

    test('deleting cancels the notification, undoing plans it again', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final planned = (await h.rows()).single.notificationId;

      final outcome = await h.deleteTask(id);
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);
      expect(h.platform.cancelCalls, [planned]);
      expect(await h.rows(), isEmpty);

      await h.undo(outcome);
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });

    test(
      'undoing the creation removes the notification of the new task',
      () async {
        await start();
        final outcome = await h.tasks.create(
          commandId: h.data.ids.newId(),
          draft: TaskDraft(title: 'Neu', reminderAtUtc: inHours(2)),
        );
        await h.service.reconcile();
        expect(await h.rows(), hasLength(1));

        await h.undo(outcome);
        await h.service.reconcile();
        expect(await h.rows(), isEmpty);
        expect(h.platform.alarms, isEmpty);
      },
    );

    test(
      'completing one task leaves the notification of another alone',
      () async {
        await start();
        final first = await h.createTask(reminderAt: inHours(2));
        final second = await h.createTask(reminderAt: inHours(3));
        await h.service.reconcile();
        final secondId = (await h.rows())
            .singleWhere((r) => r.semanticKey == 'task:$second')
            .notificationId;

        await h.completeTask(first);
        h.platform.clearCalls();
        await h.service.reconcile();

        expect(await h.rowKeys(), ['task:$second']);
        expect(h.platform.alarms.keys, [secondId]);
        expect(h.platform.scheduleCalls, isEmpty);
      },
    );
  });

  group('time passes (BS-111, AT25)', () {
    test('a delivered reminder leaves only its row, the notification stays '
        'in the shade and is never planned again', () async {
      await start();
      await h.createTask(reminderAt: inHours(1));
      await h.service.reconcile();
      expect(h.platform.alarms, hasLength(1));

      h.data.clock.advance(const Duration(hours: 2));
      h.platform.deliverDue(h.data.clock.nowUtc());
      expect(h.platform.delivered, hasLength(1));
      h.platform.clearCalls();
      await h.service.reconcile();

      expect(await h.rows(), isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.shade, hasLength(1));
    });

    test('a reminder that has passed is never handed to the system, also when '
        'it is stored (imported) as it is (BS-111, AT28)', () async {
      await start();
      final now = h.data.clock.nowUtc();
      final past = now.subtract(const Duration(days: 2));
      await h.database
          .into(h.database.tasks)
          .insert(
            TasksCompanion.insert(
              id: h.data.ids.newId(),
              title: 'Abgelaufen',
              reminderAtUtc: Value(past),
              reminderLocalDate: Value(LocalDate(2026, 10, 1)),
              reminderTimezoneId: const Value('Europe/Berlin'),
              createdAtUtc: now,
              updatedAtUtc: now,
            ),
          );
      final status = await h.service.reconcile();
      expect(status.scheduledCount, 0);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(await h.rows(), isEmpty);
    });

    test('the clock changes of Berlin keep the instants exactly: two tasks at '
        '02:30 local on the day the clocks go back (BS-111, AT25)', () async {
      // 2026-10-25: 03:00 CEST falls back to 02:00 CET (01:00Z), so 02:30
      // exists twice: 00:30Z (CEST) and 01:30Z (CET).
      await start(nowIso: '2026-10-24T20:00:00Z');
      final first = await h.createTask(
        reminderAt: DateTime.utc(2026, 10, 25, 0, 30),
      );
      final second = await h.createTask(
        reminderAt: DateTime.utc(2026, 10, 25, 1, 30),
      );
      await h.service.reconcile();

      final byKey = {
        for (final alarm in h.platform.alarms.values) alarm.payload: alarm,
      };
      expect(
        byKey['/tasks/$first']!.fireAtUtc,
        DateTime.utc(2026, 10, 25, 0, 30),
      );
      expect(
        byKey['/tasks/$second']!.fireAtUtc,
        DateTime.utc(2026, 10, 25, 1, 30),
      );

      h.data.clock.setNow(DateTime.utc(2026, 10, 25, 0, 45));
      h.platform.deliverDue(h.data.clock.nowUtc());
      await h.service.reconcile();
      expect(h.platform.delivered.map((r) => r.payload), ['/tasks/$first']);
      expect(await h.rowKeys(), ['task:$second']);
    });

    test('a reminder right after the clocks go forward keeps its instant '
        '(BS-111, AT25)', () async {
      // 2026-03-29: 02:00 CET jumps to 03:00 CEST (01:00Z).
      await start(nowIso: '2026-03-28T20:00:00Z');
      final id = await h.createTask(
        reminderAt: DateTime.utc(2026, 3, 29, 1, 0),
      );
      await h.service.reconcile();
      final alarm = h.platform.alarms.values.single;
      expect(alarm.payload, '/tasks/$id');
      expect(alarm.fireAtUtc, DateTime.utc(2026, 3, 29, 1, 0));
      expect(
        h.data.clock.toLocal(alarm.fireAtUtc).time,
        const LocalTime(3, 0),
        reason: 'the first minute after the gap',
      );
    });

    test('a change of the device zone leaves the instant alone while a habit '
        'moves with the wall clock (BS-111, AT25)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(30));
      await h.addHabit(time: const LocalTime(20, 0));
      await h.service.reconcile();
      final taskAlarm = h.platform.alarms.values.singleWhere(
        (a) => a.payload == '/tasks/$id',
      );
      h.platform.clearCalls();

      h.data.clock.setTimeZone('America/New_York');
      await h.service.reconcile();

      expect(
        h.platform.scheduleCalls.where((c) => c.payload == '/tasks/$id'),
        isEmpty,
        reason: 'the task reminder is the same instant',
      );
      expect(h.platform.alarms[taskAlarm.id]!.fireAtUtc, taskAlarm.fireAtUtc);
      expect(
        h.platform.scheduleCalls.where((c) => c.payload.startsWith('/habits')),
        isNotEmpty,
        reason: 'the habit moved to the new wall clock time',
      );
    });
  });

  group('switches and permission (BS-111, AT28)', () {
    test('without the permission nothing is planned and the status says so; '
        'the reminder is stored; granting it later plans it', () async {
      await start(permission: NotificationPermission.denied);
      final id = await h.createTask(reminderAt: inHours(3));

      final blocked = await h.service.reconcile();
      expect(blocked.state, ReminderState.blocked);
      expect(blocked.scheduledCount, 0);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.alarms, isEmpty);
      expect((await h.tasks.findById(id))!.reminder, isNotNull);

      // The user allowed notifications in the system settings.
      h.platform.permission = NotificationPermission.granted;
      final active = await h.service.reconcile();
      expect(active.state, ReminderState.active);
      expect(await h.rowKeys(), ['task:$id']);
      expect(h.platform.alarms.values.single.fireAtUtc, inHours(3));
    });

    test('revoking the permission cancels the planned notification, and the '
        'task keeps its reminder', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      expect(h.platform.alarms, hasLength(1));

      h.platform.permission = NotificationPermission.denied;
      final status = await h.service.reconcile();
      expect(status.state, ReminderState.blocked);
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);
      expect((await h.tasks.findById(id))!.reminder, isNotNull);
    });

    test('the master switch off keeps everything quiet; on plans it '
        '(BS-111)', () async {
      await start(wanted: false);
      final id = await h.createTask(reminderAt: inHours(3));
      final off = await h.service.reconcile();
      expect(off.state, ReminderState.off);
      expect(h.platform.alarms, isEmpty);

      await h.setWanted(true);
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);

      await h.setWanted(false);
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);
      expect(await h.rows(), isEmpty);
    });

    test('switching the module tasks off removes the reminder, on brings it '
        'back (BS-111)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      expect(await h.rows(), hasLength(1));

      await h.setModule(ModuleId.tasks, enabled: false);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
      expect((await h.tasks.findById(id))!.reminder, isNotNull);

      h.data.clock.advance(const Duration(minutes: 1));
      await h.setModule(ModuleId.tasks, enabled: true);
      await h.service.reconcile();
      expect(await h.rowKeys(), ['task:$id']);
    });

    test('a refused system call is reported as a planning error and the next '
        'run tries again (BS-111)', () async {
      await start();
      await h.createTask(reminderAt: inHours(3));
      h.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      final failed = await h.service.reconcile();
      expect(failed.state, ReminderState.schedulingError);
      expect(await h.rows(), isEmpty, reason: 'no row without an alarm');

      h.platform.scheduleFailure = null;
      final retry = await h.service.reconcile();
      expect(retry.state, ReminderState.active);
      expect(await h.rows(), hasLength(1));
    });
  });

  group('the cap of 40 (BS-111)', () {
    test('41 reminders: the farthest waits, the status reports the limit; a '
        'completed task frees a place for it', () async {
      await start();
      final ids = <String>[];
      for (var i = 1; i <= 41; i++) {
        ids.add(await h.createTask(reminderAt: inHours(i)));
      }
      final status = await h.service.reconcile();
      expect(status.planLimitReached, isTrue);
      expect(status.scheduledCount, 40);
      expect(await h.rowKeys(), isNot(contains('task:${ids.last}')));
      expect(await h.rowKeys(), contains('task:${ids[39]}'));

      await h.completeTask(ids.first);
      final next = await h.service.reconcile();
      expect(next.planLimitReached, isFalse);
      expect(next.scheduledCount, 40);
      expect(await h.rowKeys(), contains('task:${ids.last}'));
    });

    test('a far reminder behind many nearer ones gets its place when the app '
        'runs again later (BS-111)', () async {
      await start();
      await h.setWaterHours({10, 12, 14, 16, 18});
      await h.addHabit(time: const LocalTime(20, 0));
      final id = await h.createTask(reminderAt: inHours(24 * 30));

      final first = await h.service.reconcile();
      expect(first.planLimitReached, isTrue);
      expect(first.scheduledCount, 40);
      expect(await h.rowKeys(), isNot(contains('task:$id')));

      // The app is opened again 25 days later: the reminder is five days away.
      h.data.clock.advance(const Duration(days: 25));
      final later = await h.service.reconcile();
      expect(await h.rowKeys(), contains('task:$id'));
      expect(later.scheduledCount, lessThanOrEqualTo(40));
    });
  });

  group('habit reminders stay as they are (BS-111, regression)', () {
    test('creating, moving, removing, completing and deleting tasks never '
        'touches the notifications of habits and water', () async {
      await start();
      await h.setWaterHours({12});
      final habit = await h.addHabit(time: const LocalTime(20, 0));
      await h.service.reconcile();
      final before = {
        for (final row in await h.rows())
          row.semanticKey: (row.notificationId, row.fireAtUtc),
      };
      expect(
        before.keys.where((k) => k.startsWith('habit:$habit')),
        hasLength(7),
      );
      h.platform.clearCalls();

      final id = await h.createTask(reminderAt: inHours(4));
      await h.service.reconcile();
      final moved = await h.setReminder(id, inHours(6));
      await h.service.reconcile();
      await h.undo(moved);
      await h.service.reconcile();
      await h.setReminder(id, null);
      await h.service.reconcile();
      final done = await h.completeTask(id);
      await h.service.reconcile();
      await h.undo(done);
      await h.service.reconcile();
      final deleted = await h.deleteTask(id);
      await h.service.reconcile();
      await h.undo(deleted);
      await h.service.reconcile();

      final after = {
        for (final row in await h.rows())
          if (!row.semanticKey.startsWith('task:'))
            row.semanticKey: (row.notificationId, row.fireAtUtc),
      };
      expect(after, before);
      expect(
        h.platform.cancelCalls.toSet().intersection({
          for (final entry in before.values) entry.$1,
        }),
        isEmpty,
        reason: 'no habit or water notification was ever cancelled',
      );
      expect(
        h.platform.scheduleCalls.where((c) => !c.payload.startsWith('/tasks/')),
        isEmpty,
        reason: 'and none was handed to the system again',
      );
    });

    test('a habit and a task at the same minute are both planned, the task '
        'first (BS-111)', () async {
      await start();
      // 20:00 Berlin = 18:00Z.
      final habit = await h.addHabit(time: const LocalTime(20, 0));
      final task = await h.createTask(
        reminderAt: DateTime.utc(2026, 10, 3, 18),
      );
      await h.service.reconcile();
      final keys = await h.rowKeys();
      expect(keys.take(2), ['task:$task', 'habit:$habit:2026-10-03']);
    });
  });

  group('a new process (BS-111)', () {
    test('registers the task reminder with the system again, under the same '
        'id (the system drops alarms when the app is force-stopped)', () async {
      await start();
      final id = await h.createTask(reminderAt: inHours(3));
      await h.service.reconcile();
      final planned = (await h.rows()).single.notificationId;

      h.platform.forceStop();
      expect(h.platform.alarms, isEmpty);
      h.platform.clearCalls();

      final status = await h.newProcess().reconcile();
      expect(status.state, ReminderState.active);
      expect(h.platform.alarms.keys, [planned]);
      expect(h.platform.alarms[planned]!.payload, '/tasks/$id');
    });
  });
}
