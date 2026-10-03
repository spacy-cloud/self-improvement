import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/reminder_harness.dart';

/// A projection repository that fails on demand.
class _FlakyScheduled extends ScheduledNotificationRepository {
  _FlakyScheduled(super.database);

  bool failAll = false;
  bool failInsert = false;
  bool failUpdate = false;
  bool failDelete = false;
  bool failDeleteAll = false;

  @override
  Future<List<ScheduledReminder>> all() {
    if (failAll) {
      throw StateError('storage');
    }
    return super.all();
  }

  @override
  Future<int> insert(PlannedNotification planned) {
    if (failInsert) {
      throw StateError('storage');
    }
    return super.insert(planned);
  }

  @override
  Future<void> update(int notificationId, PlannedNotification planned) {
    if (failUpdate) {
      throw StateError('storage');
    }
    return super.update(notificationId, planned);
  }

  @override
  Future<void> delete(int notificationId) {
    if (failDelete) {
      throw StateError('storage');
    }
    return super.delete(notificationId);
  }

  @override
  Future<void> deleteAll() {
    if (failDeleteAll) {
      throw StateError('storage');
    }
    return super.deleteAll();
  }
}

/// An input reader that cannot read.
class _BrokenReader extends ReminderInputReader {
  _BrokenReader(AppDatabase database, ModuleStatusRepository modules)
    : super(
        database: database,
        modules: modules,
        waterGoalReachedToday: () async => false,
      );

  @override
  Future<ReminderInputs> read({
    required DateTime nowUtc,
    required String timeZoneId,
    required NotificationPermission permission,
  }) => throw StateError('storage');
}

/// How a failure reached the platform.
const ReminderPlatformException platformFailure = ReminderPlatformException(
  PlatformFailureKind.failed,
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  // The service logs failure categories; keep the test output clean.
  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late ReminderHarness h;
  _FlakyScheduled? flaky;

  setUp(() async {
    flaky = null;
    h = await ReminderHarness.create(
      scheduledFactory: (db) => flaky = _FlakyScheduled(db),
    );
  });
  tearDown(() => h.dispose());

  Future<void> waterOn() async {
    await h.setWanted(true);
    await h.setWaterHours({10, 12});
  }

  Future<List<ScheduledReminder>> rows() => h.rows();

  group('platform failure', () {
    test('is reported in a typed status and never thrown', () async {
      await waterOn();
      h.platform.scheduleFailure = platformFailure;

      final status = await h.service.reconcile();

      expect(status.state, ReminderState.schedulingError);
      expect(status.lastError, ReminderErrorCategory.platform);
      expect(status.failedCount, 14);
      expect(status.scheduledCount, 0);
      expect(status.wanted, isTrue);
      expect(status.permission, NotificationPermission.granted);
      expect(status.canRetry, isTrue);
    });

    test('leaves no half state: a failed notification has no row', () async {
      await waterOn();
      h.platform.scheduleFailure = platformFailure;
      await h.service.reconcile();
      expect(await rows(), isEmpty);
      expect(h.platform.alarms, isEmpty);
    });

    test(
      'a retry succeeds without committing any business data again',
      () async {
        await waterOn();
        h.platform.scheduleFailure = platformFailure;
        await h.service.reconcile();
        final receipts = await h.receiptCount();

        h.platform.scheduleFailure = null;
        final status = await h.service.reconcile();

        expect(status.state, ReminderState.active);
        expect(status.lastError, isNull);
        expect(status.failedCount, 0);
        expect(status.scheduledCount, 14);
        expect(await rows(), hasLength(14));
        expect(h.platform.alarms, hasLength(14));
        expect(
          await h.receiptCount(),
          receipts,
          reason: 'no second business commit',
        );
      },
    );

    test(
      'only the failing notification is missing, the rest is scheduled',
      () async {
        await waterOn();
        h.platform.failScheduleForIds.add(3);

        final status = await h.service.reconcile();

        expect(status.failedCount, 1);
        expect(status.lastError, ReminderErrorCategory.platform);
        expect(status.scheduledCount, 13);
        expect(await rows(), hasLength(13));
        expect(h.platform.alarms, hasLength(13));
        expect((await h.rowIds()), isNot(contains(3)));
      },
    );

    test(
      'the missing notification is retried as new and gets a fresh id',
      () async {
        await waterOn();
        h.platform.failScheduleForIds.add(3);
        await h.service.reconcile();
        h.platform.failScheduleForIds.clear();

        final status = await h.service.reconcile();

        expect(status.state, ReminderState.active);
        final ids = await h.rowIds();
        expect(ids, hasLength(14));
        expect(ids, isNot(contains(3)), reason: 'ids are never reused');
        expect(h.platform.alarms.keys.toSet(), ids);
      },
    );

    test('a plain exception from the platform is a platform failure', () async {
      await waterOn();
      h.platform.scheduleFailure = StateError('channel');
      final status = await h.service.reconcile();
      expect(status.lastError, ReminderErrorCategory.platform);
      expect(await rows(), isEmpty);
    });

    test(
      'a missing permission at the system is the permission category',
      () async {
        await waterOn();
        h.platform.scheduleFailure = const ReminderPlatformException(
          PlatformFailureKind.permissionMissing,
        );
        final status = await h.service.reconcile();
        expect(status.lastError, ReminderErrorCategory.permission);
        expect(await rows(), isEmpty);
      },
    );

    test('a time that slipped into the past is not an error', () async {
      await waterOn();
      h.platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.timeInPast,
      );
      final status = await h.service.reconcile();
      expect(status.lastError, isNull);
      expect(status.failedCount, 0);
      expect(status.state, ReminderState.active);
      expect(await rows(), isEmpty, reason: 'nothing was scheduled, no row');
    });

    test(
      'a failed reschedule removes the old alarm instead of leaving it',
      () async {
        await h.setWanted(true);
        final habit = await h.addHabit(time: const LocalTime(18, 0));
        await h.service.reconcile();
        final oldIds = await h.rowIds();
        expect(oldIds, hasLength(7));

        await h.updateHabit(habit, time: const Value(LocalTime(19, 0)));
        h.platform.scheduleFailure = platformFailure;
        final status = await h.service.reconcile();

        expect(status.lastError, ReminderErrorCategory.platform);
        expect(await rows(), isEmpty);
        expect(
          h.platform.alarms,
          isEmpty,
          reason: 'no reminder at the stale time',
        );
        expect(h.platform.cancelCalls.toSet(), oldIds);

        h.platform.scheduleFailure = null;
        final retry = await h.service.reconcile();
        expect(retry.state, ReminderState.active);
        expect((await rows()).first.fireAtUtc, DateTime.utc(2026, 10, 3, 17));
        expect(h.platform.alarms, hasLength(7));
      },
    );

    test(
      'a failing cancel keeps the row: it still describes the system',
      () async {
        await waterOn();
        await h.service.reconcile();
        await h.setWaterHours({10});
        h.platform.cancelFailure = platformFailure;

        final status = await h.service.reconcile();

        expect(status.lastError, ReminderErrorCategory.platform);
        expect(
          await rows(),
          hasLength(14),
          reason: 'the alarms are still there',
        );
        expect(h.platform.alarms, hasLength(14));

        h.platform.cancelFailure = null;
        final retry = await h.service.reconcile();
        expect(retry.state, ReminderState.active);
        expect(await rows(), hasLength(7));
        expect(h.platform.alarms, hasLength(7));
      },
    );

    test(
      'a failing cancel of everything keeps the rows and retries later',
      () async {
        await waterOn();
        await h.service.reconcile();
        await h.setWanted(false);
        h.platform.cancelFailure = platformFailure;

        final status = await h.service.reconcile();

        expect(status.state, ReminderState.off);
        expect(status.lastError, ReminderErrorCategory.platform);
        expect(await rows(), hasLength(14));

        h.platform.cancelFailure = null;
        await h.service.reconcile();
        expect(await rows(), isEmpty);
        expect(h.platform.alarms, isEmpty);
      },
    );

    test(
      'an unreadable permission is unavailable and schedules nothing',
      () async {
        await waterOn();
        h.platform.permissionFailure = StateError('channel');

        final status = await h.service.reconcile();

        expect(status.permission, NotificationPermission.unavailable);
        expect(status.state, ReminderState.unavailable);
        expect(status.lastError, ReminderErrorCategory.platform);
        expect(h.platform.scheduleCalls, isEmpty);
        expect(await rows(), isEmpty);
      },
    );

    test('an unreadable pending list does not stop scheduling', () async {
      await waterOn();
      h.platform.pendingFailure = StateError('channel');

      final status = await h.service.reconcile();

      expect(status.scheduledCount, 14);
      expect(status.lastError, ReminderErrorCategory.platform);
      expect(h.platform.alarms, hasLength(14));
    });

    test('any kind of error object is caught', () async {
      await waterOn();
      h.platform.permissionFailure = UnimplementedError('no platform');
      final status = await h.service.reconcile();
      expect(status.permission, NotificationPermission.unavailable);
    });

    test('an unknown time zone never throws', () async {
      await waterOn();
      h.data.clock.setTimeZone('Mars/Olympus');
      final status = await h.service.reconcile();
      expect(status.lastError, ReminderErrorCategory.unknown);
      expect(h.platform.scheduleCalls, isEmpty);
    });
  });

  group('storage failure', () {
    test(
      'an unreadable projection stops the run without touching the system',
      () async {
        await waterOn();
        await h.service.reconcile();
        h.platform.clearCalls();

        flaky!.failAll = true;
        final status = await h.service.reconcile();

        expect(status.lastError, ReminderErrorCategory.storage);
        expect(h.platform.scheduleCalls, isEmpty);
        expect(h.platform.cancelCalls, isEmpty);
        expect(h.platform.cancelAllPendingCalls, 0);
        expect(
          h.platform.alarms,
          hasLength(14),
          reason: 'nothing was disturbed',
        );

        flaky!.failAll = false;
        expect((await h.service.reconcile()).state, ReminderState.active);
      },
    );

    test('a failing insert schedules nothing for that notification', () async {
      await waterOn();
      flaky!.failInsert = true;
      final status = await h.service.reconcile();
      expect(status.lastError, ReminderErrorCategory.storage);
      expect(status.failedCount, 14);
      expect(h.platform.scheduleCalls, isEmpty);
      expect(h.platform.alarms, isEmpty);

      flaky!.failInsert = false;
      expect((await h.service.reconcile()).scheduledCount, 14);
    });

    test(
      'a failing delete after the cancel leaves a row but no alarm',
      () async {
        await waterOn();
        await h.service.reconcile();
        await h.setWaterHours({10});
        flaky!.failDelete = true;

        final status = await h.service.reconcile();

        expect(status.lastError, ReminderErrorCategory.storage);
        expect(h.platform.alarms, hasLength(7), reason: 'no stale reminder');
        expect(await rows(), hasLength(14));

        flaky!.failDelete = false;
        final retry = await h.service.reconcile();
        expect(retry.state, ReminderState.active);
        expect(await rows(), hasLength(7));
      },
    );

    test(
      'a failing update after the schedule is repaired by the next run',
      () async {
        await h.setWanted(true);
        final habit = await h.addHabit(time: const LocalTime(18, 0));
        await h.service.reconcile();
        await h.updateHabit(habit, time: const Value(LocalTime(19, 0)));
        flaky!.failUpdate = true;

        final status = await h.service.reconcile();

        expect(status.lastError, ReminderErrorCategory.storage);
        // The system already has the new time, the rows still the old one.
        expect(
          h.platform.alarms.values.map((r) => r.fireAtUtc).toSet(),
          contains(DateTime.utc(2026, 10, 3, 17)),
        );

        flaky!.failUpdate = false;
        h.platform.clearCalls();
        final retry = await h.service.reconcile();
        expect(retry.state, ReminderState.active);
        expect((await rows()).first.fireAtUtc, DateTime.utc(2026, 10, 3, 17));
        expect(h.platform.alarms, hasLength(7));
      },
    );

    test('a failing bulk delete is reported and repaired', () async {
      await waterOn();
      await h.service.reconcile();
      await h.setWanted(false);
      flaky!.failDeleteAll = true;
      final status = await h.service.reconcile();
      expect(status.lastError, ReminderErrorCategory.storage);
      expect(h.platform.alarms, isEmpty);

      flaky!.failDeleteAll = false;
      await h.service.reconcile();
      expect(await rows(), isEmpty);
    });

    test(
      'unreadable inputs are a storage failure without side effects',
      () async {
        final broken = ReminderService(
          inputs: _BrokenReader(h.database, h.data.moduleStatus),
          scheduled: h.scheduled,
          preferences: h.preferences,
          platform: h.platform,
          clock: h.data.clock,
        );
        addTearDown(broken.dispose);
        final status = await broken.reconcile();
        expect(status.lastError, ReminderErrorCategory.storage);
        expect(h.platform.scheduleCalls, isEmpty);
        expect(h.platform.cancelCalls, isEmpty);
      },
    );
  });

  group('process restart and self healing', () {
    test('the first run of a new process registers everything again', () async {
      await waterOn();
      await h.service.reconcile();
      final before = await rows();

      final restarted = h.newProcess();
      addTearDown(restarted.dispose);
      h.platform.clearCalls();
      await restarted.reconcile();

      expect(h.platform.scheduleCalls, hasLength(14));
      expect(h.platform.scheduleCalls.map((c) => c.id).toSet(), {
        for (final r in before) r.notificationId,
      }, reason: 'under the same ids');
      expect(h.platform.cancelCalls, isEmpty);
      expect(await rows(), before, reason: 'the projection is unchanged');

      h.platform.clearCalls();
      await restarted.reconcile();
      expect(
        h.platform.scheduleCalls,
        isEmpty,
        reason: 'only once per process',
      );
    });

    test('a forced stop is repaired when the app is opened again', () async {
      await waterOn();
      await h.service.reconcile();
      h.platform.forceStop();
      expect(h.platform.alarms, isEmpty);

      // The same process cannot know: the plugin still lists them as pending.
      await h.service.reconcile();
      expect(h.platform.alarms, isEmpty);

      // A new process (the app was opened again) registers them again.
      final reopened = h.newProcess();
      addTearDown(reopened.dispose);
      await reopened.reconcile();
      expect(h.platform.alarms, hasLength(14));
      expect(h.platform.alarms.keys.toSet(), await h.rowIds());
    });

    test('a notification the system lost is registered again', () async {
      await waterOn();
      await h.service.reconcile();
      final before = await rows();
      h.platform.wipe();
      h.platform.clearCalls();

      await h.service.reconcile();

      expect(h.platform.scheduleCalls, hasLength(14));
      expect(h.platform.alarms, hasLength(14));
      expect(await rows(), before, reason: 'same rows, same ids');
    });

    test(
      'a pending notification the projection does not know is cancelled',
      () async {
        await waterOn();
        await h.service.reconcile();
        await h.platform.schedule(
          PlatformScheduleRequest(
            id: 999,
            fireAtUtc: DateTime.utc(2026, 10, 3, 9),
            timeZoneId: 'Europe/Berlin',
            title: 'Zeit für ein Glas Wasser',
            payload: '/water',
          ),
        );
        h.platform.clearCalls();

        await h.service.reconcile();

        expect(h.platform.cancelCalls, [999]);
        expect(h.platform.alarms, isNot(contains(999)));
        expect(h.platform.alarms, hasLength(14));
        expect(await rows(), hasLength(14));
      },
    );

    test('a wiped projection leaves no duplicate alarms behind', () async {
      await waterOn();
      await h.service.reconcile();
      final oldIds = await h.rowIds();
      await h.scheduled.deleteAll();

      final status = await h.service.reconcile();

      final newIds = await h.rowIds();
      expect(newIds, hasLength(14));
      expect(
        newIds.intersection(oldIds),
        isEmpty,
        reason: 'ids are never reused',
      );
      expect(
        h.platform.alarms.keys.toSet(),
        newIds,
        reason: 'old alarms cancelled',
      );
      expect(status.scheduledCount, 14);
    });

    test('nothing wanted but alarms pending: they are cancelled', () async {
      await waterOn();
      await h.service.reconcile();
      // The projection was lost and the user's wish is off: the system still
      // holds alarms of an earlier life.
      await h.scheduled.deleteAll();
      await h.setWanted(false);
      h.platform.clearCalls();

      await h.service.reconcile();

      expect(h.platform.cancelAllPendingCalls, 1);
      expect(h.platform.alarms, isEmpty);
    });

    test('a row of an unknown kind is cleaned up', () async {
      await waterOn();
      await h.service.reconcile();
      await h.database
          .into(h.database.scheduledNotifications)
          .insert(
            ScheduledNotificationsCompanion.insert(
              semanticKey: 'unknown:x',
              fireAtUtc: DateTime.utc(2026, 10, 5),
              route: '/',
            ),
          );
      await h.service.reconcile();
      expect(await h.rowKeys(), isNot(contains('unknown:x')));
    });
  });

  group('concurrent runs', () {
    test(
      'calls that arrive while a run is busy share one follow-up run',
      () async {
        await waterOn();
        final results = await Future.wait([
          for (var n = 0; n < 5; n++) h.service.reconcile(),
        ]);
        expect(results, hasLength(5));
        expect(
          h.platform.scheduleCalls,
          hasLength(14),
          reason: 'no duplicates',
        );
        expect(
          h.platform.pendingIdsCalls,
          2,
          reason: 'one run plus one follow-up',
        );
        expect(await rows(), hasLength(14));
        expect(
          results.toSet(),
          hasLength(1),
          reason: 'all see the same result',
        );
      },
    );

    test(
      'a change made while a run is busy is picked up by the follow-up',
      () async {
        await waterOn();
        final gate = Completer<void>();
        h.platform.scheduleGate = gate.future;

        final first = h.service.reconcile();
        await pumpEventQueue();
        expect(h.platform.scheduleCalls, hasLength(1), reason: 'held mid-run');

        await h.addHabit(time: const LocalTime(19, 0));
        final second = h.service.reconcile();

        gate.complete();
        final firstStatus = await first;
        final secondStatus = await second;

        expect(firstStatus.scheduledCount, 14);
        expect(secondStatus.scheduledCount, 21, reason: 'water plus the habit');
        expect(await rows(), hasLength(21));
        expect(h.platform.alarms, hasLength(21));
        // No notification was handed over twice for the same key.
        final keys = await h.rowKeys();
        expect(keys.toSet(), hasLength(keys.length));
      },
    );

    test('whenIdle completes after the last run', () async {
      await waterOn();
      final run = h.service.reconcile();
      unawaited(h.service.reconcile());
      await h.service.whenIdle();
      expect(await run, isNotNull);
      expect(await rows(), hasLength(14));
    });

    test('the service keeps working after it was disposed', () async {
      await waterOn();
      await h.service.dispose();
      final status = await h.service.reconcile();
      expect(status.scheduledCount, 14);
    });
  });
}
