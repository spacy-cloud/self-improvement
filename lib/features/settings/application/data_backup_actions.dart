import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/settings/application/data_backup_rules.dart';

/// Result of creating the backup file.
sealed class ExportCreation {
  const ExportCreation();
}

/// The file exists in the cache folder; nothing was shared yet.
final class ExportCreated extends ExportCreation {
  const ExportCreated(this.backup);

  final ExportedBackup backup;

  /// Number of the user's entries in the file.
  int get entryCount => userEntryCount(backup.counts);
}

/// The data could not be read or the file not written. Nothing changed.
final class ExportCreationFailed extends ExportCreation {
  const ExportCreationFailed(this.failure);

  final AppFailure failure;
}

/// Result of handing the file to the system share sheet.
sealed class ExportSharing {
  const ExportSharing();
}

/// The share sheet was shown and closed; [status] tells how.
final class ExportShared extends ExportSharing {
  const ExportShared(this.status);

  final BackupShareStatus status;
}

/// The share sheet could not be opened. No data changed.
final class ExportSharingFailed extends ExportSharing {
  const ExportSharingFailed(this.failure);

  final AppFailure failure;
}

/// Result of picking and checking an import file. Nothing is ever changed by
/// this step.
sealed class ImportPick {
  const ImportPick();
}

/// The user closed the file picker without choosing.
final class ImportPickCancelled extends ImportPick {
  const ImportPickCancelled();
}

/// The picker or the check failed technically (not a bad file: a bad file is
/// [ImportPickRejected]).
final class ImportPickUnreadable extends ImportPick {
  const ImportPickUnreadable();
}

/// The file is valid: show the preview, then confirm.
final class ImportPickReady extends ImportPick {
  const ImportPickReady(this.prepared, this.fileName);

  final PreparedImport prepared;

  /// For display only; never logged (it can contain a name).
  final String fileName;
}

/// The file was rejected with readable [report] problems.
final class ImportPickRejected extends ImportPick {
  const ImportPickRejected(this.report, this.fileName);

  final ImportValidationReport report;
  final String fileName;
}

/// Result of replacing the data.
sealed class ImportCommit {
  const ImportCommit();
}

/// The data of the file replaced the existing data.
final class ImportCommitted extends ImportCommit {
  const ImportCommitted(this.outcome);

  final ImportOutcome outcome;
}

/// Nothing was replaced; the existing data is intact.
final class ImportCommitFailed extends ImportCommit {
  const ImportCommitFailed(this.failure);

  final AppFailure failure;
}

/// Result of the reset.
sealed class ResetResult {
  const ResetResult();
}

/// All data was deleted and the singletons re-created.
final class ResetDone extends ResetResult {
  const ResetDone(this.outcome);

  final ResetOutcome outcome;
}

/// Nothing was deleted (wrong phrase or storage failure).
final class ResetFailed extends ResetResult {
  const ResetFailed(this.failure);

  final AppFailure failure;
}

/// The operations of "Daten & Sicherung" as one small facade over the backup
/// engine. It adds no rules of its own except the strict reset phrase, turns
/// every failure into a typed result and logs nothing but error types.
///
/// The screen holds the busy state (and with it the lock against a second
/// tap); every method here is a single awaited unit of work.
class DataBackupActions {
  DataBackupActions({
    required this._service,
    required this._picker,
    required this._reset,
  });

  final BackupService _service;
  final BackupFilePicker _picker;
  final ResetService _reset;

  /// Creates the backup file in the cache folder. Nothing is shared.
  Future<ExportCreation> createBackup() async {
    try {
      return ExportCreated(await _service.exportBackup());
    } on AppFailure catch (failure) {
      return ExportCreationFailed(failure);
    }
  }

  /// Opens the system share sheet for [backup]. The temporary file is deleted
  /// afterwards, whatever happened.
  Future<ExportSharing> shareBackup(ExportedBackup backup) async {
    try {
      return ExportShared(await _service.shareBackup(backup));
    } on AppFailure catch (failure) {
      return ExportSharingFailed(failure);
    }
  }

  /// Removes an export the user decided not to share. Never throws.
  Future<void> discardExport() => _service.cleanUpTemporaryExports();

  /// Lets the user pick a file and validates it completely. Changes nothing.
  Future<ImportPick> pickImportFile() async {
    final PickedBackupFile? file;
    try {
      file = await _picker.pickBackupFile();
    } on Object catch (error) {
      // Only the type: the message of a file system error can hold a path.
      debugPrint('backup file picker failed: ${error.runtimeType}');
      return const ImportPickUnreadable();
    }
    if (file == null) {
      return const ImportPickCancelled();
    }
    try {
      final preparation = await _service.prepareImport(file.bytes);
      return switch (preparation) {
        ImportReady(:final prepared) => ImportPickReady(prepared, file.name),
        ImportRejected(:final report) => ImportPickRejected(report, file.name),
      };
    } on AppFailure {
      return const ImportPickUnreadable();
    }
  }

  /// Replaces all data with the prepared file in one transaction. The caller
  /// has the user's explicit confirmation.
  Future<ImportCommit> confirmImport(PreparedImport prepared) async {
    try {
      return ImportCommitted(await _service.confirmImport(prepared));
    } on AppFailure catch (failure) {
      return ImportCommitFailed(failure);
    }
  }

  /// Deletes all data. [typed] is the text the user typed; the call is only
  /// made when it is exactly [ResetPhrase.text].
  Future<ResetResult> resetAll(String typed) async {
    if (!ResetPhrase.matches(typed)) {
      return ResetFailed(
        ValidationFailure.field(
          'confirmation',
          'Bitte gib zur Bestätigung „${ResetPhrase.text}“ ein.',
        ),
      );
    }
    try {
      return ResetDone(await _reset.resetAllData(confirmation: typed));
    } on AppFailure catch (failure) {
      return ResetFailed(failure);
    }
  }
}

/// The backup operations of the data screen.
final dataBackupActionsProvider = Provider<DataBackupActions>(
  (ref) => DataBackupActions(
    service: ref.watch(backupServiceProvider),
    picker: ref.watch(backupFilePickerProvider),
    reset: ref.watch(resetServiceProvider),
  ),
);

/// The number of the user's entries in the current data, for "N Einträge
/// werden ersetzt/gelöscht". An error means the number is simply left out of
/// the text: the warning stays true without it.
final currentEntryCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final clock = ref.watch(clockProvider);
  final exporter = BackupExporter(
    database: ref.watch(appDatabaseProvider),
    clock: clock,
  );
  final document = await exporter.readDocument(clock.nowUtc());
  return userEntryCount(document.data.counts);
});
