import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_importer.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// The backup facade for the UI: export, share, validate, preview, replace.
///
/// Typical flow of the export screen: show the privacy notice, then
/// [exportBackup], then [shareBackup]. Flow of the import screen: pick a file
/// (`BackupFilePicker`), [prepareImport], show the preview or the problems,
/// and only after the user confirmed "Vorhandene App-Daten ersetzen":
/// [confirmImport].
///
/// Failures are [AppFailure]s: [UnsupportedBackupFailure] for a rejected file
/// (see [ImportRejected.failure]) and [StorageFailure] for anything that went
/// wrong while reading or writing data. Logs contain only error types, never
/// values.
final class BackupService {
  BackupService({
    required AppDatabase database,
    required ClockService clock,
    required this._files,
    required ProjectionSynchronizer projections,
    this._notifications = const NoopNotificationCanceller(),
    this._listener = const NoopBackupListener(),
    SnapshotConsistencyChecker? snapshotChecker,
  }) : _validator = BackupValidator(snapshotChecker: snapshotChecker),
       _importer = BackupImporter(
         database: database,
         projections: projections,
       ) {
    _exporter = BackupExporter(
      database: database,
      clock: clock,
      validator: _validator,
    );
  }

  final BackupFileGateway _files;
  final NotificationCanceller _notifications;
  final BackupListener _listener;
  final BackupValidator _validator;
  final BackupImporter _importer;
  late final BackupExporter _exporter;

  /// Creates a backup of the current data and writes it to a temporary file
  /// in the cache directory. Nothing is shared or uploaded yet; the data in
  /// the database is not changed. The result carries the file [ExportedBackup.path]
  /// and tells whether this app would accept the file again
  /// ([ExportedBackup.isRestorable]).
  Future<ExportedBackup> exportBackup() async {
    try {
      final backup = await _exporter.export();
      final path = await _files.writeTemporaryExport(
        fileName: backup.fileName,
        bytes: backup.bytes,
      );
      return backup.withPath(path);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw _storageFailure('export', error);
    }
  }

  /// Opens the system share sheet for [backup]. Sharing may be cancelled
  /// (the result says so); that never changes data. Afterwards the temporary
  /// file is deleted, whatever happened.
  Future<BackupShareStatus> shareBackup(ExportedBackup backup) async {
    final path = backup.path;
    if (path == null) {
      throw _storageFailure('share', StateError('backup has no file'));
    }
    try {
      return await _files.shareExport(path);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw _storageFailure('share', error);
    } finally {
      await runFollowUp(
        'delete temporary exports',
        _files.deleteTemporaryExports,
      );
    }
  }

  /// Removes leftover temporary export files (including copies made by the
  /// platform's share mechanism). Call once at app start. Never throws;
  /// returns whether the cleanup worked.
  Future<bool> cleanUpTemporaryExports() => runFollowUp(
    'clean up temporary exports',
    () => _files.deleteTemporaryExports(includePlatformShareCopies: true),
  );

  /// Validates [bytes] completely and without any side effect. Returns the
  /// preview to confirm, or the list of problems.
  Future<ImportPreparation> prepareImport(Uint8List bytes) async {
    try {
      final result = _validator.validateBytes(bytes);
      final document = result.document;
      return document == null
          ? ImportRejected(result.report)
          : ImportReady(PreparedImport(document));
    } on Object catch (error) {
      throw _storageFailure('validate', error);
    }
  }

  /// Replaces ALL app data with the prepared backup in one transaction and
  /// recomputes the XP awards. Call only after the user confirmed.
  ///
  /// On any error nothing is changed and a [StorageFailure] is thrown. After
  /// the commit the OS notifications are cancelled and the [BackupListener] is
  /// told (providers, reminder planning); failures of those follow-ups do not
  /// undo the import and show up in the [ImportOutcome].
  Future<ImportOutcome> confirmImport(PreparedImport prepared) async {
    final ImportReplaceResult result;
    try {
      result = await _importer.replaceAll(prepared.document);
    } on AppFailure {
      rethrow;
    } on Object catch (error) {
      throw _storageFailure('import', error);
    }
    final cancelled = await runFollowUp(
      'cancel notifications',
      _notifications.cancelAllNotifications,
    );
    final notified = await runFollowUp('listener', _listener.onDataReplaced);
    return ImportOutcome(
      recordCount: result.recordCount,
      recomputedDays: result.recomputedDays,
      notificationsCancelled: cancelled,
      listenerNotified: notified,
    );
  }

  StorageFailure _storageFailure(String operation, Object error) {
    // Log only the type: messages of storage errors can contain values.
    debugPrint('backup $operation failed: ${error.runtimeType}');
    return StorageFailure(causeType: error.runtimeType.toString());
  }
}
