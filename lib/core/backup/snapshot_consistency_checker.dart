import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';

/// Extension point: checks the daily goal snapshots of a backup against the
/// goal, module and habit history of the same file.
///
/// The validator already guarantees that every record is well formed and that
/// ids, foreign keys and unique keys hold. What it deliberately does NOT know
/// is the goal domain: which goals were applicable on a given day given the
/// goal versions, the module status history and the habit dates. A contradicting
/// snapshot (for example a water goal marked applicable on a day when the
/// nutrition module was off) must reject the file; that rule belongs to the
/// goal domain and is plugged in through this interface.
///
/// Contract for implementations:
/// - pure and synchronous: no I/O, no clock, no database access;
/// - called only when the file is otherwise valid, so the lists in [BackupData]
///   have exactly the positions of the records in the file;
/// - return one [ImportProblem] per contradicting record, built with
///   [ImportProblem.record] (`BackupTable.dailyGoalSnapshots`, the list index,
///   a German message without personal data), or an empty list when the
///   snapshots are consistent;
/// - never throw for file content: a thrown error aborts validation and is
///   reported as a storage failure.
///
/// Without a checker (the default) snapshots are imported as they are.
abstract interface class SnapshotConsistencyChecker {
  List<ImportProblem> check(BackupData data);
}
