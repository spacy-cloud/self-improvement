import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';

/// Everything the operating system needs to show one notification later.
@immutable
final class PlatformScheduleRequest {
  const PlatformScheduleRequest({
    required this.id,
    required this.fireAtUtc,
    required this.timeZoneId,
    required this.title,
    required this.payload,
    this.body,
  });

  /// The persistent positive integer id. Scheduling again with the same id
  /// replaces the earlier notification (the call is idempotent per id).
  final int id;

  /// When to show it (UTC instant).
  final DateTime fireAtUtc;

  /// The IANA zone the time was planned in; adapters that need a zoned time
  /// build it from [fireAtUtc] in this zone.
  final String timeZoneId;

  /// Neutral German title.
  final String title;

  /// Optional body; the V1 notifications only have a title.
  final String? body;

  /// A known in-app route, see `NotificationRoutes`. Never health values or
  /// user text.
  final String payload;

  @override
  String toString() => 'PlatformScheduleRequest(#$id at $fireAtUtc)';
}

/// How a platform call failed.
enum PlatformFailureKind {
  /// The system refused because notifications are not permitted.
  permissionMissing,

  /// The requested time is not in the future any more (the clock moved on
  /// while the run was busy). Nothing was scheduled; this is not a fault.
  timeInPast,

  /// The platform call failed for any other reason.
  failed,
}

/// A typed platform failure. It never carries the platform's message because
/// such messages can contain values; only the kind and the runtime type of the
/// cause are kept.
final class ReminderPlatformException implements Exception {
  const ReminderPlatformException(this.kind, {this.causeType});

  final PlatformFailureKind kind;

  /// Runtime type name of the underlying error, for logs.
  final String? causeType;

  @override
  String toString() => 'ReminderPlatformException(${kind.name}, $causeType)';
}

/// The seam between the reminder engine and the operating system.
///
/// The domain, the planner and the service only know this interface, so a
/// later iOS adapter implements the same methods without any change above it.
/// The shipped Android adapter is `FlutterLocalNotificationsReminderPlatform`;
/// tests use `FakeReminderPlatform`.
///
/// All methods may throw; the reminder service catches everything and reports
/// a typed status, so a platform failure never reaches a business command.
abstract interface class ReminderPlatform {
  /// Prepares the platform (channels, tap callbacks). Idempotent. The app
  /// shell calls it once at start, before the first frame, so a tap on a
  /// notification is delivered; every other method also works without it.
  Future<void> initialize();

  /// Reads whether the system lets the app post notifications. Never shows a
  /// dialog.
  Future<NotificationPermission> permissionStatus();

  /// Shows the system permission dialog (where the platform has one) and
  /// returns the resulting state. Call it only after the user switched
  /// reminders on and after an explanation was shown.
  Future<NotificationPermission> requestPermission();

  /// Opens the notification settings of this app in the system settings.
  /// Returns false when no settings screen could be opened.
  Future<bool> openSystemSettings();

  /// Hands one notification to the system, or replaces the one with the same
  /// id. Throws [ReminderPlatformException] on failure.
  Future<void> schedule(PlatformScheduleRequest request);

  /// Cancels the pending notification [notificationId]. This also removes an
  /// already delivered notification with that id from the notification shade,
  /// so the service only calls it for ids that are still pending or in the
  /// future.
  Future<void> cancel(int notificationId);

  /// Cancels every pending (scheduled, not yet delivered) notification.
  /// Notifications already visible in the shade stay.
  Future<void> cancelAllPending();

  /// The ids the system still has as pending. May be stale after the system
  /// dropped alarms on its own (a forced stop of the app).
  Future<Set<int>> pendingIds();

  /// The payload of the notification that launched the app, at most once per
  /// process (the second call returns `null`). `null` when the app was not
  /// started from a notification. The app shell consumes it after bootstrap
  /// and onboarding, see `NotificationRouteResolver`.
  Future<String?> launchPayload();

  /// Payloads of notifications the user taps while the app process is alive.
  Stream<String> get tapStream;
}
