import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Weight measurements: reads plus create/update/delete commands with undo.
///
/// This is the reference implementation of the repository pattern used by all
/// features: validation first, then the mutation, every mutation as a
/// [CommandRunner] command (atomic, idempotent), soft delete, row version
/// checks for edit and undo, frozen business date and zone.
class WeightRepository {
  WeightRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String createType = 'weight.create';
  static const String updateType = 'weight.update';
  static const String deleteType = 'weight.delete';
  static const String undoCreateType = 'weight.create.undo';
  static const String undoUpdateType = 'weight.update.undo';
  static const String undoDeleteType = 'weight.delete.undo';

  // ---------------------------------------------------------------- reads

  /// All active measurements, newest first.
  Stream<List<WeightEntry>> watchActive() {
    final query = _database.select(_database.weightEntries)
      ..where((w) => w.deletedAtUtc.isNull())
      ..orderBy([
        (w) => OrderingTerm.desc(w.occurredAtUtc),
        (w) => OrderingTerm.desc(w.id),
      ]);
    return query.watch().map((rows) => rows.map(mapWeightEntry).toList());
  }

  /// One active measurement; null if missing or deleted.
  Stream<WeightEntry?> watchById(String id) {
    final query = _database.select(_database.weightEntries)
      ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapWeightEntry(row),
    );
  }

  Future<WeightEntry?> findById(String id) async {
    final row =
        await (_database.select(_database.weightEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    return row == null ? null : mapWeightEntry(row);
  }

  /// The active measurement taken at exactly [occurredAtUtc], if any.
  Future<WeightEntry?> findActiveAt(DateTime occurredAtUtc) async {
    final row =
        await (_database.select(_database.weightEntries)..where(
              (w) =>
                  w.occurredAtUtc.equals(occurredAtUtc.millisecondsSinceEpoch) &
                  w.deletedAtUtc.isNull(),
            ))
            .getSingleOrNull();
    return row == null ? null : mapWeightEntry(row);
  }

  // ------------------------------------------------------------- commands

  /// Creates a measurement. Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required WeightDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateWeightDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        await _ensureTimeFree(input.occurredAtUtc);
        final frozen = ctx.freeze(input.occurredAtUtc);
        final id = ctx.ids.newId();
        await _database
            .into(_database.weightEntries)
            .insert(
              WeightEntriesCompanion.insert(
                id: id,
                weightGrams: input.weightGrams,
                occurredAtUtc: frozen.utc,
                localDate: frozen.localDate,
                timezoneId: frozen.timezoneId,
                beforeToilet: Value(input.beforeToilet),
                afterDrinking: Value(input.afterDrinking),
                afterEating: Value(input.afterEating),
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

  /// Edits a measurement. [expectedRowVersion] is the version the form was
  /// loaded with; a mismatch is a [ConflictFailure] (`staleVersion`).
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required WeightDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateWeightDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await _ensureTimeFree(input.occurredAtUtc, exceptId: id);

        // The frozen business date and zone only change when the measurement
        // time itself changed; editing a note never moves a record.
        final timeChanged = before.occurredAtUtc != input.occurredAtUtc;
        final frozen = ctx.freeze(input.occurredAtUtc);
        final newVersion = before.rowVersion + 1;
        await (_database.update(
          _database.weightEntries,
        )..where((w) => w.id.equals(id))).write(
          WeightEntriesCompanion(
            weightGrams: Value(input.weightGrams),
            occurredAtUtc: Value(input.occurredAtUtc),
            localDate: Value(timeChanged ? frozen.localDate : before.localDate),
            timezoneId: Value(
              timeChanged ? frozen.timezoneId : before.timezoneId,
            ),
            beforeToilet: Value(input.beforeToilet),
            afterDrinking: Value(input.afterDrinking),
            afterEating: Value(input.afterEating),
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
              previous: mapWeightEntry(before),
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes a measurement. The returned outcome carries an undo that
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
          _database.weightEntries,
        )..where((w) => w.id.equals(id))).write(
          WeightEntriesCompanion(
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
          _database.weightEntries,
        )..where((w) => w.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'weight_entry', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await _ensureTimeFree(row.occurredAtUtc, exceptId: id);
        await (_database.update(
          _database.weightEntries,
        )..where((w) => w.id.equals(id))).write(
          WeightEntriesCompanion(
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
    required WeightEntry previous,
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
        await _ensureTimeFree(previous.occurredAtUtc, exceptId: previous.id);
        await (_database.update(
          _database.weightEntries,
        )..where((w) => w.id.equals(previous.id))).write(
          WeightEntriesCompanion(
            weightGrams: Value(previous.weightGrams),
            occurredAtUtc: Value(previous.occurredAtUtc),
            localDate: Value(previous.localDate),
            timezoneId: Value(previous.timezoneId),
            beforeToilet: Value(previous.beforeToilet),
            afterDrinking: Value(previous.afterDrinking),
            afterEating: Value(previous.afterEating),
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

  Future<WeightEntryRow> _requireActive(String id) async {
    final row =
        await (_database.select(_database.weightEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw NotFoundFailure(entity: 'weight_entry', id: id);
    }
    return row;
  }

  /// A measurement time is unique among active measurements; a clash offers
  /// the existing one for editing instead of creating a duplicate.
  Future<void> _ensureTimeFree(
    DateTime occurredAtUtc, {
    String? exceptId,
  }) async {
    final existing = await findActiveAt(occurredAtUtc);
    if (existing != null && existing.id != exceptId) {
      throw ConflictFailure(
        ConflictKind.duplicateMeasurement,
        relatedEntityId: existing.id,
      );
    }
  }

  static WeightEntry mapWeightEntry(WeightEntryRow row) => WeightEntry(
    id: row.id,
    weightGrams: row.weightGrams,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    beforeToilet: row.beforeToilet,
    afterDrinking: row.afterDrinking,
    afterEating: row.afterEating,
    note: row.note,
    rowVersion: row.rowVersion,
    gamificationEligible: row.gamificationEligible,
  );
}

/// Local dates affected by a change (helper for tests and projections).
Set<LocalDate> weightDays(Iterable<WeightEntry> entries) =>
    entries.map((e) => e.localDate).toSet();
