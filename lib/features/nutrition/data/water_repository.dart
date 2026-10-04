import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_context.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/reactive.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Water entries: reads (reactive day and history models) plus the
/// quick add, create, update and delete commands with undo.
///
/// Follows the weight reference: validation first, every mutation is a
/// [CommandRunner] command (atomic, idempotent), soft delete, row version
/// checks for edit and undo, business date and zone frozen at the event, the
/// affected days reported for the projection (snapshots and XP). Unlike
/// weights, water entries have no uniqueness rule: two drinks at the same
/// instant are two entries.
class WaterRepository {
  WaterRepository({
    required this._database,
    required this._runner,
    required this._snapshots,
    required this._goalVersions,
  });

  final AppDatabase _database;
  final CommandRunner _runner;
  final GoalSnapshotService _snapshots;
  final GoalVersionRepository _goalVersions;

  static const String createType = 'water.create';
  static const String quickAddType = 'water.quick_add';
  static const String updateType = 'water.update';
  static const String deleteType = 'water.delete';
  static const String undoCreateType = 'water.create.undo';
  static const String undoUpdateType = 'water.update.undo';
  static const String undoDeleteType = 'water.delete.undo';

  // ---------------------------------------------------------------- reads

  /// One active entry; null if missing or deleted.
  Stream<WaterEntry?> watchById(String id) {
    final query = _database.select(_database.waterEntries)
      ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapWaterEntry(row),
    );
  }

  Future<WaterEntry?> findById(String id) async {
    final row =
        await (_database.select(_database.waterEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    return row == null ? null : mapWaterEntry(row);
  }

  /// The tables a day or history model depends on: the entries plus
  /// everything that decides the day's target.
  List<ResultSetImplementation<dynamic, dynamic>> get _modelTables => [
    _database.waterEntries,
    _database.dailyGoalSnapshots,
    _database.goalVersions,
    _database.moduleStatusHistory,
    _database.profile,
  ];

  /// The model of [today], re-emitted whenever an entry, a goal, a snapshot or
  /// the module status changes. Equal consecutive models are not repeated.
  Stream<WaterToday> watchToday(LocalDate today) =>
      watchComputed(_database, _modelTables, () => loadToday(today)).distinct();

  /// The model of [today] now.
  Future<WaterToday> loadToday(LocalDate today) async {
    final rows =
        await (_database.select(_database.waterEntries)..where(
              (w) => w.localDate.equalsValue(today) & w.deletedAtUtc.isNull(),
            ))
            .get();
    final targets = await _targetsFor({today});
    return buildWaterToday(
      date: today,
      entries: rows.map(mapWaterEntry),
      targetMl: targets[today],
    );
  }

  /// The entries of the last [days] local days (including [today]) grouped per
  /// day, newest first, re-emitted on every relevant change.
  Stream<WaterHistory> watchHistory({
    required LocalDate today,
    required int days,
  }) => watchComputed(
    _database,
    _modelTables,
    () => loadHistory(today: today, days: days),
  ).distinct();

  /// The history of the last [days] local days now. Days without an entry do
  /// not appear. Entries stored with a later local date than [today] (possible
  /// after travelling west) are included, so every entry stays reachable for
  /// editing.
  Future<WaterHistory> loadHistory({
    required LocalDate today,
    required int days,
  }) async {
    if (days < 1) {
      throw ArgumentError.value(days, 'days', 'must be at least 1');
    }
    final from = today.addDays(-(days - 1));
    final rows =
        await (_database.select(_database.waterEntries)..where(
              (w) =>
                  w.localDate.isBiggerOrEqualValue(from.toIso()) &
                  w.deletedAtUtc.isNull(),
            ))
            .get();
    final entries = rows.map(mapWaterEntry).toList();
    final targets = await _targetsFor({
      for (final entry in entries) entry.localDate,
    });
    return buildWaterHistory(
      days: days,
      entries: entries,
      targetFor: (day) => targets[day],
    );
  }

  /// The threshold of each of [days] in ml (null: no water goal applied that
  /// day): the frozen snapshot target when one exists, otherwise the goal
  /// version in effect (see [resolveWaterTarget]).
  Future<Map<LocalDate, int?>> _targetsFor(Set<LocalDate> days) async {
    if (days.isEmpty) {
      return const {};
    }
    final sorted = days.toList()..sort();
    final snapshots = await _snapshots.snapshotsBetween(
      sorted.first,
      sorted.last,
    );
    final versions = await _goalVersions.all();
    final moduleRows = await _database
        .select(_database.moduleStatusHistory)
        .get();
    final profile = await _database.select(_database.profile).getSingleOrNull();
    return {
      for (final day in sorted)
        day: resolveWaterTarget(
          day: day,
          snapshot: snapshots[day],
          versions: versions,
          nutritionEnabledOnDay:
              ModuleStatusRepository.statusesFromHistory(
                moduleRows,
                day,
              )[ModuleId.nutrition] ??
              true,
          profileStart: profile?.startedLocalDate,
        ),
    };
  }

  // ------------------------------------------------------------- commands

  /// One-tap add: creates a real entry of [amountMl] at the current time
  /// within ONE command. A new tap uses a new [commandId]; retrying the same
  /// [commandId] never duplicates.
  Future<CommandOutcome> quickAdd({
    required String commandId,
    required int amountMl,
  }) {
    return _runner.run(
      commandId: commandId,
      type: quickAddType,
      body: (ctx) async {
        final input = validateWaterDraft(
          WaterDraft(amountMl: amountMl, occurredAtUtc: ctx.nowUtc),
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        return _insert(ctx, input);
      },
    );
  }

  /// Creates an entry with an explicit time (the "Eigene Menge" form).
  /// Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required WaterDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateWaterDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        return _insert(ctx, input);
      },
    );
  }

  /// Edits an entry. [expectedRowVersion] is the version the form was loaded
  /// with; a mismatch is a [ConflictFailure] (`staleVersion`).
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required WaterDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateWaterDraft(
          draft,
          nowUtc: ctx.nowUtc,
          clock: ctx.clock,
        );
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }

        // The frozen business date and zone only change when the time itself
        // changed; editing the amount or note never moves a record.
        final timeChanged = before.occurredAtUtc != input.occurredAtUtc;
        final frozen = ctx.freeze(input.occurredAtUtc);
        final newVersion = before.rowVersion + 1;
        await (_database.update(
          _database.waterEntries,
        )..where((w) => w.id.equals(id))).write(
          WaterEntriesCompanion(
            amountMl: Value(input.amountMl),
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
              previous: mapWaterEntry(before),
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes an entry. The returned outcome carries an undo that
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

  Future<CommandEffect> _insert(CommandContext ctx, WaterDraft input) async {
    final frozen = ctx.freeze(input.occurredAtUtc);
    final id = ctx.ids.newId();
    await _database
        .into(_database.waterEntries)
        .insert(
          WaterEntriesCompanion.insert(
            id: id,
            amountMl: input.amountMl,
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
  }

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
          _database.waterEntries,
        )..where((w) => w.id.equals(id))).write(
          WaterEntriesCompanion(
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
          _database.waterEntries,
        )..where((w) => w.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'water_entry', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.waterEntries,
        )..where((w) => w.id.equals(id))).write(
          WaterEntriesCompanion(
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
    required WaterEntry previous,
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
          _database.waterEntries,
        )..where((w) => w.id.equals(previous.id))).write(
          WaterEntriesCompanion(
            amountMl: Value(previous.amountMl),
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

  Future<WaterEntryRow> _requireActive(String id) async {
    final row =
        await (_database.select(_database.waterEntries)
              ..where((w) => w.id.equals(id) & w.deletedAtUtc.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw NotFoundFailure(entity: 'water_entry', id: id);
    }
    return row;
  }

  static WaterEntry mapWaterEntry(WaterEntryRow row) => WaterEntry(
    id: row.id,
    amountMl: row.amountMl,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    createdAtUtc: row.createdAtUtc,
    note: row.note,
    rowVersion: row.rowVersion,
    gamificationEligible: row.gamificationEligible,
  );
}
