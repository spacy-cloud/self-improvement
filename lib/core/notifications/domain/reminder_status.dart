import 'package:flutter/foundation.dart';

/// Whether the operating system currently lets the app post notifications.
///
/// The value is always read from the device. It is never stored in the
/// database and never exported or imported: the database only keeps the
/// *wish* of the user (`app_settings.notifications_enabled`).
enum NotificationPermission {
  /// Notifications are allowed.
  granted,

  /// Notifications are not allowed. On Android this covers "never asked",
  /// "refused" and "blocked in the system settings"; the platform cannot tell
  /// these apart. Once the user has asked for reminders the UI shows this as
  /// blocked ("Im System blockiert") and offers the system settings.
  denied,

  /// The platform offers no notifications or the state could not be read.
  unavailable,
}

/// Category of the last problem while planning or handing reminders to the
/// operating system. Carries no message because platform messages can contain
/// values; only the category is shown or logged.
enum ReminderErrorCategory {
  /// The system refused because the notification permission is missing.
  permission,

  /// The platform plugin failed (channel error, missing plugin, ...).
  platform,

  /// The local database failed while reading inputs or writing the projection
  /// of planned notifications.
  storage,

  /// Anything unexpected, e.g. an unknown time zone id.
  unknown,
}

/// The overall state of the reminder feature as the settings screen shows it.
enum ReminderState {
  /// The user did not ask for reminders (default).
  off,

  /// Reminders are wanted but the system does not allow notifications. The
  /// settings screen shows "Im System blockiert" and the system settings.
  blocked,

  /// Reminders are wanted but the platform cannot show notifications.
  unavailable,

  /// Reminders are wanted and allowed but the last scheduling run failed
  /// ("Planungsfehler"); the screen offers a retry.
  schedulingError,

  /// Reminders are wanted, allowed and planned.
  active,
}

/// Typed result of a reconcile run: everything the settings screen needs to
/// describe the reminder feature honestly.
@immutable
final class ReminderStatus {
  const ReminderStatus({
    required this.wanted,
    required this.permission,
    required this.scheduledCount,
    this.lastError,
    this.failedCount = 0,
    this.planLimitReached = false,
    this.nextFireAtUtc,
  });

  /// The desired state: the master switch of the user.
  final bool wanted;

  /// The real permission as read from the device in this run.
  final NotificationPermission permission;

  /// Number of notifications handed to the operating system (rows of the
  /// planned-notification projection).
  final int scheduledCount;

  /// Category of the most recent failure of the latest run; `null` when the
  /// latest run completed without a failure, so a successful retry clears it.
  final ReminderErrorCategory? lastError;

  /// How many individual notifications failed in the latest run.
  final int failedCount;

  /// True when more reminders were due within the horizon than the global cap
  /// allows; the rest is planned on a later start. The UI documents this.
  final bool planLimitReached;

  /// When the next planned notification is due; `null` if none is planned.
  final DateTime? nextFireAtUtc;

  /// Derived overall state.
  ReminderState get state {
    if (!wanted) {
      return ReminderState.off;
    }
    return switch (permission) {
      NotificationPermission.denied => ReminderState.blocked,
      NotificationPermission.unavailable => ReminderState.unavailable,
      NotificationPermission.granted =>
        lastError == null
            ? ReminderState.active
            : ReminderState.schedulingError,
    };
  }

  /// Convenience: reminders are wanted but blocked by the system.
  bool get isBlocked => state == ReminderState.blocked;

  /// Convenience: the settings screen should offer "Wiederholen".
  bool get canRetry => state == ReminderState.schedulingError;

  @override
  bool operator ==(Object other) =>
      other is ReminderStatus &&
      other.wanted == wanted &&
      other.permission == permission &&
      other.scheduledCount == scheduledCount &&
      other.lastError == lastError &&
      other.failedCount == failedCount &&
      other.planLimitReached == planLimitReached &&
      other.nextFireAtUtc == nextFireAtUtc;

  @override
  int get hashCode => Object.hash(
    wanted,
    permission,
    scheduledCount,
    lastError,
    failedCount,
    planLimitReached,
    nextFireAtUtc,
  );

  @override
  String toString() =>
      'ReminderStatus($state, permission: ${permission.name}, '
      'scheduled: $scheduledCount, error: ${lastError?.name})';
}
