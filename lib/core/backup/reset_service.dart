import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/database_wipe.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/bootstrap/local_data_seeder.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// What a committed reset did.
@immutable
final class ResetOutcome {
  const ResetOutcome({
    required this.notificationsCancelled,
    required this.temporaryFilesDeleted,
    required this.listenerNotified,
  });

  /// The OS notifications were cancelled. `false` means the data is gone but
  /// old reminders may still fire until the app cancels them.
  final bool notificationsCancelled;

  /// Leftover temporary export files (which contain personal data) were
  /// removed from the cache.
  final bool temporaryFilesDeleted;

  /// The app listener ran (providers invalidated).
  final bool listenerNotified;

  bool get followUpSucceeded =>
      notificationsCancelled && temporaryFilesDeleted && listenerNotified;
}

/// "Alle App-Daten löschen": the explicit, complete deletion of the app's
/// data (BS-77).
///
/// One transaction deletes every row of every table (technical ones
/// included) and re-creates the two singleton rows through the existing
/// [LocalDataSeeder], so the next start shows a fresh onboarding. After the
/// commit the OS notifications are cancelled, leftover temporary export files
/// are removed and the [BackupListener] is told. A failure of any of these
/// follow-ups does NOT undo the reset (the data is gone for good once the
/// transaction committed) and is reported in the [ResetOutcome].
///
/// This class stops nothing by itself: running timers and tickers live in the
/// UI layer and end when the providers are invalidated by the listener (the
/// focus session rows are deleted here, which is what makes "the timer is
/// gone" true in the data).
///
/// A reset is NEVER triggered implicitly: not by deactivating a module, not
/// by a migration or database error ([MigrationFailure] never deletes), not
/// by a rejected or failed import. The only way to run it is calling
/// [resetAllData] with the typed confirmation.
final class ResetService {
  ResetService({
    required this._database,
    required this._clock,
    required this._notifications,
    this._listener = const NoopBackupListener(),
    this._files,
  });

  /// The word the user must type to confirm a reset.
  static const String confirmationPhrase = 'LÖSCHEN';

  /// Whether [input] confirms a reset: the phrase, ignoring case and
  /// surrounding spaces.
  static bool isConfirmation(String input) =>
      input.trim().toUpperCase() == confirmationPhrase;

  final AppDatabase _database;
  final ClockService _clock;
  final NotificationCanceller _notifications;
  final BackupListener _listener;
  final BackupFileGateway? _files;

  /// Deletes all app data. Throws [ValidationFailure] if [confirmation] does
  /// not match [confirmationPhrase] (nothing is changed), and
  /// [StorageFailure] if the deletion failed (the transaction rolled back,
  /// the data is intact).
  Future<ResetOutcome> resetAllData({required String confirmation}) async {
    if (!isConfirmation(confirmation)) {
      throw ValidationFailure.field(
        'confirmation',
        'Bitte gib zur Bestätigung „$confirmationPhrase“ ein.',
      );
    }
    try {
      await _database.transaction(() async {
        await DatabaseWipe.deleteAllRows(_database);
        await LocalDataSeeder(
          database: _database,
          clock: _clock,
        ).ensureSingletons();
      });
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      debugPrint('reset failed: ${error.runtimeType}');
      throw StorageFailure(causeType: error.runtimeType.toString());
    }

    final cancelled = await runFollowUp(
      'cancel notifications',
      _notifications.cancelAllNotifications,
    );
    final files = _files;
    final filesDeleted = files == null
        ? true
        : await runFollowUp(
            'delete temporary exports',
            () =>
                files.deleteTemporaryExports(includePlatformShareCopies: true),
          );
    final notified = await runFollowUp('listener', _listener.onDataReplaced);
    return ResetOutcome(
      notificationsCancelled: cancelled,
      temporaryFilesDeleted: filesDeleted,
      listenerNotified: notified,
    );
  }
}
