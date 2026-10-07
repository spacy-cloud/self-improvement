import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/user_profile.dart';

/// What the user sees before confirming "replace existing data".
@immutable
final class ImportPreview {
  const ImportPreview({
    required this.profileName,
    required this.hasProfileName,
    required this.exportedAtUtc,
    required this.appVersion,
    required this.counts,
    required this.schemaVersion,
  });

  /// The preview of a validated [document].
  factory ImportPreview.of(BackupDocument document) {
    final name = document.data.profile.displayName;
    return ImportPreview(
      profileName: name ?? UserProfile.defaultName,
      hasProfileName: name != null,
      exportedAtUtc: document.exportedAtUtc,
      appVersion: document.appVersion,
      counts: Map<BackupTable, int>.unmodifiable(document.data.counts),
      schemaVersion: document.sourceSchemaVersion,
    );
  }

  /// The profile's display name, or the app's default name ("Mein Profil")
  /// when the backup has none.
  final String profileName;

  /// Whether [profileName] is the real name from the file.
  final bool hasProfileName;

  /// When the backup was created (UTC; show it in the device zone).
  final DateTime exportedAtUtc;

  /// App version that wrote the file.
  final String appVersion;

  /// Number of records per section (profile and settings count 1 each).
  final Map<BackupTable, int> counts;

  /// The format version of the FILE (not of this app): a file of an older
  /// version is read through an upward step and shows its own version here.
  final int schemaVersion;

  /// Total number of records.
  int get totalRecords => counts.values.fold(0, (sum, count) => sum + count);

  /// The records of the business sections, i.e. everything except the
  /// profile and settings singletons, for a "N Einträge" line.
  int get entryCount =>
      totalRecords -
      (counts[BackupTable.profile] ?? 0) -
      (counts[BackupTable.appSettings] ?? 0);
}

/// A validated file, ready to be confirmed. Only the backup service creates
/// these from validated files; confirming it replaces all app data.
@immutable
final class PreparedImport {
  PreparedImport(this.document) : preview = ImportPreview.of(document);

  final BackupDocument document;
  final ImportPreview preview;
}

/// Result of preparing an import: either a preview to confirm, or the list
/// of problems. Preparing never changes any data.
@immutable
sealed class ImportPreparation {
  const ImportPreparation();
}

/// The file is valid: show [preview], then call `confirmImport(prepared)`.
final class ImportReady extends ImportPreparation {
  const ImportReady(this.prepared);

  final PreparedImport prepared;

  ImportPreview get preview => prepared.preview;
}

/// The file was rejected; existing data is untouched.
final class ImportRejected extends ImportPreparation {
  const ImportRejected(this.report);

  final ImportValidationReport report;

  /// The rejection as the app-wide failure type (`unsupported_backup`) with
  /// a German reason that names the first problem.
  UnsupportedBackupFailure get failure =>
      UnsupportedBackupFailure(report.summary);
}

/// What a committed import did, for the UI's confirmation message.
@immutable
final class ImportOutcome {
  const ImportOutcome({
    required this.recordCount,
    required this.recomputedDays,
    required this.notificationsCancelled,
    required this.listenerNotified,
  });

  /// Records written (including profile and settings).
  final int recordCount;

  /// Local dates whose XP awards were recomputed.
  final int recomputedDays;

  /// The OS notifications were cancelled. `false` means the data is imported
  /// but old reminders may still fire until they are re-planned.
  final bool notificationsCancelled;

  /// The app listener ran (providers invalidated, reminders re-planned).
  final bool listenerNotified;

  /// Everything that follows the commit worked.
  bool get followUpSucceeded => notificationsCancelled && listenerNotified;
}
