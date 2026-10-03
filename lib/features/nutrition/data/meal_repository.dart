import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Meals with optional calories: reads (day and history models with the
/// calorie summary) plus the create, update and delete commands with undo.
///
/// Follows the weight reference: validation first, every mutation is a
/// [CommandRunner] command (atomic, idempotent), soft delete, row version
/// checks for edit and undo, business date and zone frozen at the event.
///
/// Meals earn no XP and have no goal. The affected days are still reported to
/// the projection so that it stays the single place that decides this; for
/// meals the synchronisation is a cheap no-op for XP.
class MealRepository {
  MealRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String createType = 'meal.create';
  static const String updateType = 'meal.update';
  static const String deleteType = 'meal.delete';
  static const String undoCreateType = 'meal.create.undo';
  static const String undoUpdateType = 'meal.update.undo';
  static const String undoDeleteType = 'meal.delete.undo';

  // ---------------------------------------------------------------- reads

  /// One active meal; null if missing or deleted.
  Stream<MealEntry?> watchById(String id) {
    final query = _database.select(_database.mealEntries)
      ..where((m) => m.id.equals(id) & m.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapMealEntry(row),
    );
  }

  Future<MealEntry?> findById(String id) async {
    final row =
        await (_database.select(_database.mealEntries)
              ..where((m) => m.id.equals(id) & m.deletedAtUtc.isNull()))
            .getSingleOrNull();
    return row == null ? null : mapMealEntry(row);
  }

  /// The meals of [day] with their calorie summary, re-emitted on every
  /// change. Equal consecutive models are not repeated.
  Stream<MealDay> watchDay(LocalDate day) {
    final query = _database.select(_database.mealEntries)
      ..where((m) => m.localDate.equalsValue(day) & m.deletedAtUtc.isNull());
    return query
        .watch()
        .map((rows) => buildMealDay(date: day, entries: rows.map(mapMealEntry)))
        .distinct();
  }

  /// The meals of the last [days] local days (including [today]) grouped per
  /// day, newest first, re-emitted on every change. Days without a meal do
  /// not appear. Meals stored with a later local date than [today] (possible
  /// after travelling west) are included, so every meal stays reachable for
  /// editing.
  Stream<MealHistory> watchHistory({
    required LocalDate today,
    required int days,
  }) {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'must be at least 1');
    }
    final from = today.addDays(-(days - 1));
    final query = _database.select(_database.mealEntries)
      ..where(
        (m) =>
            m.localDate.isBiggerOrEqualValue(from.toIso()) &
            m.deletedAtUtc.isNull(),
      );
    return query
        .watch()
        .map(
          (rows) =>
              buildMealHistory(days: days, entries: rows.map(mapMealEntry)),
        )
        .distinct();
  }

  /// The active meals of the local days `[from, to]` (inclusive), newest
  /// first. For period summaries (see `summarizeMeals`).
  Future<List<MealEntry>> findBetween(LocalDate from, LocalDate to) async {
    final rows =
        await (_database.select(_database.mealEntries)..where(
              (m) =>
                  m.localDate.isBetweenValues(from.toIso(), to.toIso()) &
                  m.deletedAtUtc.isNull(),
            ))
            .get();
    return rows.map(mapMealEntry).toList()..sort(compareMealNewestFirst);
  }

  // ------------------------------------------------------------- commands

  /// Creates a meal. Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required MealDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateMealDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final frozen = ctx.freeze(input.occurredAtUtc);
        final id = ctx.ids.newId();
        await _database
            .into(_database.mealEntries)
            .insert(
              MealEntriesCompanion.insert(
                id: id,
                name: input.name,
                kcal: Value(input.kcal),
                occurredAtUtc: frozen.utc,
                localDate: frozen.localDate,
                timezoneId: frozen.timezoneId,
                note: Value(input.note),
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

  /// Edits a meal. [expectedRowVersion] is the version the form was loaded
  /// with; a mismatch is a [ConflictFailure] (`staleVersion`).
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required MealDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateMealDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }

        // The frozen business date and zone only change when the time itself
        // changed; editing the name or note never moves a record.
        final timeChanged = before.occurredAtUtc != input.occurredAtUtc;
        final frozen = ctx.freeze(input.occurredAtUtc);
        final newVersion = before.rowVersion + 1;
        await (_database.update(
          _database.mealEntries,
        )..where((m) => m.id.equals(id))).write(
          MealEntriesCompanion(
            name: Value(input.name),
            kcal: Value(input.kcal),
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
              previous: mapMealEntry(before),
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes a meal. The returned outcome carries an undo that restores
  /// the SAME id.
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
          _database.mealEntries,
        )..where((m) => m.id.equals(id))).write(
          MealEntriesCompanion(
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
          _database.mealEntries,
        )..where((m) => m.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'meal_entry', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.mealEntries,
        )..where((m) => m.id.equals(id))).write(
          MealEntriesCompanion(
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
    required MealEntry previous,
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
          _database.mealEntries,
        )..where((m) => m.id.equals(previous.id))).write(
          MealEntriesCompanion(
            name: Value(previous.name),
            kcal: Value(previous.kcal),
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

  Future<MealEntryRow> _requireActive(String id) async {
    final row =
        await (_database.select(_database.mealEntries)
              ..where((m) => m.id.equals(id) & m.deletedAtUtc.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw NotFoundFailure(entity: 'meal_entry', id: id);
    }
    return row;
  }

  static MealEntry mapMealEntry(MealEntryRow row) => MealEntry(
    id: row.id,
    name: row.name,
    kcal: row.kcal,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    createdAtUtc: row.createdAtUtc,
    note: row.note,
    rowVersion: row.rowVersion,
  );
}
