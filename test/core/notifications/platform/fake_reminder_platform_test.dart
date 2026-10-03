import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';

/// The fake is the stand-in for the operating system in every test of the
/// reminder engine and of the app shell, so its own contract is pinned here.
void main() {
  setUpAll(TimeZones.ensureInitialized);

  PlatformScheduleRequest request(int id, {DateTime? at, String? payload}) =>
      PlatformScheduleRequest(
        id: id,
        fireAtUtc: at ?? DateTime.utc(2026, 10, 3, 8),
        timeZoneId: 'Europe/Berlin',
        title: 'Zeit für ein Glas Wasser',
        payload: payload ?? '/water',
      );

  late FakeReminderPlatform platform;
  late FakeClock clock;

  setUp(() {
    clock = FakeClock.at('2026-10-03T06:00:00Z');
    platform = FakeReminderPlatform(clock: clock);
  });
  tearDown(() => platform.dispose());

  group('scheduling', () {
    test('schedule registers an alarm and a pending entry', () async {
      await platform.schedule(request(1));
      expect(platform.alarms.keys, [1]);
      expect(await platform.pendingIds(), {1});
      expect(platform.scheduleCalls.single.payload, '/water');
    });

    test('scheduling the same id replaces the notification', () async {
      await platform.schedule(request(1, at: DateTime.utc(2026, 10, 3, 8)));
      await platform.schedule(request(1, at: DateTime.utc(2026, 10, 3, 9)));
      expect(platform.alarms, hasLength(1));
      expect(platform.alarms[1]!.fireAtUtc, DateTime.utc(2026, 10, 3, 9));
      expect(platform.scheduleCalls, hasLength(2));
    });

    test('cancel removes alarm and pending entry and is recorded', () async {
      await platform.schedule(request(1));
      await platform.schedule(request(2));
      await platform.cancel(1);
      expect(platform.alarms.keys, [2]);
      expect(await platform.pendingIds(), {2});
      expect(platform.cancelCalls, [1]);
    });

    test('cancelling an unknown id is harmless', () async {
      await platform.cancel(42);
      expect(platform.cancelCalls, [42]);
    });

    test('cancelAllPending removes everything pending', () async {
      await platform.schedule(request(1));
      await platform.schedule(request(2));
      await platform.cancelAllPending();
      expect(platform.alarms, isEmpty);
      expect(await platform.pendingIds(), isEmpty);
      expect(platform.cancelAllPendingCalls, 1);
    });

    test('a time that is not in the future throws timeInPast', () async {
      await expectLater(
        platform.schedule(request(1, at: DateTime.utc(2026, 10, 3, 6))),
        throwsA(
          isA<ReminderPlatformException>().having(
            (e) => e.kind,
            'kind',
            PlatformFailureKind.timeInPast,
          ),
        ),
      );
      expect(platform.alarms, isEmpty);
    });

    test('without a clock the time is not checked', () async {
      final unchecked = FakeReminderPlatform();
      await unchecked.schedule(request(1, at: DateTime.utc(2020)));
      expect(unchecked.alarms, hasLength(1));
      await unchecked.dispose();
    });

    test('ids outside 1 to 2^31-1 are refused like the plugin does', () async {
      for (final id in [0, -1, 0x80000000]) {
        await expectLater(
          platform.schedule(request(id)),
          throwsA(isA<ReminderPlatformException>()),
          reason: '$id',
        );
      }
      await platform.schedule(request(0x7FFFFFFF));
      expect(platform.alarms.keys, [0x7FFFFFFF]);
    });
  });

  group('operating system behaviour', () {
    test('deliverDue shows due alarms and removes them', () async {
      await platform.schedule(request(1, at: DateTime.utc(2026, 10, 3, 8)));
      await platform.schedule(request(2, at: DateTime.utc(2026, 10, 3, 10)));
      platform.deliverDue(DateTime.utc(2026, 10, 3, 8));
      expect(platform.delivered.map((r) => r.id), [1]);
      expect(platform.alarms.keys, [2]);
      expect(await platform.pendingIds(), {2});
    });

    test(
      'a forced stop drops the alarms but the pending list survives',
      () async {
        await platform.schedule(request(1));
        platform.forceStop();
        expect(platform.alarms, isEmpty);
        expect(await platform.pendingIds(), {1});
        platform.deliverDue(DateTime.utc(2030));
        expect(platform.delivered, isEmpty, reason: 'nothing fires after it');
      },
    );

    test('wipe drops alarms and pending list', () async {
      await platform.schedule(request(1));
      platform.wipe();
      expect(platform.alarms, isEmpty);
      expect(await platform.pendingIds(), isEmpty);
    });
  });

  group('permission', () {
    test('reports the configured permission and counts the queries', () async {
      platform.permission = NotificationPermission.denied;
      expect(await platform.permissionStatus(), NotificationPermission.denied);
      expect(platform.permissionStatusCalls, 1);
    });

    test(
      'the dialog turns a missing permission into the configured result',
      () async {
        platform.permission = NotificationPermission.denied;
        platform.permissionAfterRequest = NotificationPermission.granted;
        expect(
          await platform.requestPermission(),
          NotificationPermission.granted,
        );
        expect(platform.permission, NotificationPermission.granted);
        expect(platform.requestPermissionCalls, 1);
      },
    );

    test('a refusing dialog leaves the permission denied', () async {
      platform.permission = NotificationPermission.denied;
      platform.permissionAfterRequest = NotificationPermission.denied;
      expect(await platform.requestPermission(), NotificationPermission.denied);
    });

    test('settings can be opened or not', () async {
      expect(await platform.openSystemSettings(), isTrue);
      platform.settingsCanOpen = false;
      expect(await platform.openSystemSettings(), isFalse);
      expect(platform.openSettingsCalls, 2);
    });
  });

  group('failures', () {
    test('every call can be made to fail', () async {
      platform.scheduleFailure = const ReminderPlatformException(
        PlatformFailureKind.failed,
      );
      await expectLater(
        platform.schedule(request(1)),
        throwsA(isA<ReminderPlatformException>()),
      );
      expect(platform.alarms, isEmpty);
      platform.scheduleFailure = null;

      platform.cancelFailure = StateError('x');
      await expectLater(platform.cancel(1), throwsStateError);
      await expectLater(platform.cancelAllPending(), throwsStateError);
      platform.cancelFailure = null;

      platform.permissionFailure = StateError('x');
      await expectLater(platform.permissionStatus(), throwsStateError);
      platform.permissionFailure = null;

      platform.pendingFailure = StateError('x');
      await expectLater(platform.pendingIds(), throwsStateError);
      platform.pendingFailure = null;

      platform.requestFailure = StateError('x');
      await expectLater(platform.requestPermission(), throwsStateError);
    });

    test('single ids can be made to fail', () async {
      platform.failScheduleForIds.add(2);
      await platform.schedule(request(1));
      await expectLater(
        platform.schedule(request(2)),
        throwsA(isA<ReminderPlatformException>()),
      );
      expect(platform.alarms.keys, [1]);
    });

    test('clearCalls forgets calls but keeps the simulated state', () async {
      await platform.schedule(request(1));
      platform.clearCalls();
      expect(platform.scheduleCalls, isEmpty);
      expect(platform.alarms, hasLength(1));
    });
  });

  group('launch and taps', () {
    test('the launch payload is returned once', () async {
      platform.launchPayloadValue = '/water';
      expect(await platform.launchPayload(), '/water');
      expect(await platform.launchPayload(), isNull);
    });

    test('no launch payload when the app was not started by a tap', () async {
      expect(await platform.launchPayload(), isNull);
    });

    test('taps arrive on the tap stream', () async {
      final taps = <String>[];
      final subscription = platform.tapStream.listen(taps.add);
      addTearDown(subscription.cancel);
      platform.emitTap('/habits');
      await Future<void>.delayed(Duration.zero);
      expect(taps, ['/habits']);
    });

    test('initialize is counted and can fail', () async {
      await platform.initialize();
      expect(platform.initializeCalls, 1);
      platform.initializeFailure = StateError('x');
      await expectLater(platform.initialize(), throwsStateError);
      expect(platform.initializeCalls, 2);
    });
  });
}
