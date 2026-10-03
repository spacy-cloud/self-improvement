import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/backup/platform/backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/file_selector_backup_file_picker.dart';
import 'package:self_improvement/core/backup/platform/share_plus_backup_file_gateway.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// Temporary export files and the system share sheet. Overridden with an
/// in-memory fake in tests.
final backupFileGatewayProvider = Provider<BackupFileGateway>(
  (ref) => SharePlusBackupFileGateway(),
);

/// The system file picker for imports. Overridden with a fake in tests.
final backupFilePickerProvider = Provider<BackupFilePicker>(
  (ref) => FileSelectorBackupFilePicker(),
);

/// Cancels the OS notifications after an import or a reset. The default does
/// nothing; the reminder feature overrides it with the real implementation.
final notificationCancellerProvider = Provider<NotificationCanceller>(
  (ref) => const NoopNotificationCanceller(),
);

/// Told after the data was replaced as a whole (import or reset): the app
/// invalidates cached providers and re-plans reminders here. The default does
/// nothing; the app root overrides it.
final backupListenerProvider = Provider<BackupListener>(
  (ref) => const NoopBackupListener(),
);

/// Optional cross-check of the daily goal snapshots of an imported file
/// against the goal, module and habit history. `null` (the default) accepts
/// snapshots as they are; the goal feature overrides it.
final snapshotConsistencyCheckerProvider =
    Provider<SnapshotConsistencyChecker?>((ref) => null);

/// Export, share, validate, preview and replace (BS-73).
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    files: ref.watch(backupFileGatewayProvider),
    projections: ref.watch(projectionSynchronizerProvider),
    notifications: ref.watch(notificationCancellerProvider),
    listener: ref.watch(backupListenerProvider),
    snapshotChecker: ref.watch(snapshotConsistencyCheckerProvider),
  ),
);

/// "Alle App-Daten löschen" (BS-77).
final resetServiceProvider = Provider<ResetService>(
  (ref) => ResetService(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    notifications: ref.watch(notificationCancellerProvider),
    listener: ref.watch(backupListenerProvider),
    files: ref.watch(backupFileGatewayProvider),
  ),
);
