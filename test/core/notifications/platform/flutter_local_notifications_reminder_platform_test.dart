import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// Android implementation double: no method channel, answers from fields.
class _FakeAndroid extends fln.AndroidFlutterLocalNotificationsPlugin {
  bool? enabled = true;
  bool? requestResult = true;

  /// What `areNotificationsEnabled` reports after the permission dialog.
  bool? enabledAfterRequest;
  int requestCalls = 0;
  final List<fln.AndroidNotificationChannel> channels = [];

  @override
  Future<bool?> areNotificationsEnabled() async => enabled;

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestCalls++;
    if (enabledAfterRequest != null || requestResult != null) {
      enabled = enabledAfterRequest ?? enabled;
    }
    return requestResult;
  }

  @override
  Future<void> createNotificationChannel(
    fln.AndroidNotificationChannel notificationChannel,
  ) async {
    channels.add(notificationChannel);
  }
}

/// iOS implementation double.
class _FakeIos extends fln.IOSFlutterLocalNotificationsPlugin {
  bool enabled = false;
  bool enabledAfterRequest = true;
  Map<String, bool>? requested;

  fln.NotificationsEnabledOptions options(bool on) =>
      fln.NotificationsEnabledOptions(
        isEnabled: on,
        isSoundEnabled: on,
        isAlertEnabled: on,
        isBadgeEnabled: false,
        isProvisionalEnabled: false,
        isCriticalEnabled: false,
        isProvidesAppNotificationSettingsEnabled: false,
      );

  @override
  Future<fln.NotificationsEnabledOptions?> checkPermissions() async =>
      options(enabled);

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
    bool carPlay = false,
    bool providesAppNotificationSettings = false,
  }) async {
    requested = {'sound': sound, 'alert': alert, 'badge': badge};
    enabled = enabledAfterRequest;
    return enabled;
  }
}

/// Plugin facade double that records what the adapter calls.
class _FakePlugin implements fln.FlutterLocalNotificationsPlugin {
  _FakePlugin({this.android, this.ios});

  final _FakeAndroid? android;
  final _FakeIos? ios;

  int initializeCalls = 0;
  fln.InitializationSettings? settings;
  fln.DidReceiveNotificationResponseCallback? onResponse;
  Object? initializeFailure;

  final List<Map<String, Object?>> scheduled = [];
  Object? scheduleFailure;
  final List<int> cancelled = [];
  int cancelAllCalls = 0;
  int cancelAllPendingCalls = 0;
  List<fln.PendingNotificationRequest> pending = [];
  bool? settingsOpened = true;
  fln.NotificationAppLaunchDetails? launchDetails;
  Object? launchFailure;
  int launchReads = 0;

  @override
  T? resolvePlatformSpecificImplementation<
    T extends fln.FlutterLocalNotificationsPlatform
  >() {
    if (T == fln.AndroidFlutterLocalNotificationsPlugin) {
      return android as T?;
    }
    if (T == fln.IOSFlutterLocalNotificationsPlugin) {
      return ios as T?;
    }
    return null;
  }

  @override
  Future<bool?> initialize({
    required fln.InitializationSettings settings,
    fln.DidReceiveNotificationResponseCallback?
    onDidReceiveNotificationResponse,
    fln.DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls++;
    final failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
    this.settings = settings;
    onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required fln.NotificationDetails notificationDetails,
    required fln.AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    fln.DateTimeComponents? matchDateTimeComponents,
  }) async {
    final failure = scheduleFailure;
    if (failure != null) {
      throw failure;
    }
    scheduled.add({
      'id': id,
      'date': scheduledDate,
      'details': notificationDetails,
      'mode': androidScheduleMode,
      'title': title,
      'body': body,
      'payload': payload,
      'match': matchDateTimeComponents,
    });
  }

  @override
  Future<void> cancel({required int id, String? tag}) async {
    cancelled.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
  }

  @override
  Future<void> cancelAllPendingNotifications() async {
    cancelAllPendingCalls++;
  }

  @override
  Future<List<fln.PendingNotificationRequest>>
  pendingNotificationRequests() async => pending;

  @override
  Future<bool?> openAppNotificationSettings() async => settingsOpened;

  @override
  Future<fln.NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    launchReads++;
    final failure = launchFailure;
    if (failure != null) {
      throw failure;
    }
    return launchDetails;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

fln.NotificationResponse response(
  String? payload, {
  fln.NotificationResponseType type =
      fln.NotificationResponseType.selectedNotification,
}) =>
    fln.NotificationResponse(notificationResponseType: type, payload: payload);

PlatformScheduleRequest request({
  int id = 7,
  DateTime? at,
  String zone = 'Europe/Berlin',
  String payload = '/water',
  String? body,
}) => PlatformScheduleRequest(
  id: id,
  fireAtUtc: at ?? DateTime.utc(2026, 10, 3, 8),
  timeZoneId: zone,
  title: 'Zeit für ein Glas Wasser',
  body: body,
  payload: payload,
);

void main() {
  setUpAll(TimeZones.ensureInitialized);

  late _FakeAndroid android;
  late _FakePlugin plugin;
  late FlutterLocalNotificationsReminderPlatform platform;

  setUp(() {
    android = _FakeAndroid();
    plugin = _FakePlugin(android: android);
    platform = FlutterLocalNotificationsReminderPlatform(plugin: plugin);
  });
  tearDown(() => platform.dispose());

  group('initialize', () {
    test('uses the status bar icon and asks for no permission', () async {
      await platform.initialize();
      expect(plugin.initializeCalls, 1);
      expect(plugin.settings!.android!.defaultIcon, 'ic_stat_notification');
      final ios = plugin.settings!.iOS!;
      expect(ios.requestAlertPermission, isFalse);
      expect(ios.requestBadgePermission, isFalse);
      expect(ios.requestSoundPermission, isFalse);
    });

    test('creates the reminder channel with the neutral German name', () async {
      await platform.initialize();
      final channel = android.channels.single;
      expect(channel.id, 'reminders');
      expect(channel.name, 'Erinnerungen');
      expect(channel.importance, fln.Importance.defaultImportance);
    });

    test('is idempotent', () async {
      await platform.initialize();
      await platform.initialize();
      await platform.initialize();
      expect(plugin.initializeCalls, 1);
      expect(android.channels, hasLength(1));
    });

    test('a failure is typed and retried on the next call', () async {
      plugin.initializeFailure = PlatformException(code: 'invalid_icon');
      await expectLater(
        platform.initialize(),
        throwsA(
          isA<ReminderPlatformException>().having(
            (e) => e.kind,
            'kind',
            PlatformFailureKind.failed,
          ),
        ),
      );
      plugin.initializeFailure = null;
      await platform.initialize();
      expect(plugin.initializeCalls, 2);
      expect(plugin.settings, isNotNull);
    });

    test('works without an Android implementation (other platform)', () async {
      final other = FlutterLocalNotificationsReminderPlatform(
        plugin: _FakePlugin(),
      );
      await other.initialize();
      expect(
        await other.permissionStatus(),
        NotificationPermission.unavailable,
      );
      await other.dispose();
    });
  });

  group('schedule', () {
    test('is a one-shot, inexact alarm that may run while idle', () async {
      await platform.schedule(request());
      final call = plugin.scheduled.single;
      expect(call['mode'], fln.AndroidScheduleMode.inexactAllowWhileIdle);
      expect(call['match'], isNull, reason: 'one-shot, never repeating');
    });

    test('hands over id, texts and the payload', () async {
      await platform.schedule(request(id: 12, payload: '/habits', body: 'b'));
      final call = plugin.scheduled.single;
      expect(call['id'], 12);
      expect(call['title'], 'Zeit für ein Glas Wasser');
      expect(call['body'], 'b');
      expect(call['payload'], '/habits');
    });

    test('puts the notification on the reminder channel', () async {
      await platform.schedule(request());
      final details =
          plugin.scheduled.single['details']! as fln.NotificationDetails;
      expect(details.android!.channelId, 'reminders');
      expect(details.android!.channelName, 'Erinnerungen');
    });

    test(
      'the zoned time is the same instant with the planned wall clock',
      () async {
        await platform.schedule(
          request(at: DateTime.utc(2026, 10, 3, 8), zone: 'Europe/Berlin'),
        );
        final date = plugin.scheduled.single['date']! as tz.TZDateTime;
        expect(date.toUtc(), DateTime.utc(2026, 10, 3, 8));
        expect(date.location.name, 'Europe/Berlin');
        expect(date.hour, 10);
        expect(date.minute, 0);
      },
    );

    test(
      'initializes the plugin first when that has not happened yet',
      () async {
        await platform.schedule(request());
        expect(plugin.initializeCalls, 1);
      },
    );

    test(
      'a time that is not in the future is reported as timeInPast',
      () async {
        plugin.scheduleFailure = ArgumentError.value(
          DateTime.utc(2020),
          'scheduledDate',
          'Must be a date in the future',
        );
        await expectLater(
          platform.schedule(request()),
          throwsA(
            isA<ReminderPlatformException>().having(
              (e) => e.kind,
              'kind',
              PlatformFailureKind.timeInPast,
            ),
          ),
        );
      },
    );

    test('a platform error is typed and carries no message', () async {
      plugin.scheduleFailure = PlatformException(
        code: 'x',
        message: 'private value 71.5 kg',
      );
      try {
        await platform.schedule(request());
        fail('should have thrown');
      } on ReminderPlatformException catch (error) {
        expect(error.kind, PlatformFailureKind.failed);
        expect(error.causeType, 'PlatformException');
        expect(error.toString(), isNot(contains('71.5')));
      }
    });
  });

  group('classify', () {
    test('keeps an already typed failure', () {
      const typed = ReminderPlatformException(
        PlatformFailureKind.permissionMissing,
      );
      expect(
        FlutterLocalNotificationsReminderPlatform.classify(typed),
        same(typed),
      );
    });

    test('maps the exact alarm refusal to a missing permission', () {
      expect(
        FlutterLocalNotificationsReminderPlatform.classify(
          PlatformException(code: 'exact_alarms_not_permitted'),
        ).kind,
        PlatformFailureKind.permissionMissing,
      );
    });

    test('maps everything else to a failure with the cause type only', () {
      final failure = FlutterLocalNotificationsReminderPlatform.classify(
        MissingPluginException('no plugin'),
      );
      expect(failure.kind, PlatformFailureKind.failed);
      expect(failure.causeType, 'MissingPluginException');
    });

    test('an argument error about another argument is a failure', () {
      expect(
        FlutterLocalNotificationsReminderPlatform.classify(
          ArgumentError.value(0, 'id', 'bad'),
        ).kind,
        PlatformFailureKind.failed,
      );
    });
  });

  group('cancel and pending', () {
    test('cancel cancels the single id', () async {
      await platform.cancel(5);
      expect(plugin.cancelled, [5]);
    });

    test('cancelAllPending cancels only pending, not what is shown', () async {
      await platform.cancelAllPending();
      expect(plugin.cancelAllPendingCalls, 1);
      expect(
        plugin.cancelAllCalls,
        0,
        reason: 'cancelAll would clear the shade',
      );
    });

    test('pendingIds maps the pending requests', () async {
      plugin.pending = const [
        fln.PendingNotificationRequest(3, 't', null, '/water'),
        fln.PendingNotificationRequest(9, null, null, null),
      ];
      expect(await platform.pendingIds(), {3, 9});
    });

    test('a failing plugin call is a typed failure', () async {
      plugin.scheduleFailure = null;
      final broken = FlutterLocalNotificationsReminderPlatform(
        plugin: _ThrowingPlugin(),
      );
      await expectLater(
        broken.cancel(1),
        throwsA(isA<ReminderPlatformException>()),
      );
      await expectLater(
        broken.pendingIds(),
        throwsA(isA<ReminderPlatformException>()),
      );
      await broken.dispose();
    });
  });

  group('permission', () {
    test('maps the Android flag', () async {
      android.enabled = true;
      expect(await platform.permissionStatus(), NotificationPermission.granted);
      android.enabled = false;
      expect(await platform.permissionStatus(), NotificationPermission.denied);
      android.enabled = null;
      expect(
        await platform.permissionStatus(),
        NotificationPermission.unavailable,
      );
    });

    test('requesting shows the dialog and reads the state back', () async {
      android.enabled = false;
      android.enabledAfterRequest = true;
      expect(
        await platform.requestPermission(),
        NotificationPermission.granted,
      );
      expect(android.requestCalls, 1);
    });

    test('a refused dialog is denied, whatever flag came back', () async {
      android.enabled = false;
      android.requestResult = true; // not trusted
      android.enabledAfterRequest = null;
      expect(await platform.requestPermission(), NotificationPermission.denied);
    });

    test(
      'maps the iOS state when there is no Android implementation',
      () async {
        final ios = _FakeIos();
        final iosPlatform = FlutterLocalNotificationsReminderPlatform(
          plugin: _FakePlugin(ios: ios),
        );
        expect(
          await iosPlatform.permissionStatus(),
          NotificationPermission.denied,
        );
        ios.enabled = true;
        expect(
          await iosPlatform.permissionStatus(),
          NotificationPermission.granted,
        );
        await iosPlatform.dispose();
      },
    );

    test(
      'iOS: the request asks for alert and sound, not for a badge',
      () async {
        final ios = _FakeIos();
        final iosPlatform = FlutterLocalNotificationsReminderPlatform(
          plugin: _FakePlugin(ios: ios),
        );
        expect(
          await iosPlatform.requestPermission(),
          NotificationPermission.granted,
        );
        expect(ios.requested, {'sound': true, 'alert': true, 'badge': false});
        await iosPlatform.dispose();
      },
    );

    test('opening the settings reports whether something opened', () async {
      plugin.settingsOpened = true;
      expect(await platform.openSystemSettings(), isTrue);
      plugin.settingsOpened = false;
      expect(await platform.openSystemSettings(), isFalse);
      plugin.settingsOpened = null;
      expect(await platform.openSystemSettings(), isFalse);
    });
  });

  group('launch payload and taps', () {
    test('returns the payload that launched the app, once', () async {
      plugin.launchDetails = fln.NotificationAppLaunchDetails(
        true,
        notificationResponse: response('/habits'),
      );
      expect(await platform.launchPayload(), '/habits');
      expect(await platform.launchPayload(), isNull);
      expect(plugin.launchReads, 1);
    });

    test('is null when the app was not started from a notification', () async {
      plugin.launchDetails = const fln.NotificationAppLaunchDetails(false);
      expect(await platform.launchPayload(), isNull);
    });

    test('is null when the plugin has no launch details', () async {
      plugin.launchDetails = null;
      expect(await platform.launchPayload(), isNull);
    });

    test('a failed read may be repeated', () async {
      plugin.launchFailure = StateError('x');
      await expectLater(
        platform.launchPayload(),
        throwsA(isA<ReminderPlatformException>()),
      );
      plugin.launchFailure = null;
      plugin.launchDetails = fln.NotificationAppLaunchDetails(
        true,
        notificationResponse: response('/water'),
      );
      expect(await platform.launchPayload(), '/water');
    });

    test('a tap while the app runs arrives on the tap stream', () async {
      await platform.initialize();
      final taps = <String>[];
      final subscription = platform.tapStream.listen(taps.add);
      addTearDown(subscription.cancel);
      plugin.onResponse!(response('/focus/session'));
      await Future<void>.delayed(Duration.zero);
      expect(taps, ['/focus/session']);
    });

    test('a tap without payload arrives as an empty string', () async {
      await platform.initialize();
      final taps = <String>[];
      final subscription = platform.tapStream.listen(taps.add);
      addTearDown(subscription.cancel);
      plugin.onResponse!(response(null));
      await Future<void>.delayed(Duration.zero);
      expect(taps, ['']);
    });

    test('actions and dismissals are no taps', () async {
      await platform.initialize();
      final taps = <String>[];
      final subscription = platform.tapStream.listen(taps.add);
      addTearDown(subscription.cancel);
      plugin.onResponse!(
        response(
          '/water',
          type: fln.NotificationResponseType.selectedNotificationAction,
        ),
      );
      plugin.onResponse!(
        response(
          '/water',
          type: fln.NotificationResponseType.notificationDismissed,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(taps, isEmpty);
    });
  });

  group('toZonedDateTime', () {
    test('keeps the instant and shows the wall clock of the zone', () {
      final berlin = FlutterLocalNotificationsReminderPlatform.toZonedDateTime(
        DateTime.utc(2026, 3, 29, 8),
        'Europe/Berlin',
      );
      expect(berlin.toUtc(), DateTime.utc(2026, 3, 29, 8));
      expect(berlin.hour, 10, reason: 'summer time started that night');
      expect(berlin.timeZoneOffset, const Duration(hours: 2));
    });

    test('the winter wall clock differs from the summer one', () {
      final winter = FlutterLocalNotificationsReminderPlatform.toZonedDateTime(
        DateTime.utc(2026, 3, 28, 9),
        'Europe/Berlin',
      );
      expect(winter.hour, 10);
      expect(winter.timeZoneOffset, const Duration(hours: 1));
    });

    test('works in another zone', () {
      final newYork = FlutterLocalNotificationsReminderPlatform.toZonedDateTime(
        DateTime.utc(2026, 10, 4, 14),
        'America/New_York',
      );
      expect(newYork.hour, 10);
      expect(newYork.location.name, 'America/New_York');
    });

    test('an unknown zone is a failure of the schedule call', () async {
      await expectLater(
        platform.schedule(request(zone: 'Mars/Olympus')),
        throwsA(isA<ReminderPlatformException>()),
      );
      expect(plugin.scheduled, isEmpty);
    });
  });
}

/// A plugin whose every call fails like a missing native implementation.
class _ThrowingPlugin implements fln.FlutterLocalNotificationsPlugin {
  @override
  Future<void> cancel({required int id, String? tag}) async =>
      throw MissingPluginException('no implementation');

  @override
  Future<List<fln.PendingNotificationRequest>>
  pendingNotificationRequests() async =>
      throw MissingPluginException('no implementation');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
