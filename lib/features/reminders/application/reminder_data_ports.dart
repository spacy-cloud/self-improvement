import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';

/// Cancels every notification the operating system still holds after the
/// data was replaced by an import or deleted by a reset.
///
/// Both operations wipe the table of planned notifications, so the system
/// side must follow, otherwise reminders of the old data would still fire.
/// Plug it into the backup engine with
/// `notificationCancellerProvider.overrideWith((ref) =>
/// ref.watch(reminderNotificationCancellerProvider))`.
final class ReminderNotificationCanceller implements NotificationCanceller {
  const ReminderNotificationCanceller(this._platform);

  final ReminderPlatform _platform;

  @override
  Future<void> cancelAllNotifications() => _platform.cancelAllPending();
}

/// Plans the reminders again after the data was replaced as a whole. After an
/// import the new reminder rules and the wish of the file apply; after a reset
/// nothing is wanted any more and nothing gets planned.
///
/// `ReminderService.reconcile` never throws, so this listener only fails when
/// the service was disposed.
final class ReminderReplanListener implements BackupListener {
  const ReminderReplanListener(this._service);

  final ReminderService _service;

  @override
  Future<void> onDataReplaced() async {
    await _service.reconcile();
  }
}

/// Runs several [BackupListener]s one after the other. Every listener runs
/// even when an earlier one failed; if any failed, the first error is thrown
/// afterwards so that the backup engine reports the follow-up as failed.
///
/// The app root composes its own invalidations with the reminder replanning:
/// `CompositeBackupListener([myInvalidation, ref.watch(reminderReplanListenerProvider)])`.
final class CompositeBackupListener implements BackupListener {
  const CompositeBackupListener(this._listeners);

  final List<BackupListener> _listeners;

  @override
  Future<void> onDataReplaced() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final listener in _listeners) {
      try {
        await listener.onDataReplaced();
      } on Object catch (error, stack) {
        debugPrint('backup listener failed: ${error.runtimeType}');
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }
}

/// The real [NotificationCanceller] for the backup engine.
final reminderNotificationCancellerProvider = Provider<NotificationCanceller>(
  (ref) => ReminderNotificationCanceller(ref.watch(reminderPlatformProvider)),
);

/// The reminder part of the "data was replaced" listener.
final reminderReplanListenerProvider = Provider<BackupListener>(
  (ref) => ReminderReplanListener(ref.watch(reminderServiceProvider)),
);
