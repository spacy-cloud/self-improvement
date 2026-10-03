import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Daily habits and their checks: reads plus create/update/check/archive/delete
/// commands with undo.
///
/// Same pattern as the weight repository: validation first, every mutation a
/// [CommandRunner] command (atomic, idempotent), soft delete, row version
/// checks for edit and undo, frozen business date and zone, and the affected
/// days reported to the projection (a retroactive check syncs ITS day).
///
/// Rules (specification 9.2):
/// - a habit starts on the day it is created and is a daily goal from then on;
/// - one check per habit and day (a unique index that includes soft-deleted
///   rows): checking creates the row or REACTIVATES the soft-deleted row of
///   that day; unchecking soft-deletes it;
/// - checks are allowed from the start day up to today, at most 30 days back,
///   never in the future and never on or after the archive date;
/// - archiving works from TOMORROW; archived habits keep their checks and are
///   never reactivated (a new habit gets a new id).
class HabitRepository {
  HabitRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String createType = 'habit.create';
  static const String updateType = 'habit.update';
  static const String archiveType = 'habit.archive';
  static const String deleteType = 'habit.delete';
  static const String checkType = 'habit.check';
  static const String uncheckType = 'habit.uncheck';
  static const String undoCreateType = 'habit.create.undo';
  static const String undoUpdateType = 'habit.update.undo';
  static const String undoDeleteType = 'habit.delete.undo';
  static const String undoCheckType = 'habit.check.undo';
  static const String undoUncheckType = 'habit.uncheck.undo';

  // ---------------------------------------------------------------- reads

  /// All existing (not deleted) habits, archived ones included, oldest first.
  Stream<List<Habit>> watchAll() {
    final query = _database.select(_database.habits)
      ..where((h) => h.deletedAtUtc.isNull())
      ..orderBy([
        (h) => OrderingTerm.asc(h.createdAtUtc),
        (h) => OrderingTerm.asc(h.id),
      ]);
    return query.watch().map((rows) => rows.map(mapHabit).toList());
  }

  /// One existing habit (archived ones too); emits null when it is missing or
  /// deleted.
  Stream<Habit?> watchById(String id) {
    final query = _database.select(_database.habits)
      ..where((h) => h.id.equals(id) & h.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapHabit(row),
    );
  }

  Future<Habit?> findById(String id) async {
    final row = await _activeHabit(id);
    return row == null ? null : mapHabit(row);
  }

  /// The active checks of all existing habits. Checks of deleted habits and
  /// soft-deleted checks are excluded, like in the XP and day fact queries.
  Stream<HabitCheckIndex> watchChecks() {
    final query =
        _database.select(_database.habitChecks).join([
          innerJoin(
            _database.habits,
            _database.habits.id.equalsExp(_database.habitChecks.habitId),
          ),
        ])..where(
          _database.habitChecks.deletedAtUtc.isNull() &
              _database.habits.deletedAtUtc.isNull(),
        );
    return query.watch().map((rows) {
      final byHabit = <String, Set<LocalDate>>{};
      for (final row in rows) {
        final check = row.readTable(_database.habitChecks);
        byHabit
            .putIfAbsent(check.habitId, () => <LocalDate>{})
            .add(check.localDate);
      }
      return HabitCheckIndex(byHabit);
    });
  }

  /// The active check of [habitId] on [date], or null.
  Future<HabitCheck?> findCheck(String habitId, LocalDate date) async {
    final row = await _checkRow(habitId, date);
    return row == null || row.deletedAtUtc != null ? null : _mapCheck(row);
  }

  // ------------------------------------------------------------- commands

  /// Creates a habit that starts today (the day is frozen at creation).
  /// Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required HabitDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateHabitDraft(draft);
        final id = ctx.ids.newId();
        await _database
            .into(_database.habits)
            .insert(
              HabitsCompanion.insert(
                id: id,
                title: input.title,
                startedLocalDate: ctx.today,
                iconKey: Value(input.iconKey),
                reminderLocalTime: Value(input.reminderTime),
                createdAtUtc: ctx.nowUtc,
                updatedAtUtc: ctx.nowUtc,
              ),
            );
        // Today's goal snapshot gains the new habit goal.
        return CommandEffect(
          entityId: id,
          affectedDays: {ctx.today},
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

  /// Edits title, icon and reminder time. NEVER rewrites history: the start
  /// day, the archive date and all checks stay as they are.
  /// [expectedRowVersion] is the version the form was loaded with; a mismatch
  /// is a [ConflictFailure] (`staleVersion`).
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required HabitDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateHabitDraft(draft);
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        final newVersion = before.rowVersion + 1;
        await _writeContent(
          id,
          title: input.title,
          iconKey: input.iconKey,
          reminderTime: input.reminderTime,
          now: ctx.nowUtc,
          rowVersion: newVersion,
        );
        // Title, icon and reminder are not facts: no projection day.
        return CommandEffect(
          entityId: id,
          undo: UndoAction(
            run: (undoId) => _restoreContent(
              commandId: undoId,
              previous: before,
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Sets the check of [habitId] on [date] to the DESIRED state.
  ///
  /// - Checking creates the check, or REACTIVATES the soft-deleted row of that
  ///   day with a fresh `checked_at_utc` and a fresh eligibility flag from the
  ///   current gamification state: there is always exactly one row per habit
  ///   and day.
  /// - Unchecking soft-deletes the check.
  /// - A day that already has the desired state is left untouched: the outcome
  ///   has no undo.
  /// - The allowed dates are the habit's start day up to today, at most 30
  ///   days back; the future, days before the start and days on or after the
  ///   archive date are rejected with a [ValidationFailure] on
  ///   [HabitFields.date].
  ///
  /// The outcome's undo restores the exact previous state of the row, flag
  /// included. The projection syncs the check's own day.
  Future<CommandOutcome> setChecked({
    required String commandId,
    required String habitId,
    required LocalDate date,
    required bool checked,
  }) {
    return _runner.run(
      commandId: commandId,
      type: checked ? checkType : uncheckType,
      body: (ctx) async {
        final habitRow = await _requireActive(habitId);
        validateCheckDate(
          habit: mapHabit(habitRow),
          date: date,
          today: ctx.today,
        );
        final existing = await _checkRow(habitId, date);
        final isChecked = existing != null && existing.deletedAtUtc == null;
        if (isChecked == checked) {
          return CommandEffect(entityId: existing?.id);
        }

        if (existing == null) {
          // First check of this day: a new row.
          final id = ctx.ids.newId();
          await _database
              .into(_database.habitChecks)
              .insert(
                HabitChecksCompanion.insert(
                  id: id,
                  habitId: habitId,
                  localDate: date,
                  checkedAtUtc: ctx.nowUtc,
                  timezoneId: ctx.timeZoneId,
                  eligibility: await ctx.isGamificationEnabled(),
                  createdAtUtc: ctx.nowUtc,
                  updatedAtUtc: ctx.nowUtc,
                ),
              );
          return CommandEffect(
            entityId: id,
            affectedDays: {date},
            undo: UndoAction(
              run: (undoId) => _softDeleteCheck(
                commandId: undoId,
                checkId: id,
                expectedRowVersion: 1,
                type: undoCheckType,
              ),
            ),
          );
        }

        final newVersion = existing.rowVersion + 1;
        if (checked) {
          // Reactivate the soft-deleted row of this day: new time, new flag.
          await (_database.update(
            _database.habitChecks,
          )..where((c) => c.id.equals(existing.id))).write(
            HabitChecksCompanion(
              deletedAtUtc: const Value(null),
              checkedAtUtc: Value(ctx.nowUtc),
              timezoneId: Value(ctx.timeZoneId),
              eligibility: Value(await ctx.isGamificationEnabled()),
              updatedAtUtc: Value(ctx.nowUtc),
              rowVersion: Value(newVersion),
            ),
          );
        } else {
          await (_database.update(
            _database.habitChecks,
          )..where((c) => c.id.equals(existing.id))).write(
            HabitChecksCompanion(
              deletedAtUtc: Value(ctx.nowUtc),
              updatedAtUtc: Value(ctx.nowUtc),
              rowVersion: Value(newVersion),
            ),
          );
        }
        return CommandEffect(
          entityId: existing.id,
          affectedDays: {date},
          kind: checked ? EffectKind.committed : EffectKind.removed,
          undo: UndoAction(
            run: (undoId) => _restoreCheck(
              commandId: undoId,
              previous: existing,
              expectedRowVersion: newVersion,
              type: checked ? undoCheckType : undoUncheckType,
            ),
          ),
        );
      },
    );
  }

  /// Archives the habit FROM TOMORROW: `archived_from_date` becomes
  /// `today + 1`. Today the habit still applies (the UI shows "Ab morgen
  /// archiviert"); from tomorrow on it is no longer a goal and its reminders
  /// stop. All checks and the history stay. Archiving is final (a habit is
  /// never reactivated), so the outcome has no undo.
  ///
  /// A habit that is already archived keeps its archive date: the call is a
  /// no-op without undo, so archiving twice can never extend the habit.
  Future<CommandOutcome> archive({
    required String commandId,
    required String id,
  }) {
    return _runner.run(
      commandId: commandId,
      type: archiveType,
      body: (ctx) async {
        final row = await _requireActive(id);
        if (row.archivedFromDate != null) {
          return CommandEffect(entityId: id);
        }
        await (_database.update(
          _database.habits,
        )..where((h) => h.id.equals(id))).write(
          HabitsCompanion(
            archivedFromDate: Value(ctx.today.addDays(1)),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        // Today still applies unchanged; tomorrow has no snapshot yet.
        return CommandEffect(entityId: id);
      },
    );
  }

  /// Soft-deletes the habit. Its checks stay in the database but are ignored
  /// by the XP and day fact queries, so the XP of every checked day is taken
  /// back. The outcome's undo restores the SAME id (and with it the history).
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
        final days = await _affectedDays(id, ctx.today);
        await (_database.update(
          _database.habits,
        )..where((h) => h.id.equals(id))).write(
          HabitsCompanion(
            deletedAtUtc: Value(ctx.nowUtc),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: days,
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
          _database.habits,
        )..where((h) => h.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'habit', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.habits,
        )..where((h) => h.id.equals(id))).write(
          HabitsCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: await _affectedDays(id, ctx.today),
        );
      },
    );
  }

  Future<CommandOutcome> _restoreContent({
    required String commandId,
    required HabitRow previous,
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
        await _writeContent(
          previous.id,
          title: previous.title,
          iconKey: previous.iconKey,
          reminderTime: previous.reminderLocalTime,
          now: ctx.nowUtc,
          rowVersion: current.rowVersion + 1,
        );
        return CommandEffect(entityId: previous.id);
      },
    );
  }

  /// Soft-deletes a check row (the undo of "create check").
  Future<CommandOutcome> _softDeleteCheck({
    required String commandId,
    required String checkId,
    required int expectedRowVersion,
    required String type,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row = await _checkRowById(checkId);
        if (row == null) {
          throw NotFoundFailure(entity: 'habit_check', id: checkId);
        }
        if (row.deletedAtUtc != null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(
            ConflictKind.staleVersion,
            relatedEntityId: checkId,
          );
        }
        await (_database.update(
          _database.habitChecks,
        )..where((c) => c.id.equals(checkId))).write(
          HabitChecksCompanion(
            deletedAtUtc: Value(ctx.nowUtc),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: checkId,
          affectedDays: {row.localDate},
          kind: EffectKind.removed,
        );
      },
    );
  }

  /// Writes the exact earlier state of a check row back (deleted marker, time,
  /// zone and eligibility flag) with a new row version.
  Future<CommandOutcome> _restoreCheck({
    required String commandId,
    required HabitCheckRow previous,
    required int expectedRowVersion,
    required String type,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final current = await _checkRowById(previous.id);
        if (current == null) {
          throw NotFoundFailure(entity: 'habit_check', id: previous.id);
        }
        if (current.rowVersion != expectedRowVersion) {
          throw ConflictFailure(
            ConflictKind.staleVersion,
            relatedEntityId: previous.id,
          );
        }
        // The check belongs to a habit that must still exist.
        await _requireActive(previous.habitId);
        await (_database.update(
          _database.habitChecks,
        )..where((c) => c.id.equals(previous.id))).write(
          HabitChecksCompanion(
            deletedAtUtc: Value(previous.deletedAtUtc),
            checkedAtUtc: Value(previous.checkedAtUtc),
            timezoneId: Value(previous.timezoneId),
            eligibility: Value(previous.eligibility),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(current.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: previous.id,
          affectedDays: {previous.localDate},
          kind: previous.deletedAtUtc == null
              ? EffectKind.committed
              : EffectKind.removed,
        );
      },
    );
  }

  Future<void> _writeContent(
    String id, {
    required String title,
    required String iconKey,
    required LocalTime? reminderTime,
    required DateTime now,
    required int rowVersion,
  }) async {
    await (_database.update(
      _database.habits,
    )..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        title: Value(title),
        iconKey: Value(iconKey),
        reminderLocalTime: Value(reminderTime),
        updatedAtUtc: Value(now),
        rowVersion: Value(rowVersion),
      ),
    );
  }

  /// The days whose projection changes when the habit appears or disappears:
  /// every day with an active check, plus today (the goal snapshot).
  Future<Set<LocalDate>> _affectedDays(String habitId, LocalDate today) async {
    final rows = await (_database.select(
      _database.habitChecks,
    )..where((c) => c.habitId.equals(habitId) & c.deletedAtUtc.isNull())).get();
    return {today, for (final row in rows) row.localDate};
  }

  Future<HabitRow?> _activeHabit(String id) {
    return (_database.select(_database.habits)
          ..where((h) => h.id.equals(id) & h.deletedAtUtc.isNull()))
        .getSingleOrNull();
  }

  Future<HabitRow> _requireActive(String id) async {
    final row = await _activeHabit(id);
    if (row == null) {
      throw NotFoundFailure(entity: 'habit', id: id);
    }
    return row;
  }

  /// The check row of a habit and day INCLUDING a soft-deleted one (the unique
  /// index covers deleted rows, so there is at most one).
  Future<HabitCheckRow?> _checkRow(String habitId, LocalDate date) {
    return (_database.select(_database.habitChecks)..where(
          (c) => c.habitId.equals(habitId) & c.localDate.equalsValue(date),
        ))
        .getSingleOrNull();
  }

  Future<HabitCheckRow?> _checkRowById(String id) {
    return (_database.select(
      _database.habitChecks,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  static Habit mapHabit(HabitRow row) => Habit(
    id: row.id,
    title: row.title,
    icon: HabitIcon.tryParse(row.iconKey) ?? defaultHabitIcon,
    startedOn: row.startedLocalDate,
    reminderTime: row.reminderLocalTime,
    archivedFrom: row.archivedFromDate,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static HabitCheck _mapCheck(HabitCheckRow row) => HabitCheck(
    id: row.id,
    habitId: row.habitId,
    date: row.localDate,
    checkedAtUtc: row.checkedAtUtc,
    timezoneId: row.timezoneId,
    eligibility: row.eligibility,
    rowVersion: row.rowVersion,
  );
}
