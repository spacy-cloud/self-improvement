import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_route_resolver.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

/// Reconcile against a real in-memory database and the fake operating system.
///
/// "Now" is 2026-10-03 06:30Z = 08:30 in Berlin (summer time).
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness h;

  setUp(() async {
    h = await ReminderHarness.create();
  });
  tearDown(() => h.dispose());

  Map<String, int> idsByKey(List<ScheduledReminder> rows) => {
    for (final r in rows) r.semanticKey: r.notificationId,
  };

  List<ScheduledReminder> keyed(List<ScheduledReminder> rows, String prefix) =>
      rows.where((r) => r.semanticKey.startsWith(prefix)).toList();

  /// Switches reminders on with water slots 10 and 12 (14 notifications).
  Future<void> waterOnly() async {
    await h.setWanted(true);
    await h.setWaterHours({10, 12});
  }

  group('first run', () {
    test('reminders are off by default: nothing is scheduled', () async {
      await h.setWaterHours({10, 12});
      final status = await h.service.reconcile();
      expect(status.state, ReminderState.off);
      expect(status.wanted, isFalse);
      expect(status.scheduledCount, 0);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(await h.rows(), isEmpty);
    });

    test('schedules every wanted notification and records each one', () async {
      await waterOnly();
      final status = await h.service.reconcile();

      expect(status.state, ReminderState.active);
      expect(status.wanted, isTrue);
      expect(status.permission, NotificationPermission.granted);
      expect(status.scheduledCount, 14);
      expect(status.lastError, isNull);
      expect(status.failedCount, 0);
      expect(status.planLimitReached, isFalse);
      expect(status.nextFireAtUtc, DateTime.utc(2026, 10, 3, 8));

      final rows = await h.rows();
      expect(rows, hasLength(14));
      expect(h.platform.scheduleCalls, hasLength(14));
      expect(h.platform.alarms.keys.toSet(), await h.rowIds());
      for (final row in rows) {
        final alarm = h.platform.alarms[row.notificationId]!;
        expect(alarm.fireAtUtc, row.fireAtUtc);
        expect(alarm.payload, row.route);
        expect(alarm.title, 'Zeit für ein Glas Wasser');
        expect(alarm.timeZoneId, 'Europe/Berlin');
      }
    });

    test('the integer ids are positive, unique counters', () async {
      await waterOnly();
      await h.service.reconcile();
      final ids = (await h.rows()).map((r) => r.notificationId).toList();
      expect(ids.every((id) => id > 0), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id <= 0x7FFFFFFF), isTrue);
    });

    test('the projection stores key, time, route and source rule', () async {
      await waterOnly();
      await h.service.reconcile();
      final first = (await h.rows()).first;
      expect(first.semanticKey, 'water:2026-10-03:10:00');
      expect(first.fireAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(first.route, '/water');
      expect(first.sourceRuleId, isNotNull);
      expect(first.kind, ReminderKind.water);
    });

    test('every payload is a known route', () async {
      await waterOnly();
      await h.addHabit();
      await h.addFocus(segmentStart: h.data.clock.nowUtc());
      await h.service.reconcile();
      expect(h.platform.scheduleCalls, isNotEmpty);
      for (final call in h.platform.scheduleCalls) {
        expect(
          NotificationRouteResolver.parse(call.payload),
          isNotNull,
          reason: call.payload,
        );
        expect(call.body, isNull);
        expect(call.title, isNot(contains('Lesen')));
      }
    });

    test('notifications are requested soonest first', () async {
      await waterOnly();
      await h.service.reconcile();
      final times = h.platform.scheduleCalls.map((c) => c.fireAtUtc).toList();
      expect(times, [...times]..sort());
    });
  });

  group('idempotence', () {
    test('a second run with unchanged facts does nothing', () async {
      await waterOnly();
      final first = await h.service.reconcile();
      final rowsBefore = await h.rows();
      h.platform.clearCalls();

      final second = await h.service.reconcile();

      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
      expect(h.platform.cancelAllPendingCalls, 0);
      expect(await h.rows(), rowsBefore);
      expect(second, first);
    });

    test('many runs in a row stay quiet', () async {
      await waterOnly();
      await h.addHabit();
      await h.service.reconcile();
      h.platform.clearCalls();
      for (var n = 0; n < 5; n++) {
        await h.service.reconcile();
      }
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.cancelCalls, isEmpty);
    });

    test('nothing wanted and nothing pending does not even cancel', () async {
      await h.service.reconcile();
      await h.service.reconcile();
      expect(h.platform.cancelAllPendingCalls, 0);
      expect(h.platform.cancelCalls, isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);
    });

    test('a run never writes business data', () async {
      await waterOnly();
      final receipts = await h.receiptCount();
      await h.service.reconcile();
      await h.service.reconcile();
      expect(await h.receiptCount(), receipts);
    });
  });

  group('changes reschedule under the same id', () {
    test('a new habit time moves its notifications, ids stay', () async {
      await h.setWanted(true);
      final habit = await h.addHabit(time: const LocalTime(18, 0));
      await h.service.reconcile();
      final before = idsByKey(await h.rows());
      expect(before, hasLength(7));

      await h.updateHabit(habit, time: const Value(LocalTime(19, 0)));
      h.platform.clearCalls();
      await h.service.reconcile();

      final after = await h.rows();
      expect(idsByKey(after), before, reason: 'same keys, same ids');
      expect(h.platform.scheduleCalls, hasLength(7));
      expect(
        h.platform.scheduleCalls.map((c) => c.id).toSet(),
        before.values.toSet(),
      );
      expect(h.platform.cancelCalls, isEmpty);
      expect(h.platform.alarms, hasLength(7));
      final today = after.firstWhere(
        (r) => r.semanticKey.endsWith('2026-10-03'),
      );
      expect(
        today.fireAtUtc,
        DateTime.utc(2026, 10, 3, 17),
        reason: '19:00 CEST',
      );
      expect(
        h.platform.alarms[today.notificationId]!.fireAtUtc,
        today.fireAtUtc,
      );
    });

    test('a changed time zone plans every reminder again in the new zone', () async {
      await waterOnly();
      await h.service.reconcile();
      final before = await h.rows();
      final idsBefore = idsByKey(before);
      h.platform.clearCalls();

      h.data.clock.setTimeZone('America/New_York');
      final status = await h.service.reconcile();

      // 08:30 Berlin is 02:30 in New York: both slots of today are still ahead,
      // so the keys of the first days are the same, at other instants.
      final after = await h.rows();
      final idsAfter = idsByKey(after);
      expect(
        idsAfter['water:2026-10-03:10:00'],
        idsBefore['water:2026-10-03:10:00'],
      );
      final today10 = after.firstWhere(
        (r) => r.semanticKey == 'water:2026-10-03:10:00',
      );
      expect(
        today10.fireAtUtc,
        DateTime.utc(2026, 10, 3, 14),
        reason: '10:00 EDT',
      );
      expect(h.platform.scheduleCalls, isNotEmpty);
      expect(
        h.platform.scheduleCalls.every(
          (c) => c.timeZoneId == 'America/New_York',
        ),
        isTrue,
      );
      expect(
        h.platform.alarms[today10.notificationId]!.fireAtUtc,
        today10.fireAtUtc,
      );
      expect(status.state, ReminderState.active);
      expect(status.scheduledCount, 14);
      expect(h.platform.cancelCalls, isEmpty);
    });

    test(
      'a changed zone that moves the horizon cancels what fell out',
      () async {
        await h.setWanted(true);
        await h.addHabit(time: const LocalTime(20, 0));
        h.data.clock.setNow(DateTime.utc(2026, 10, 3, 23, 30));
        await h.service.reconcile();
        String dayOf(String key) => key.split(':').last;
        // Berlin: it is the 4th already, the horizon is 2026-10-04 to 10-10.
        var rows = await h.rows();
        expect(dayOf(rows.first.semanticKey), '2026-10-04');
        expect(dayOf(rows.last.semanticKey), '2026-10-10');
        final fallingOut = rows.last.notificationId;
        h.platform.clearCalls();

        h.data.clock.setTimeZone('America/New_York');
        await h.service.reconcile();

        // New York: still the 3rd, 19:30. 20:00 of the 3rd is ahead and the
        // 10th is out of the horizon.
        expect(h.platform.cancelCalls, [fallingOut]);
        rows = await h.rows();
        expect(dayOf(rows.first.semanticKey), '2026-10-03');
        expect(rows.first.fireAtUtc, DateTime.utc(2026, 10, 4));
        expect(dayOf(rows.last.semanticKey), '2026-10-09');
        expect(rows, hasLength(7));
        expect(h.platform.alarms, hasLength(7));
      },
    );

    test('a daylight saving change keeps the wall clock time (AT25)', () async {
      h.data.clock.setNow(DateTime.utc(2026, 3, 28, 8));
      await h.setWanted(true);
      await h.setWaterHours({10});
      await h.service.reconcile();
      final rows = await h.rows();
      final byKey = {for (final r in rows) r.semanticKey: r.fireAtUtc};
      expect(byKey['water:2026-03-28:10:00'], DateTime.utc(2026, 3, 28, 9));
      expect(byKey['water:2026-03-29:10:00'], DateTime.utc(2026, 3, 29, 8));
      expect(byKey['water:2026-03-30:10:00'], DateTime.utc(2026, 3, 30, 8));
      expect(
        h.platform.alarms.values.map((r) => r.fireAtUtc).toSet(),
        byKey.values.toSet(),
      );
    });
  });

  group('cancel rules', () {
    test(
      'a water slot switched off is cancelled and its rows deleted',
      () async {
        await waterOnly();
        await h.service.reconcile();
        final rows = await h.rows();
        final twelve = keyed(
          rows,
          'water:',
        ).where((r) => r.semanticKey.endsWith(':12:00'));
        expect(twelve, hasLength(7));
        h.platform.clearCalls();

        await h.setWaterHours({10});
        final status = await h.service.reconcile();

        expect(
          h.platform.cancelCalls.toSet(),
          twelve.map((r) => r.notificationId).toSet(),
        );
        expect(h.platform.scheduleCalls, isEmpty);
        final after = await h.rows();
        expect(after, hasLength(7));
        expect(after.every((r) => r.semanticKey.endsWith(':10:00')), isTrue);
        expect(h.platform.alarms, hasLength(7));
        expect(status.scheduledCount, 7);
      },
    );

    test('a slot switched on again gets new ids, never the old ones', () async {
      await waterOnly();
      await h.service.reconcile();
      final firstTwelve = {
        for (final r in await h.rows())
          if (r.semanticKey.endsWith(':12:00')) r.notificationId,
      };
      await h.setWaterHours({10});
      await h.service.reconcile();
      await h.setWaterHours({10, 12});
      await h.service.reconcile();

      final secondTwelve = {
        for (final r in await h.rows())
          if (r.semanticKey.endsWith(':12:00')) r.notificationId,
      };
      expect(secondTwelve, hasLength(7));
      expect(secondTwelve.intersection(firstTwelve), isEmpty);
      final highestOld = firstTwelve.reduce((a, b) => a > b ? a : b);
      expect(secondTwelve.every((id) => id > highestOld), isTrue);
    });

    test(
      'an id never belongs to two different keys over the whole history',
      () async {
        final owner = <int, String>{};
        Future<void> run() async {
          await h.service.reconcile();
          for (final r in await h.rows()) {
            final known = owner[r.notificationId];
            expect(
              known == null || known == r.semanticKey,
              isTrue,
              reason: 'id ${r.notificationId} was $known, now ${r.semanticKey}',
            );
            owner[r.notificationId] = r.semanticKey;
          }
        }

        await h.setWanted(true);
        await h.setWaterHours({10, 12});
        await run();
        await h.setWaterHours({12});
        await run();
        final habit = await h.addHabit(time: const LocalTime(18, 0));
        await run();
        await h.updateHabit(habit, deletedAt: Value(h.data.clock.nowUtc()));
        await run();
        await h.setWaterHours({10, 12, 14});
        await run();
        h.data.clock.advance(const Duration(days: 1));
        await run();
        await h.setWanted(false);
        await run();
        await h.setWanted(true);
        await run();
        expect(owner.keys.every((id) => id > 0), isTrue);
      },
    );

    test(
      'master switch off cancels everything pending and clears the rows',
      () async {
        await waterOnly();
        await h.addHabit();
        await h.service.reconcile();
        expect(h.platform.alarms, hasLength(21));

        await h.setWanted(false);
        final status = await h.service.reconcile();

        expect(h.platform.cancelAllPendingCalls, 1);
        expect(h.platform.alarms, isEmpty);
        expect(await h.rows(), isEmpty);
        expect(status.state, ReminderState.off);
        expect(status.scheduledCount, 0);
      },
    );

    test(
      'permission missing: nothing scheduled, everything pending cancelled',
      () async {
        await waterOnly();
        await h.service.reconcile();
        expect(h.platform.alarms, hasLength(14));

        h.platform.permission = NotificationPermission.denied;
        final status = await h.service.reconcile();

        expect(h.platform.alarms, isEmpty);
        expect(await h.rows(), isEmpty);
        expect(status.state, ReminderState.blocked);
        expect(status.permission, NotificationPermission.denied);
        expect(status.wanted, isTrue);
      },
    );

    test('module nutrition off deletes the water notifications only', () async {
      await waterOnly();
      await h.addHabit();
      await h.service.reconcile();

      await h.setModule(ModuleId.nutrition, enabled: false);
      await h.service.reconcile();

      final rows = await h.rows();
      expect(rows.every((r) => r.kind == ReminderKind.habit), isTrue);
      expect(rows, hasLength(7));
      expect(h.platform.alarms, hasLength(7));
    });

    test('module tasks off deletes the habit notifications only', () async {
      await waterOnly();
      await h.addHabit();
      await h.service.reconcile();

      await h.setModule(ModuleId.tasks, enabled: false);
      await h.service.reconcile();

      final rows = await h.rows();
      expect(rows.every((r) => r.kind == ReminderKind.water), isTrue);
      expect(rows, hasLength(14));
    });

    test('switching a module back on plans its reminders again', () async {
      await waterOnly();
      await h.service.reconcile();
      await h.setModule(ModuleId.nutrition, enabled: false);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);

      h.data.clock.advance(const Duration(seconds: 1));
      await h.setModule(ModuleId.nutrition, enabled: true);
      await h.service.reconcile();
      expect(await h.rows(), hasLength(14));
    });
  });

  group('water goal reached today', () {
    test('cancels the remaining water of today and keeps tomorrow', () async {
      await waterOnly();
      await h.service.reconcile();
      final todays = keyed(await h.rows(), 'water:2026-10-03');
      expect(todays, hasLength(2));
      h.platform.clearCalls();

      h.goal.reached = true;
      final status = await h.service.reconcile();

      expect(
        h.platform.cancelCalls.toSet(),
        todays.map((r) => r.notificationId).toSet(),
      );
      final rows = await h.rows();
      expect(keyed(rows, 'water:2026-10-03'), isEmpty);
      expect(keyed(rows, 'water:2026-10-04'), hasLength(2));
      expect(rows, hasLength(12));
      expect(status.scheduledCount, 12);
    });

    test('does not cancel habit reminders of today', () async {
      await waterOnly();
      await h.addHabit(time: const LocalTime(20, 0));
      await h.service.reconcile();
      h.goal.reached = true;
      await h.service.reconcile();
      expect(
        (await h.rows()).any(
          (r) =>
              r.semanticKey.startsWith('habit:') &&
              r.semanticKey.endsWith('2026-10-03'),
        ),
        isTrue,
      );
    });

    test('plans today again when the goal is no longer reached', () async {
      await waterOnly();
      h.goal.reached = true;
      await h.service.reconcile();
      expect(keyed(await h.rows(), 'water:2026-10-03'), isEmpty);

      h.goal.reached = false;
      await h.service.reconcile();
      expect(keyed(await h.rows(), 'water:2026-10-03'), hasLength(2));
    });

    test(
      'is a fact of today only: the next day plans normally again',
      () async {
        await waterOnly();
        h.goal.reached = true;
        await h.service.reconcile();
        h.data.clock.advance(const Duration(days: 1));
        h.goal.reached = false;
        await h.service.reconcile();
        expect(keyed(await h.rows(), 'water:2026-10-04'), hasLength(2));
      },
    );
  });

  group('time passes', () {
    test('a delivered notification is forgotten, not cancelled', () async {
      await waterOnly();
      await h.service.reconcile();
      final tenToday = (await h.rows()).firstWhere(
        (r) => r.semanticKey == 'water:2026-10-03:10:00',
      );

      // 10:05 local. The system delivered the 10:00 reminder.
      h.data.clock.setNow(DateTime.utc(2026, 10, 3, 8, 5));
      h.platform.deliverDue(h.data.clock.nowUtc());
      h.platform.clearCalls();
      await h.service.reconcile();

      expect(
        h.platform.cancelCalls,
        isNot(contains(tenToday.notificationId)),
        reason:
            'a cancel would remove the delivered notification from the shade',
      );
      expect(h.platform.cancelCalls, isEmpty);
      expect(h.platform.shade.map((r) => r.id), [
        tenToday.notificationId,
      ], reason: 'the delivered reminder is still visible');
      final keys = await h.rowKeys();
      expect(keys, isNot(contains('water:2026-10-03:10:00')));
      expect(keys, contains('water:2026-10-03:12:00'));
      expect(h.platform.scheduleCalls, isEmpty);
    });

    test('a due but still pending notification is cancelled', () async {
      await waterOnly();
      await h.service.reconcile();
      final tenToday = (await h.rows()).firstWhere(
        (r) => r.semanticKey == 'water:2026-10-03:10:00',
      );

      // The system delayed it: it is 10:05 and it has not been shown.
      h.data.clock.setNow(DateTime.utc(2026, 10, 3, 8, 5));
      h.platform.clearCalls();
      await h.service.reconcile();

      expect(h.platform.cancelCalls, [tenToday.notificationId]);
      expect(await h.rowKeys(), isNot(contains('water:2026-10-03:10:00')));
      expect(h.platform.alarms, isNot(contains(tenToday.notificationId)));
    });

    test('a new day extends the horizon by one day', () async {
      await h.setWanted(true);
      await h.setWaterHours({10});
      await h.service.reconcile();
      expect((await h.rowKeys()).last, 'water:2026-10-09:10:00');

      h.data.clock.advance(const Duration(days: 1));
      await h.service.reconcile();
      final keys = await h.rowKeys();
      expect(keys.last, 'water:2026-10-10:10:00');
      expect(keys.first, 'water:2026-10-04:10:00');
      expect(keys, hasLength(7));
    });
  });

  group('habits', () {
    test('plan from the start date and stop from the archive date', () async {
      await h.setWanted(true);
      await h.addHabit(
        time: const LocalTime(18, 0),
        started: LocalDate(2026, 10, 4),
        archivedFrom: LocalDate(2026, 10, 7),
      );
      await h.service.reconcile();
      final dates = (await h.rowKeys()).map((k) => k.split(':').last).toList();
      expect(dates, ['2026-10-04', '2026-10-05', '2026-10-06']);
    });

    test(
      'archiving today works from tomorrow: today stays, the rest goes',
      () async {
        await h.setWanted(true);
        final habit = await h.addHabit(time: const LocalTime(18, 0));
        await h.service.reconcile();
        expect(await h.rows(), hasLength(7));

        await h.updateHabit(habit, archivedFrom: Value(LocalDate(2026, 10, 4)));
        await h.service.reconcile();

        final dates = (await h.rowKeys())
            .map((k) => k.split(':').last)
            .toList();
        expect(dates, ['2026-10-03']);
        expect(h.platform.alarms, hasLength(1));
      },
    );

    test('a habit archived from today on has no reminders at all', () async {
      await h.setWanted(true);
      final habit = await h.addHabit(time: const LocalTime(18, 0));
      await h.service.reconcile();
      await h.updateHabit(habit, archivedFrom: Value(LocalDate(2026, 10, 3)));
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test('a soft deleted habit loses all its notifications', () async {
      await h.setWanted(true);
      final habit = await h.addHabit();
      final other = await h.addHabit(time: const LocalTime(19, 0));
      await h.service.reconcile();
      expect(await h.rows(), hasLength(14));

      await h.updateHabit(habit, deletedAt: Value(h.data.clock.nowUtc()));
      await h.service.reconcile();
      final rows = await h.rows();
      expect(rows, hasLength(7));
      expect(rows.every((r) => r.semanticKey.contains(other)), isTrue);
    });

    test('a habit that is deleted from the start is never planned', () async {
      await h.setWanted(true);
      await h.addHabit(deleted: true);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.scheduleCalls, isEmpty);
    });

    test('undo of a delete plans the habit again', () async {
      await h.setWanted(true);
      final habit = await h.addHabit();
      await h.updateHabit(habit, deletedAt: Value(h.data.clock.nowUtc()));
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      await h.updateHabit(habit, deletedAt: const Value(null));
      await h.service.reconcile();
      expect(await h.rows(), hasLength(7));
    });

    test('removing the reminder time cancels the notifications', () async {
      await h.setWanted(true);
      final habit = await h.addHabit();
      await h.service.reconcile();
      await h.updateHabit(habit, time: const Value(null));
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test('the habit title never reaches the system', () async {
      await h.setWanted(true);
      await h.addHabit(title: 'Geheime Gewohnheit');
      await h.service.reconcile();
      for (final call in h.platform.scheduleCalls) {
        expect(call.title, 'Zeit für deine Gewohnheit');
        expect(call.payload, isNot(contains('Geheime')));
      }
    });

    test('habit reminders carry the detail route of the habit', () async {
      await h.setWanted(true);
      final habit = await h.addHabit();
      await h.service.reconcile();
      expect(
        (await h.rows()).every((r) => r.route == '/habits/$habit'),
        isTrue,
      );
    });
  });

  group('focus end', () {
    test('a running session gets one notification at its end', () async {
      await h.setWanted(true);
      final session = await h.addFocus(
        planned: 1800,
        segmentStart: h.data.clock.nowUtc(),
      );
      await h.service.reconcile();

      final rows = await h.rows();
      expect(rows, hasLength(1));
      expect(rows.single.semanticKey, 'focus_end:$session');
      expect(rows.single.fireAtUtc, DateTime.utc(2026, 10, 3, 7));
      expect(rows.single.route, '/focus/session');
      final alarm = h.platform.alarms[rows.single.notificationId]!;
      expect(alarm.title, 'Deine Fokuszeit ist vorbei');
      expect(alarm.payload, '/focus/session');
    });

    test(
      'pause cancels it and resume plans it again from the new segment',
      () async {
        await h.setWanted(true);
        final session = await h.addFocus(
          planned: 1800,
          segmentStart: h.data.clock.nowUtc(),
        );
        await h.service.reconcile();
        final firstId = (await h.rows()).single.notificationId;

        // Ten minutes later: paused with 600 s accumulated.
        h.data.clock.advance(const Duration(minutes: 10));
        await h.pauseFocus(session, accumulated: 600);
        h.platform.clearCalls();
        await h.service.reconcile();
        expect(h.platform.cancelCalls, [firstId]);
        expect(await h.rows(), isEmpty);
        expect(h.platform.alarms, isEmpty);

        // Five minutes of pause, then resume: 1200 s remain.
        h.data.clock.advance(const Duration(minutes: 5));
        await h.resumeFocus(session);
        await h.service.reconcile();
        final rows = await h.rows();
        expect(rows, hasLength(1));
        expect(rows.single.fireAtUtc, DateTime.utc(2026, 10, 3, 7, 5));
        expect(rows.single.notificationId, isNot(firstId));
      },
    );

    test('completing the session cancels it', () async {
      await h.setWanted(true);
      final session = await h.addFocus(segmentStart: h.data.clock.nowUtc());
      await h.service.reconcile();
      expect(h.platform.alarms, hasLength(1));
      await h.closeFocus(session, completed: true);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test('discarding the session cancels it', () async {
      await h.setWanted(true);
      final session = await h.addFocus(segmentStart: h.data.clock.nowUtc());
      await h.service.reconcile();
      await h.closeFocus(session, completed: false);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test(
      'a session that reached its end needs no notification any more',
      () async {
        await h.setWanted(true);
        await h.addFocus(planned: 600, segmentStart: h.data.clock.nowUtc());
        await h.service.reconcile();
        expect(await h.rows(), hasLength(1));
        h.data.clock.advance(const Duration(minutes: 11));
        await h.service.reconcile();
        expect(await h.rows(), isEmpty);
      },
    );

    test('switching the module off cancels it', () async {
      await h.setWanted(true);
      await h.addFocus(segmentStart: h.data.clock.nowUtc());
      await h.service.reconcile();
      await h.setModule(ModuleId.focus, enabled: false);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test('a paused session has no notification', () async {
      await h.setWanted(true);
      await h.addFocus(status: 'paused', accumulated: 300);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
    });

    test('a session awaiting confirmation has no notification', () async {
      await h.setWanted(true);
      await h.addFocus(status: 'awaiting_confirmation', accumulated: 1500);
      await h.service.reconcile();
      expect(await h.rows(), isEmpty);
    });

    test('focus end and the other reminders live side by side', () async {
      await waterOnly();
      await h.addFocus(segmentStart: h.data.clock.nowUtc());
      await h.service.reconcile();
      final kinds = (await h.rows()).map((r) => r.kind).toSet();
      expect(kinds, {ReminderKind.water, ReminderKind.focusEnd});
    });
  });

  group('limit', () {
    test('at most 40 notifications are handed to the system', () async {
      await h.setWanted(true);
      for (var n = 0; n < 12; n++) {
        await h.addHabit(time: const LocalTime(9, 0));
      }
      final status = await h.service.reconcile();
      expect(status.scheduledCount, 40);
      expect(status.planLimitReached, isTrue);
      expect(h.platform.alarms, hasLength(40));
      expect(await h.rows(), hasLength(40));
      expect(status.state, ReminderState.active);
    });

    test('the cut part follows when days have passed', () async {
      await h.setWanted(true);
      for (var n = 0; n < 12; n++) {
        await h.addHabit(time: const LocalTime(9, 0));
      }
      await h.service.reconcile();
      String dayOf(String key) => key.split(':').last;
      expect((await h.rowKeys()).map(dayOf).toSet(), {
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
      });

      h.data.clock.advance(const Duration(days: 1));
      final status = await h.service.reconcile();
      expect(status.scheduledCount, 40);
      expect((await h.rowKeys()).map(dayOf).toSet(), {
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
      });
      expect(h.platform.alarms, hasLength(40));
    });

    test('below the limit the status does not report a cut', () async {
      await waterOnly();
      final status = await h.service.reconcile();
      expect(status.planLimitReached, isFalse);
    });
  });
}
