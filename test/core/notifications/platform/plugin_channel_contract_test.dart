import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Runs the adapter on the REAL plugin classes of the installed
/// `flutter_local_notifications` version with the native side replaced by a
/// recording method channel. It proves what the plugin's Dart code puts on the
/// wire for our calls (method names, arguments, schedule mode, ids) and how it
/// reads the answers; it cannot prove what Android then does with them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall call)> answers;
  late FlutterLocalNotificationsReminderPlatform platform;

  setUpAll(() {
    TimeZones.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fln.AndroidFlutterLocalNotificationsPlugin.registerWith();
  });
  tearDownAll(() => debugDefaultTargetPlatformOverride = null);

  setUp(() {
    calls = [];
    answers = {
      'initialize': (_) => true,
      'createNotificationChannel': (_) => null,
      'zonedSchedule': (_) => null,
      'cancel': (_) => null,
      'cancelAllPendingNotifications': (_) => null,
      'pendingNotificationRequests': (_) => <Object?>[],
      'getNotificationAppLaunchDetails': (_) => <String, Object?>{
        'notificationLaunchedApp': false,
      },
      'areNotificationsEnabled': (_) => true,
      'requestNotificationsPermission': (_) => true,
      'openAppNotificationSettings': (_) => true,
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final answer = answers[call.method];
      if (answer == null) {
        throw MissingPluginException('no answer for ${call.method}');
      }
      return answer(call);
    });
    platform = FlutterLocalNotificationsReminderPlatform();
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await platform.dispose();
  });

  MethodCall called(String method) =>
      calls.lastWhere((c) => c.method == method);

  Map<Object?, Object?> args(String method) =>
      called(method).arguments as Map<Object?, Object?>;

  test(
    'initialize sends the status bar icon and creates the channel',
    () async {
      await platform.initialize();
      expect(args('initialize')['defaultIcon'], 'ic_stat_notification');
      final channelArgs = args('createNotificationChannel');
      expect(channelArgs['id'], 'reminders');
      expect(channelArgs['name'], 'Erinnerungen');
      expect(channelArgs['importance'], fln.Importance.defaultImportance.value);
    },
  );

  test(
    'schedule is an inexact one-shot alarm with the persistent id',
    () async {
      await platform.schedule(
        PlatformScheduleRequest(
          id: 42,
          fireAtUtc: DateTime.utc(2036, 10, 3, 8),
          timeZoneId: 'Europe/Berlin',
          title: 'Zeit für ein Glas Wasser',
          payload: '/water',
        ),
      );
      final schedule = args('zonedSchedule');
      expect(schedule['id'], 42);
      expect(schedule['title'], 'Zeit für ein Glas Wasser');
      expect(schedule['payload'], '/water');
      expect(schedule['timeZoneName'], 'Europe/Berlin');
      // The wall clock time of the planned zone, not UTC.
      expect(schedule['scheduledDateTime'], '2036-10-03T10:00:00');
      expect(schedule.containsKey('matchDateTimeComponents'), isFalse);
      final specifics = schedule['platformSpecifics']! as Map<Object?, Object?>;
      expect(specifics['scheduleMode'], 'inexactAllowWhileIdle');
      expect(specifics['channelId'], 'reminders');
    },
  );

  test('a time in the past is refused before anything is sent', () async {
    await expectLater(
      platform.schedule(
        PlatformScheduleRequest(
          id: 1,
          fireAtUtc: DateTime.utc(2020, 1, 1),
          timeZoneId: 'Europe/Berlin',
          title: 't',
          payload: '/',
        ),
      ),
      throwsA(
        isA<ReminderPlatformException>().having(
          (e) => e.kind,
          'kind',
          PlatformFailureKind.timeInPast,
        ),
      ),
    );
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
  });

  test('an id beyond 32 bits is refused by the plugin', () async {
    await expectLater(
      platform.schedule(
        PlatformScheduleRequest(
          id: 0x80000000,
          fireAtUtc: DateTime.utc(2036),
          timeZoneId: 'Europe/Berlin',
          title: 't',
          payload: '/',
        ),
      ),
      throwsA(isA<ReminderPlatformException>()),
    );
  });

  test('the autumn doubled hour keeps the first occurrence', () async {
    // 00:30Z on 2036-10-26 is 02:30 CEST, the first of the two 02:30.
    await platform.schedule(
      PlatformScheduleRequest(
        id: 5,
        fireAtUtc: DateTime.utc(2036, 10, 26, 0, 30),
        timeZoneId: 'Europe/Berlin',
        title: 't',
        payload: '/',
      ),
    );
    final schedule = args('zonedSchedule');
    expect(schedule['scheduledDateTime'], '2036-10-26T02:30:00');
    expect(schedule['scheduledDateTimeISO8601'], endsWith('+0200'));
  });

  test(
    'cancel names the id, and cancelling pending is not cancelAll',
    () async {
      await platform.cancel(7);
      expect(called('cancel').arguments, {'id': 7, 'tag': null});
      await platform.cancelAllPending();
      expect(
        calls.map((c) => c.method),
        contains('cancelAllPendingNotifications'),
      );
      expect(calls.map((c) => c.method), isNot(contains('cancelAll')));
    },
  );

  test('pendingIds reads the ids of the plugin answer', () async {
    answers['pendingNotificationRequests'] = (_) => <Object?>[
      <String, Object?>{
        'id': 3,
        'title': 't',
        'body': null,
        'payload': '/water',
      },
      <String, Object?>{'id': 9, 'title': null, 'body': null, 'payload': ''},
    ];
    expect(await platform.pendingIds(), {3, 9});
  });

  test(
    'permission is read from the platform and read back after the request',
    () async {
      answers['areNotificationsEnabled'] = (_) => false;
      expect(await platform.permissionStatus(), NotificationPermission.denied);

      var asked = false;
      answers['requestNotificationsPermission'] = (_) {
        asked = true;
        answers['areNotificationsEnabled'] = (_) => true;
        return true;
      };
      expect(
        await platform.requestPermission(),
        NotificationPermission.granted,
      );
      expect(asked, isTrue);
      expect(
        calls.map((c) => c.method),
        containsAllInOrder([
          'requestNotificationsPermission',
          'areNotificationsEnabled',
        ]),
      );
    },
  );

  test('a refused dialog stays denied even if the plugin says true', () async {
    answers['areNotificationsEnabled'] = (_) => false;
    answers['requestNotificationsPermission'] = (_) => true;
    expect(await platform.requestPermission(), NotificationPermission.denied);
  });

  test('the system settings are opened through the plugin', () async {
    expect(await platform.openSystemSettings(), isTrue);
    answers['openAppNotificationSettings'] = (_) => false;
    expect(await platform.openSystemSettings(), isFalse);
  });

  test('the launch payload is read from the plugin once', () async {
    answers['getNotificationAppLaunchDetails'] = (_) => <String, Object?>{
      'notificationLaunchedApp': true,
      'notificationResponse': <String, Object?>{
        'notificationId': 3,
        'actionId': null,
        'input': null,
        'notificationResponseType': 0,
        'payload': '/habits',
        'data': <String, Object?>{},
      },
    };
    expect(await platform.launchPayload(), '/habits');
    expect(await platform.launchPayload(), isNull);
    expect(
      calls.where((c) => c.method == 'getNotificationAppLaunchDetails'),
      hasLength(1),
    );
  });

  test(
    'no launch payload when the app was not launched by a notification',
    () async {
      expect(await platform.launchPayload(), isNull);
    },
  );

  test(
    'a tap that the native side reports arrives on the tap stream',
    () async {
      await platform.initialize();
      final taps = <String>[];
      final subscription = platform.tapStream.listen(taps.add);
      addTearDown(subscription.cancel);

      Future<void> nativeCall(String payload, int type) async {
        final data = const StandardMethodCodec().encodeMethodCall(
          MethodCall('didReceiveNotificationResponse', <String, Object?>{
            'notificationId': 3,
            'actionId': null,
            'input': null,
            'payload': payload,
            'notificationResponseType': type,
          }),
        );
        await messenger.handlePlatformMessage(channel.name, data, (_) {});
      }

      await nativeCall('/focus/session', 0);
      await nativeCall('/water', 2); // dismissed: no tap
      await Future<void>.delayed(Duration.zero);
      expect(taps, ['/focus/session']);
    },
  );

  test('a native failure is a typed failure without its message', () async {
    answers['cancel'] = (_) =>
        throw PlatformException(code: 'x', message: 'private value 71.5 kg');
    try {
      await platform.cancel(1);
      fail('should have thrown');
    } on ReminderPlatformException catch (error) {
      expect(error.kind, PlatformFailureKind.failed);
      expect(error.toString(), isNot(contains('71.5')));
    }
  });

  test(
    'the exact alarm refusal of the plugin is a missing permission',
    () async {
      answers['zonedSchedule'] = (_) => throw PlatformException(
        code: 'exact_alarms_not_permitted',
        message: 'Exact alarms are not permitted',
      );
      try {
        await platform.schedule(
          PlatformScheduleRequest(
            id: 1,
            fireAtUtc: DateTime.utc(2036),
            timeZoneId: 'Europe/Berlin',
            title: 't',
            payload: '/',
          ),
        );
        fail('should have thrown');
      } on ReminderPlatformException catch (error) {
        expect(error.kind, PlatformFailureKind.permissionMissing);
      }
    },
  );
}
