import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/database_wipe.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/shared/local_date.dart';

/// What a committed replace did.
@immutable
final class ImportReplaceResult {
  const ImportReplaceResult({
    required this.recordCount,
    required this.recomputedDays,
  });

  /// Records written (including the two singletons).
  final int recordCount;

  /// Number of local dates whose XP awards were recomputed.
  final int recomputedDays;
}

/// Replaces the whole database content with a validated backup. Replace
/// only, never merge.
///
/// Everything happens in ONE transaction: delete all rows of all tables
/// (technical ones included), insert the imported rows with their ids and
/// timestamps exactly as in the file (soft-delete columns stay `null`), then
/// recompute the XP awards through the [ProjectionSynchronizer] for every
/// local date that has facts. Any error, in the inserts or in the projection,
/// rolls everything back and the previous data stays intact.
///
/// The caller must have validated the document first (`BackupValidator`):
/// this class trusts record-level contents and relies on the database's own
/// constraints only as the last line of defence.
final class BackupImporter {
  BackupImporter({required this._database, required this._projections});

  final AppDatabase _database;
  final ProjectionSynchronizer _projections;

  /// Replaces all data with [document]; throws on any failure (nothing is
  /// changed then).
  Future<ImportReplaceResult> replaceAll(BackupDocument document) async {
    final data = document.data;
    final days = factDays(data);
    await _database.transaction(() async {
      await DatabaseWipe.deleteAllRows(_database);
      await _insertAll(data);
      if (days.isNotEmpty) {
        await _projections.syncDays(days);
      }
    });
    return ImportReplaceResult(
      recordCount: data.recordCount,
      recomputedDays: days.length,
    );
  }

  /// The local dates that carry facts relevant to goals and XP, in ascending
  /// order: weight, step, water and workout dates, the completion dates of
  /// focus sessions and tasks, and habit check dates. Meals do not count
  /// (no goals, no XP); snapshot-only days have nothing to award, and neither
  /// do rest and skipped days (`workout_day_marks` earn no XP).
  static Set<LocalDate> factDays(BackupData data) {
    final days = <LocalDate>{
      for (final r in data.weightEntries) r.localDate,
      for (final r in data.stepDays) r.localDate,
      for (final r in data.waterEntries) r.localDate,
      for (final r in data.workoutEntries) r.localDate,
      for (final r in data.habitChecks) r.localDate,
      for (final r in data.focusSessions)
        if (r.completedLocalDate != null) r.completedLocalDate!,
      for (final r in data.tasks)
        if (r.completedLocalDate != null) r.completedLocalDate!,
    };
    return {...(days.toList()..sort())};
  }

  Future<void> _insertAll(BackupData data) async {
    final db = _database;
    // Parents before children (habits before their checks).
    await db.batch((batch) {
      batch
        ..insert(db.profile, data.profile.toCompanion())
        ..insert(db.appSettings, data.appSettings.toCompanion())
        ..insertAll(
          db.moduleStatusHistory,
          data.moduleStatusHistory.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.dashboardCards,
          data.dashboardCards.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.goalVersions,
          data.goalVersions.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.dailyGoalSnapshots,
          data.dailyGoalSnapshots.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.weightEntries,
          data.weightEntries.map((r) => r.toCompanion()),
        )
        ..insertAll(db.stepDays, data.stepDays.map((r) => r.toCompanion()))
        ..insertAll(
          db.waterEntries,
          data.waterEntries.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.mealEntries,
          data.mealEntries.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.focusSessions,
          data.focusSessions.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.workoutEntries,
          data.workoutEntries.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.workoutDayMarks,
          data.workoutDayMarks.map((r) => r.toCompanion()),
        )
        ..insertAll(db.tasks, data.tasks.map((r) => r.toCompanion()))
        ..insertAll(db.habits, data.habits.map((r) => r.toCompanion()))
        ..insertAll(
          db.habitChecks,
          data.habitChecks.map((r) => r.toCompanion()),
        )
        ..insertAll(
          db.reminderRules,
          data.reminderRules.map((r) => r.toCompanion()),
        );
    });
  }
}
