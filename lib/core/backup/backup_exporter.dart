import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_codec.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/dto/body_nutrition_dtos.dart';
import 'package:self_improvement/core/backup/dto/core_dtos.dart';
import 'package:self_improvement/core/backup/dto/focus_dtos.dart';
import 'package:self_improvement/core/backup/dto/task_dtos.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// A created backup: the file content and its name.
@immutable
final class ExportedBackup {
  const ExportedBackup({
    required this.fileName,
    required this.bytes,
    required this.exportedAtUtc,
    required this.counts,
    required this.importCheck,
    this.path,
  });

  /// `self-improvement-backup-YYYY-MM-DD-HHmm.json` (local time of export).
  final String fileName;

  /// UTF-8 JSON.
  final Uint8List bytes;

  /// When the backup was created (the `exportedAtUtc` of the file).
  final DateTime exportedAtUtc;

  /// Records per section.
  final Map<BackupTable, int> counts;

  /// Result of running the import validation over [bytes]. A backup the app
  /// would refuse to import again (for example because it exceeds the import
  /// limits) is still created, but flagged here so the UI can warn instead of
  /// the user finding out at restore time.
  final ImportValidationReport importCheck;

  /// Location of the temporary file, set once a file gateway wrote it.
  final String? path;

  /// Whether this app would accept the file in an import.
  bool get isRestorable => importCheck.isValid;

  int get recordCount => counts.values.fold(0, (sum, count) => sum + count);

  /// Same backup with the temporary file [path].
  ExportedBackup withPath(String path) => ExportedBackup(
    fileName: fileName,
    bytes: bytes,
    exportedAtUtc: exportedAtUtc,
    counts: counts,
    importCheck: importCheck,
    path: path,
  );
}

/// Creates a backup of the live database.
///
/// Reads ONE consistent snapshot: every table is read inside a single
/// database transaction, so the app's own writes (which the database
/// serialises) cannot interleave. Only ACTIVE business records are exported;
/// soft-deleted rows, `xp_awards`, `command_receipts` and
/// `scheduled_notifications` never are. A `running` focus session is written
/// as `paused` with its duration computed at export time; the live row stays
/// running.
///
/// Rows are ordered by their business time and id, so identical data yields a
/// byte-identical file.
final class BackupExporter {
  BackupExporter({
    required this._database,
    required this._clock,
    this._validator = const BackupValidator(),
    this._appVersion = AppConfig.appVersion,
  });

  final AppDatabase _database;
  final ClockService _clock;
  final BackupValidator _validator;
  final String _appVersion;

  /// Creates the backup file content. Throws if the database cannot be read
  /// (callers map that to a `StorageFailure`).
  Future<ExportedBackup> export() async {
    final nowUtc = _clock.nowUtc();
    final document = await readDocument(nowUtc);
    final bytes = BackupCodec.encode(document);
    return ExportedBackup(
      fileName: BackupFileName.forInstant(_clock, nowUtc),
      bytes: bytes,
      exportedAtUtc: document.exportedAtUtc,
      counts: document.data.counts,
      importCheck: _validator.validateBytes(bytes).report,
    );
  }

  /// Reads the database into a document as of [nowUtc] (one transaction).
  Future<BackupDocument> readDocument(DateTime nowUtc) {
    final db = _database;
    return db.transaction(() async {
      final profile = await db.select(db.profile).getSingleOrNull();
      final settings = await db.select(db.appSettings).getSingleOrNull();
      if (profile == null || settings == null) {
        throw StateError('singleton rows are missing');
      }

      final moduleStatus =
          await (db.select(db.moduleStatusHistory)..orderBy([
                (t) => OrderingTerm.asc(t.effectiveAtUtc),
                (t) => OrderingTerm.asc(t.id),
              ]))
              .get();
      final cards =
          await (db.select(db.dashboardCards)..orderBy([
                (t) => OrderingTerm.asc(t.sortIndex),
                (t) => OrderingTerm.asc(t.cardId),
              ]))
              .get();
      final goals =
          await (db.select(db.goalVersions)..orderBy([
                (t) => OrderingTerm.asc(t.effectiveFromDate),
                (t) => OrderingTerm.asc(t.goalType),
                (t) => OrderingTerm.asc(t.id),
              ]))
              .get();
      final snapshots =
          await (db.select(db.dailyGoalSnapshots)..orderBy([
                (t) => OrderingTerm.asc(t.localDate),
                (t) => OrderingTerm.asc(t.goalKey),
                (t) => OrderingTerm.asc(t.id),
              ]))
              .get();
      final weights =
          await (db.select(db.weightEntries)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.occurredAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final steps =
          await (db.select(db.stepDays)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.localDate),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final water =
          await (db.select(db.waterEntries)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.occurredAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final meals =
          await (db.select(db.mealEntries)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.occurredAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final focus =
          await (db.select(db.focusSessions)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.startedAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final workouts =
          await (db.select(db.workoutEntries)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.occurredAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final tasks =
          await (db.select(db.tasks)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.createdAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final habits =
          await (db.select(db.habits)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.createdAtUtc),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final checks =
          await (db.select(db.habitChecks)
                ..where((t) => t.deletedAtUtc.isNull())
                ..orderBy([
                  (t) => OrderingTerm.asc(t.localDate),
                  (t) => OrderingTerm.asc(t.habitId),
                  (t) => OrderingTerm.asc(t.id),
                ]))
              .get();
      final rules = await (db.select(
        db.reminderRules,
      )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

      // Checks of a deleted habit are not active business records: without
      // their habit they would break the foreign key on import.
      final habitIds = {for (final habit in habits) habit.id};

      return BackupDocument(
        exportedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          nowUtc.millisecondsSinceEpoch,
          isUtc: true,
        ),
        appVersion: _appVersion,
        data: BackupData(
          profile: ProfileDto.fromRow(profile),
          appSettings: AppSettingsDto.fromRow(settings),
          moduleStatusHistory: moduleStatus
              .map(ModuleStatusDto.fromRow)
              .toList(),
          dashboardCards: cards.map(DashboardCardDto.fromRow).toList(),
          goalVersions: goals.map(GoalVersionDto.fromRow).toList(),
          dailyGoalSnapshots: snapshots
              .map(DailyGoalSnapshotDto.fromRow)
              .toList(),
          weightEntries: weights.map(WeightEntryDto.fromRow).toList(),
          stepDays: steps.map(StepDayDto.fromRow).toList(),
          waterEntries: water.map(WaterEntryDto.fromRow).toList(),
          mealEntries: meals.map(MealEntryDto.fromRow).toList(),
          focusSessions: [
            for (final row in focus)
              FocusSessionDto.fromRow(row).exportedAt(nowUtc),
          ],
          workoutEntries: workouts.map(WorkoutEntryDto.fromRow).toList(),
          tasks: tasks.map(TaskDto.fromRow).toList(),
          habits: habits.map(HabitDto.fromRow).toList(),
          habitChecks: [
            for (final row in checks)
              if (habitIds.contains(row.habitId)) HabitCheckDto.fromRow(row),
          ],
          reminderRules: rules.map(ReminderRuleDto.fromRow).toList(),
        ),
      );
    });
  }
}
