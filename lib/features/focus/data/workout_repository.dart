import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Manual workouts: reads plus create/update/delete commands with undo.
///
/// Same pattern as the weight reference: validation first, every mutation a
/// [CommandRunner] command (atomic, idempotent), soft delete, row version
/// checks for edit and undo, business date and zone frozen with
/// `ctx.freeze`, the affected days reported for the XP projection (15 XP once
/// per day for the first eligible workout; the projection decides).
///
/// Workouts are never focus time: nothing here touches `focus_sessions`.
class WorkoutRepository {
  WorkoutRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String createType = 'workout.create';
  static const String updateType = 'workout.update';
  static const String deleteType = 'workout.delete';
  static const String undoCreateType = 'workout.create.undo';
  static const String undoUpdateType = 'workout.update.undo';
  static const String undoDeleteType = 'workout.delete.undo';

  // ---------------------------------------------------------------- reads

  /// All active workouts, newest first ("Alle Trainings"). [limit] and
  /// [offset] allow a lazy, paged list.
  Stream<List<WorkoutEntry>> watchActive({int? limit, int offset = 0}) {
    return _activeQuery(
      limit: limit,
      offset: offset,
    ).watch().map((rows) => rows.map(mapWorkoutEntry).toList());
  }

  /// One page of the active workouts, newest first.
  Future<List<WorkoutEntry>> fetchPage({
    required int limit,
    int offset = 0,
  }) async {
    final rows = await _activeQuery(limit: limit, offset: offset).get();
    return rows.map(mapWorkoutEntry).toList();
  }

  /// The active workouts whose frozen local date lies in `[from, to]`
  /// (inclusive), newest first.
  Stream<List<WorkoutEntry>> watchBetween(LocalDate from, LocalDate to) {
    final query = _database.select(_database.workoutEntries)
      ..where(
        (w) =>
            w.deletedAtUtc.isNull() &
            w.localDate.isBiggerOrEqualValue(from.toIso()) &
            w.localDate.isSmallerOrEqualValue(to.toIso()),
      )
      ..orderBy([
        (w) => OrderingTerm.desc(w.occurredAtUtc),
        (w) => OrderingTerm.desc(w.id),
      ]);
    return query.watch().map((rows) => rows.map(mapWorkoutEntry).toList());
  }

  /// One active workout; null if missing or deleted.
  Stream<WorkoutEntry?> watchById(String id) {
    final query = _database.select(_database.workoutEntries)
      ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapWorkoutEntry(row),
    );
  }

  Future<WorkoutEntry?> findById(String id) async {
    final row =
        await (_database.select(_database.workoutEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    return row == null ? null : mapWorkoutEntry(row);
  }

  SimpleSelectStatement<$WorkoutEntriesTable, WorkoutEntryRow> _activeQuery({
    int? limit,
    int offset = 0,
  }) {
    final query = _database.select(_database.workoutEntries)
      ..where((w) => w.deletedAtUtc.isNull())
      ..orderBy([
        (w) => OrderingTerm.desc(w.occurredAtUtc),
        (w) => OrderingTerm.desc(w.id),
      ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query;
  }

  // ------------------------------------------------------------- commands

  /// Creates a workout. Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required WorkoutDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateWorkoutDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final frozen = ctx.freeze(input.occurredAtUtc);
        final id = ctx.ids.newId();
        await _database
            .into(_database.workoutEntries)
            .insert(
              WorkoutEntriesCompanion.insert(
                id: id,
                trainingCategory: input.category.key,
                title: Value(input.title),
                durationMinutes: input.durationMinutes,
                muscleGroups: Value(_keys(input.muscleGroups)),
                intensity: Value(input.intensity?.key),
                occurredAtUtc: frozen.utc,
                localDate: frozen.localDate,
                timezoneId: frozen.timezoneId,
                note: Value(input.note),
                gamificationEligible: await ctx.isGamificationEnabled(),
                createdAtUtc: ctx.nowUtc,
                updatedAtUtc: ctx.nowUtc,
              ),
            );
        return CommandEffect(
          entityId: id,
          affectedDays: {frozen.localDate},
          undo: UndoAction(
            run: (undoId) => _softDelete(
              commandId: undoId,
              id: id,
              expectedRowVersion: 1,
              type: undoCreateType,
            ),
          ),
        );
      },
    );
  }

  /// Edits a workout. [expectedRowVersion] is the version the form was loaded
  /// with; a mismatch is a `ConflictFailure(staleVersion)`.
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required WorkoutDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateWorkoutDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }

        // The frozen business date and zone only change when the workout time
        // itself changed; editing the title never moves a record.
        final timeChanged = before.occurredAtUtc != input.occurredAtUtc;
        final frozen = ctx.freeze(input.occurredAtUtc);
        final newVersion = before.rowVersion + 1;
        await (_database.update(
          _database.workoutEntries,
        )..where((w) => w.id.equals(id))).write(
          WorkoutEntriesCompanion(
            trainingCategory: Value(input.category.key),
            title: Value(input.title),
            durationMinutes: Value(input.durationMinutes),
            muscleGroups: Value(_keys(input.muscleGroups)),
            intensity: Value(input.intensity?.key),
            occurredAtUtc: Value(input.occurredAtUtc),
            localDate: Value(timeChanged ? frozen.localDate : before.localDate),
            timezoneId: Value(
              timeChanged ? frozen.timezoneId : before.timezoneId,
            ),
            note: Value(input.note),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {before.localDate, if (timeChanged) frozen.localDate},
          undo: UndoAction(
            run: (undoId) => _restoreValues(
              commandId: undoId,
              previous: mapWorkoutEntry(before),
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes a workout. The returned outcome carries an undo that
  /// restores the SAME id.
  Future<CommandOutcome> delete({
    required String commandId,
    required String id,
  }) {
    return _softDelete(
      commandId: commandId,
      id: id,
      expectedRowVersion: null,
      type: deleteType,
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
        final row = await _requireActive(id);
        if (expectedRowVersion != null &&
            row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        final newVersion = row.rowVersion + 1;
        await (_database.update(
          _database.workoutEntries,
        )..where((w) => w.id.equals(id))).write(
          WorkoutEntriesCompanion(
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
      type: undoDeleteType,
      body: (ctx) async {
        final row = await (_database.select(
          _database.workoutEntries,
        )..where((w) => w.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'workout_entry', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.workoutEntries,
        )..where((w) => w.id.equals(id))).write(
          WorkoutEntriesCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(entityId: id, affectedDays: {row.localDate});
      },
    );
  }

  Future<CommandOutcome> _restoreValues({
    required String commandId,
    required WorkoutEntry previous,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: undoUpdateType,
      body: (ctx) async {
        final current = await _requireActive(previous.id);
        if (current.rowVersion != expectedRowVersion) {
          throw ConflictFailure(
            ConflictKind.staleVersion,
            relatedEntityId: previous.id,
          );
        }
        await (_database.update(
          _database.workoutEntries,
        )..where((w) => w.id.equals(previous.id))).write(
          WorkoutEntriesCompanion(
            trainingCategory: Value(previous.category.key),
            title: Value(previous.title),
            durationMinutes: Value(previous.durationMinutes),
            muscleGroups: Value(_keys(previous.muscleGroups)),
            intensity: Value(previous.intensity?.key),
            occurredAtUtc: Value(previous.occurredAtUtc),
            localDate: Value(previous.localDate),
            timezoneId: Value(previous.timezoneId),
            note: Value(previous.note),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(current.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: previous.id,
          affectedDays: {current.localDate, previous.localDate},
        );
      },
    );
  }

  Future<WorkoutEntryRow> _requireActive(String id) async {
    final row =
        await (_database.select(_database.workoutEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw NotFoundFailure(entity: 'workout_entry', id: id);
    }
    return row;
  }

  static List<String> _keys(Iterable<MuscleGroup> groups) => [
    for (final group in groups) group.key,
  ];

  static WorkoutEntry mapWorkoutEntry(WorkoutEntryRow row) => WorkoutEntry(
    id: row.id,
    category: TrainingCategory.fromKey(row.trainingCategory),
    title: row.title,
    durationMinutes: row.durationMinutes,
    muscleGroups: MuscleGroup.fromKeys(row.muscleGroups),
    intensity: row.intensity == null
        ? null
        : WorkoutIntensity.tryParse(row.intensity!),
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    note: row.note,
    rowVersion: row.rowVersion,
    gamificationEligible: row.gamificationEligible,
  );
}
