import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Rest days and skipped days (BS-99): at most ONE active mark per local day.
///
/// The same command pattern as the manual steps: every mutation is a
/// [CommandRunner] command (atomic, idempotent, `affectedDays` for the goal
/// snapshot of the day), soft delete, row version checks for the undo, the
/// business day and the zone frozen when the mark was set.
///
/// A mark fulfils the optional daily goal "Workout heute" and keeps the streak,
/// but it never earns XP: nothing here touches the XP projection (the XP rules
/// know workouts, focus sessions and the like, not marks).
class WorkoutDayMarkRepository {
  WorkoutDayMarkRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String markType = 'workout_day.mark';
  static const String unmarkType = 'workout_day.unmark';
  static const String undoMarkType = 'workout_day.mark.undo';
  static const String undoUnmarkType = 'workout_day.unmark.undo';

  // ---------------------------------------------------------------- reads

  /// The active mark of [date], or null; follows every change.
  Stream<WorkoutDayMark?> watchDay(LocalDate date) =>
      (_database.select(_database.workoutDayMarks)..where(
            (m) => m.localDate.equalsValue(date) & m.deletedAtUtc.isNull(),
          ))
          .watchSingleOrNull()
          .map((row) => row == null ? null : mapMark(row));

  /// The active mark of [date], or null.
  Future<WorkoutDayMark?> findDay(LocalDate date) async {
    final row = await _activeRow(date);
    return row == null ? null : mapMark(row);
  }

  // ------------------------------------------------------------- commands

  /// Marks [date] (default: today in the zone of the device) as [kind].
  ///
  /// A second mark for a day that already has an active one is a
  /// `ConflictFailure(invalidState)` that names the existing mark: taking it
  /// back first is the way to choose again. A day in the future cannot be
  /// marked. Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> mark({
    required String commandId,
    required WorkoutDayMarkKind kind,
    LocalDate? date,
  }) {
    return _runner.run(
      commandId: commandId,
      type: markType,
      body: (ctx) async {
        final day = date ?? ctx.today;
        if (day.isAfter(ctx.today)) {
          throw ValidationFailure.field(
            'date',
            'Für einen Tag in der Zukunft kannst du noch nichts eintragen.',
          );
        }
        final existing = await _activeRow(day);
        if (existing != null) {
          throw ConflictFailure(
            ConflictKind.invalidState,
            relatedEntityId: existing.id,
          );
        }
        final id = ctx.ids.newId();
        await _database
            .into(_database.workoutDayMarks)
            .insert(
              WorkoutDayMarksCompanion.insert(
                id: id,
                localDate: day,
                kind: kind.key,
                timezoneId: ctx.timeZoneId,
                createdAtUtc: ctx.nowUtc,
                updatedAtUtc: ctx.nowUtc,
              ),
            );
        return CommandEffect(
          entityId: id,
          affectedDays: {day},
          undo: UndoAction(
            run: (undoId) => _softDelete(
              commandId: undoId,
              id: id,
              expectedRowVersion: 1,
              type: undoMarkType,
            ),
          ),
        );
      },
    );
  }

  /// Takes the mark [id] back (soft delete). The day is open again, the goal
  /// no longer counts it. The returned outcome carries an undo that restores
  /// the SAME mark, unless another one was set for the day meanwhile.
  Future<CommandOutcome> unmark({
    required String commandId,
    required String id,
  }) {
    return _softDelete(
      commandId: commandId,
      id: id,
      expectedRowVersion: null,
      type: unmarkType,
    );
  }

  // -------------------------------------------------------------- helpers

  Future<CommandOutcome> _softDelete({
    required String commandId,
    required String id,
    required int? expectedRowVersion,
    required String type,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row =
            await (_database.select(_database.workoutDayMarks)
                  ..where((m) => m.id.equals(id) & m.deletedAtUtc.isNull()))
                .getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'workout_day_mark', id: id);
        }
        if (expectedRowVersion != null &&
            row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        final newVersion = row.rowVersion + 1;
        await (_database.update(
          _database.workoutDayMarks,
        )..where((m) => m.id.equals(id))).write(
          WorkoutDayMarksCompanion(
            deletedAtUtc: Value(ctx.nowUtc),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {row.localDate},
          kind: EffectKind.removed,
          undo: UndoAction(
            run: (undoId) => _restoreDeleted(
              commandId: undoId,
              id: id,
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  Future<CommandOutcome> _restoreDeleted({
    required String commandId,
    required String id,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: undoUnmarkType,
      body: (ctx) async {
        final row = await (_database.select(
          _database.workoutDayMarks,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'workout_day_mark', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        // Check before writing: the unique index would reject a second active
        // mark, and a database error is not a conflict the user can read.
        final other = await _activeRow(row.localDate);
        if (other != null) {
          // The day was marked again meanwhile: keep that newer mark.
          throw ConflictFailure(
            ConflictKind.staleVersion,
            relatedEntityId: other.id,
          );
        }
        await (_database.update(
          _database.workoutDayMarks,
        )..where((m) => m.id.equals(id))).write(
          WorkoutDayMarksCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(entityId: id, affectedDays: {row.localDate});
      },
    );
  }

  Future<WorkoutDayMarkRow?> _activeRow(LocalDate date) =>
      (_database.select(_database.workoutDayMarks)..where(
            (m) => m.localDate.equalsValue(date) & m.deletedAtUtc.isNull(),
          ))
          .getSingleOrNull();

  /// Maps a row; a row with an unknown kind (impossible by CHECK) is skipped
  /// by callers.
  static WorkoutDayMark? mapMark(WorkoutDayMarkRow row) {
    final kind = WorkoutDayMarkKind.tryParse(row.kind);
    if (kind == null) {
      return null;
    }
    return WorkoutDayMark(
      id: row.id,
      date: row.localDate,
      kind: kind,
      timezoneId: row.timezoneId,
      rowVersion: row.rowVersion,
    );
  }
}
