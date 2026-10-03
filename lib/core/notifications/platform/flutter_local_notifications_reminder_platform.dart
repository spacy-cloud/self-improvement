import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// [ReminderPlatform] on top of `flutter_local_notifications` (Android first,
/// iOS prepared). This is the only file of the engine that imports the plugin.
///
/// ## What it does on Android
///
/// - One notification channel `reminders` ("Erinnerungen"), created at
///   [initialize], default importance.
/// - Every notification is a one-shot `zonedSchedule` with
///   `AndroidScheduleMode.inexactAllowWhileIdle`: no exact-alarm permission,
///   no foreground service. The persistent integer id comes from the caller.
/// - Permission via `areNotificationsEnabled` (read) and
///   `requestNotificationsPermission` (the Android 13+ dialog), settings via
///   `openAppNotificationSettings`.
///
/// ## Android manifest this adapter relies on
///
/// `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, the receivers
/// `ScheduledNotificationReceiver` and `ScheduledNotificationBootReceiver`,
/// and the drawable `ic_stat_notification` (kept from resource shrinking by
/// `res/raw/keep.xml`). Without the drawable the plugin refuses to initialize.
///
/// ## Honest limits
///
/// Derived from the plugin's source and the documented behaviour of Android's
/// alarm manager; not measured on a device.
///
/// - **Inexact.** The system delivers an inexact alarm *around* the requested
///   time; in doze mode a delay of several minutes is normal.
/// - **Reboot.** The plugin keeps its pending notifications in its own
///   storage and re-registers them when the device boots or the app is
///   updated. Notifications whose time passed while the device was switched
///   off are due as soon as they are re-registered and are shown right away.
/// - **Forced stop.** When the user force-stops the app the system cancels all
///   its alarms, and the plugin's own list of pending notifications does not
///   notice. Nothing is delivered until the app is opened again; the reminder
///   service then registers everything again at the first reconcile of the
///   process.
/// - **Vendor battery savers** (some Android variants) may suppress alarms of
///   apps that are not whitelisted; this cannot be solved by the app.
///
/// The iOS branches (permission, init without a permission prompt) follow the
/// plugin's documentation but are not run in this repository's checks (no
/// macOS); the iOS app delegate setup the plugin documents is part of the
/// iOS project, not of this file.
final class FlutterLocalNotificationsReminderPlatform
    implements ReminderPlatform {
  FlutterLocalNotificationsReminderPlatform({
    fln.FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? fln.FlutterLocalNotificationsPlugin();

  /// Id of the Android notification channel.
  static const String channelId = 'reminders';

  /// Name of the monochrome status bar icon (`res/drawable`).
  static const String androidIconName = 'ic_stat_notification';

  final fln.FlutterLocalNotificationsPlugin _plugin;
  final StreamController<String> _taps = StreamController<String>.broadcast();
  Future<void>? _initialization;
  bool _launchPayloadConsumed = false;

  @override
  Stream<String> get tapStream => _taps.stream;

  @override
  Future<void> initialize() async {
    final running = _initialization;
    if (running != null) {
      return running;
    }
    final attempt = _initialize();
    _initialization = attempt;
    try {
      await attempt;
    } catch (error) {
      // A failed initialization is retried on the next call.
      _initialization = null;
      throw classify(error);
    }
  }

  Future<void> _initialize() async {
    await _plugin.initialize(
      settings: const fln.InitializationSettings(
        android: fln.AndroidInitializationSettings(androidIconName),
        // The permission is requested later, after the explanation, never at
        // initialization.
        iOS: fln.DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const fln.AndroidNotificationChannel(
        channelId,
        ReminderTexts.channelName,
        description: ReminderTexts.channelDescription,
      ),
    );
  }

  void _onResponse(fln.NotificationResponse response) {
    if (response.notificationResponseType !=
        fln.NotificationResponseType.selectedNotification) {
      return;
    }
    _taps.add(response.payload ?? '');
  }

  @override
  Future<NotificationPermission> permissionStatus() => _guarded(() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return _fromEnabled(await android.areNotificationsEnabled());
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          fln.IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final options = await ios.checkPermissions();
      return _fromEnabled(options?.isEnabled);
    }
    return NotificationPermission.unavailable;
  });

  @override
  Future<NotificationPermission> requestPermission() => _guarded(() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
      // The returned flag is not trusted: the state is read back.
      return _fromEnabled(await android.areNotificationsEnabled());
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          fln.IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      await ios.requestPermissions(alert: true, sound: true);
      final options = await ios.checkPermissions();
      return _fromEnabled(options?.isEnabled);
    }
    return NotificationPermission.unavailable;
  });

  @override
  Future<bool> openSystemSettings() => _guarded(() async {
    final opened = await _plugin.openAppNotificationSettings();
    return opened ?? false;
  });

  @override
  Future<void> schedule(PlatformScheduleRequest request) => _guarded(() async {
    await initialize();
    await _plugin.zonedSchedule(
      id: request.id,
      scheduledDate: toZonedDateTime(request.fireAtUtc, request.timeZoneId),
      notificationDetails: const fln.NotificationDetails(
        android: fln.AndroidNotificationDetails(
          channelId,
          ReminderTexts.channelName,
          channelDescription: ReminderTexts.channelDescription,
        ),
        iOS: fln.DarwinNotificationDetails(),
      ),
      androidScheduleMode: fln.AndroidScheduleMode.inexactAllowWhileIdle,
      title: request.title,
      body: request.body,
      payload: request.payload,
    );
  });

  @override
  Future<void> cancel(int notificationId) => _guarded(() async {
    await _plugin.cancel(id: notificationId);
  });

  @override
  Future<void> cancelAllPending() => _guarded(() async {
    await _plugin.cancelAllPendingNotifications();
  });

  @override
  Future<Set<int>> pendingIds() => _guarded(() async {
    final pending = await _plugin.pendingNotificationRequests();
    return {for (final request in pending) request.id};
  });

  @override
  Future<String?> launchPayload() => _guarded(() async {
    await initialize();
    if (_launchPayloadConsumed) {
      return null;
    }
    _launchPayloadConsumed = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) {
        return null;
      }
      return details.notificationResponse?.payload;
    } catch (_) {
      // Not read: a later call may try again.
      _launchPayloadConsumed = false;
      rethrow;
    }
  });

  /// Converts a UTC instant to the zoned time the plugin needs. The wall clock
  /// time is the one planned in [timeZoneId]; the plugin hands the zone name
  /// and local date time to the system, which resolves it again after a
  /// reboot.
  static tz.TZDateTime toZonedDateTime(DateTime utc, String timeZoneId) {
    assert(utc.isUtc, 'Instants must be UTC');
    return tz.TZDateTime.from(utc, TimeZones.location(timeZoneId));
  }

  /// Maps any error of the plugin to a typed failure. Messages are dropped;
  /// only the runtime type survives.
  static ReminderPlatformException classify(Object error) {
    if (error is ReminderPlatformException) {
      return error;
    }
    final causeType = error.runtimeType.toString();
    if (error is ArgumentError && error.name == 'scheduledDate') {
      // The plugin refuses a time that is not in the future any more.
      return ReminderPlatformException(
        PlatformFailureKind.timeInPast,
        causeType: causeType,
      );
    }
    if (error is PlatformException &&
        error.code == 'exact_alarms_not_permitted') {
      return ReminderPlatformException(
        PlatformFailureKind.permissionMissing,
        causeType: causeType,
      );
    }
    return ReminderPlatformException(
      PlatformFailureKind.failed,
      causeType: causeType,
    );
  }

  static NotificationPermission _fromEnabled(bool? enabled) =>
      switch (enabled) {
        true => NotificationPermission.granted,
        false => NotificationPermission.denied,
        null => NotificationPermission.unavailable,
      };

  Future<T> _guarded<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (error) {
      throw classify(error);
    }
  }

  /// Releases the tap stream.
  Future<void> dispose() => _taps.close();
}
