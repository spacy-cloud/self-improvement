import 'package:flutter/foundation.dart';

/// Called by the backup engine AFTER the database content was replaced as a
/// whole and the transaction committed (a successful import, or a reset).
///
/// The app implements it to invalidate providers that cache data and to
/// re-plan reminders from the new rules. It must tolerate being called with
/// completely different data than before. A failure here never undoes the
/// replace; the engine only reports it.
abstract interface class BackupListener {
  Future<void> onDataReplaced();
}

/// A listener that does nothing (tests, early wiring).
final class NoopBackupListener implements BackupListener {
  const NoopBackupListener();

  @override
  Future<void> onDataReplaced() async {}
}

/// Cancels every notification the app has scheduled with the operating
/// system. Called after the commit of an import or a reset; the table
/// `scheduled_notifications` is wiped by both, so the OS side must follow.
/// Cancelling must be idempotent.
abstract interface class NotificationCanceller {
  Future<void> cancelAllNotifications();
}

/// A canceller that does nothing (tests, early wiring).
final class NoopNotificationCanceller implements NotificationCanceller {
  const NoopNotificationCanceller();

  @override
  Future<void> cancelAllNotifications() async {}
}

/// Runs a step that follows a committed change. It never throws: a failing
/// follow-up must not make a committed import or reset look like it failed.
/// Returns whether the step succeeded; logs only the error type (error
/// messages can contain values).
Future<bool> runFollowUp(String name, Future<void> Function() step) async {
  try {
    await step();
    return true;
  } on Object catch (error) {
    debugPrint('backup follow-up "$name" failed: ${error.runtimeType}');
    return false;
  }
}
