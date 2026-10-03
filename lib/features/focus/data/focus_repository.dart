import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_context.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Focus sessions: reads plus every timer command.
///
/// Follows the reference repository pattern (validation first, then the
/// mutation, every mutation a [CommandRunner] command, soft delete, row
/// version checks for undo, frozen business date and zone). All state changes
/// are decided by the pure functions of `focus_timer.dart`; this class only
/// loads, applies and persists them.
///
/// ## Commands
///
/// Every command that changes the OPEN session (start, pause, resume, await,
/// save, discard and the undo of save/discard) publishes a [FocusStateChanged]
/// event after the commit; failed commands publish nothing. Commands that
/// reach the desired state again (pause on a paused session, a second save)
/// are no-ops. Commands that need to know the session take its id, so a stale
/// screen can never act on a different session.
///
/// | Command | Undoable | Projection days |
/// |---|---|---|
/// | [start] | no | none |
/// | [pause], [resume], [markAwaitingConfirmation] | no | none |
/// | [save] / [finishEarly] | yes: reopens the session in its previous state | the completion day |
/// | [discard] | yes: reopens the session in its previous state | none |
/// | [updateNote] | yes: restores the previous note | none |
/// | [delete] (completed or discarded only) | yes: restores the same id | the completion day |
class FocusRepository {
  FocusRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String startType = 'focus.start';
  static const String pauseType = 'focus.pause';
  static const String resumeType = 'focus.resume';
  static const String awaitType = 'focus.await_confirmation';
  static const String saveType = 'focus.save';
  static const String discardType = 'focus.discard';
  static const String updateNoteType = 'focus.note.update';
  static const String deleteType = 'focus.delete';
  static const String undoSaveType = 'focus.save.undo';
  static const String undoDiscardType = 'focus.discard.undo';
  static const String undoNoteType = 'focus.note.update.undo';
  static const String undoDeleteType = 'focus.delete.undo';

  // ---------------------------------------------------------------- reads

  /// The open session (running, paused or awaiting confirmation), or null.
  /// Re-emits on every change; independent of any screen.
  Stream<FocusSession?> watchOpen() {
    final query = _database.select(_database.focusSessions)
      ..where(_isOpen)
      ..orderBy([
        (f) => OrderingTerm.desc(f.createdAtUtc),
        (f) => OrderingTerm.desc(f.id),
      ])
      ..limit(1);
    return query.watch().map(
      (rows) => rows.isEmpty ? null : mapFocusSession(rows.first),
    );
  }

  /// The open session now, or null.
  Future<FocusSession?> findOpen() async {
    final row =
        await (_database.select(_database.focusSessions)
              ..where(_isOpen)
              ..orderBy([
                (f) => OrderingTerm.desc(f.createdAtUtc),
                (f) => OrderingTerm.desc(f.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : mapFocusSession(row);
  }

  /// One active (not deleted) session of any status; null if missing.
  Stream<FocusSession?> watchById(String id) {
    final query = _database.select(_database.focusSessions)
      ..where((f) => f.id.equals(id) & f.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapFocusSession(row),
    );
  }

  Future<FocusSession?> findById(String id) async {
    final row =
        await (_database.select(_database.focusSessions)
              ..where((f) => f.id.equals(id) & f.deletedAtUtc.isNull()))
            .getSingleOrNull();
    return row == null ? null : mapFocusSession(row);
  }

  /// Completed sessions, newest confirmation first. Discarded and open
  /// sessions are not part of the history. [limit] and [offset] allow a lazy,
  /// paged list.
  Stream<List<FocusSession>> watchHistory({int? limit, int offset = 0}) {
    return _historyQuery(
      limit: limit,
      offset: offset,
    ).watch().map((rows) => rows.map(mapFocusSession).toList());
  }

  /// One page of the history (see [watchHistory]).
  Future<List<FocusSession>> fetchHistory({
    required int limit,
    int offset = 0,
  }) async {
    final rows = await _historyQuery(limit: limit, offset: offset).get();
    return rows.map(mapFocusSession).toList();
  }

  /// Sessions completed on the local [date] (the confirmation day), newest
  /// first.
  Stream<List<FocusSession>> watchCompletedOn(LocalDate date) {
    final query = _database.select(_database.focusSessions)
      ..where(
        (f) =>
            f.status.equals(FocusStatus.completed.key) &
            f.completedLocalDate.equalsValue(date) &
            f.deletedAtUtc.isNull(),
      )
      ..orderBy([
        (f) => OrderingTerm.desc(f.endedAtUtc),
        (f) => OrderingTerm.desc(f.id),
      ]);
    return query.watch().map((rows) => rows.map(mapFocusSession).toList());
  }

  SimpleSelectStatement<$FocusSessionsTable, FocusSessionRow> _historyQuery({
    int? limit,
    int offset = 0,
  }) {
    final query = _database.select(_database.focusSessions)
      ..where(
        (f) =>
            f.status.equals(FocusStatus.completed.key) &
            f.deletedAtUtc.isNull(),
      )
      ..orderBy([
        (f) => OrderingTerm.desc(f.endedAtUtc),
        (f) => OrderingTerm.desc(f.id),
      ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query;
  }

  static Expression<bool> _isOpen($FocusSessionsTable f) =>
      f.status.isIn(SchemaKeys.focusOpenStatuses) & f.deletedAtUtc.isNull();

  // ------------------------------------------------------------- commands

  /// Starts a session: persists it as `running` (the UI shows the started
  /// state from the database, never before). Validates the planned duration
  /// (300 to 10800 seconds) first; if a session is already open (any open
  /// state) the command fails with `ConflictFailure(openFocusSession)` and
  /// the open session as `relatedEntityId` - navigation can never create a
  /// second session. The database additionally enforces it with a partial
  /// unique index.
  Future<CommandOutcome> start({
    required String commandId,
    required FocusCategory category,
    required int plannedSeconds,
  }) {
    return _runner.run(
      commandId: commandId,
      type: startType,
      body: (ctx) async {
        validateFocusPlan(plannedSeconds);
        await _ensureNoOpenSession();
        final id = ctx.ids.newId();
        await _database
            .into(_database.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: id,
                category: category.key,
                plannedSeconds: plannedSeconds,
                segmentStartedAtUtc: Value(ctx.nowUtc),
                startedAtUtc: ctx.nowUtc,
                timezoneId: ctx.timeZoneId,
                status: FocusStatus.running.key,
                createdAtUtc: ctx.nowUtc,
                updatedAtUtc: ctx.nowUtc,
              ),
            );
        return CommandEffect(
          entityId: id,
          extraEvents: const [FocusStateChanged()],
        );
      },
    );
  }

  /// Pauses a running session (see `pauseFocus`).
  Future<CommandOutcome> pause({
    required String commandId,
    required String id,
  }) => _transition(
    commandId: commandId,
    type: pauseType,
    id: id,
    transition: (session, ctx) => pauseFocus(session, ctx.nowUtc),
  );

  /// Resumes a paused session with a new UTC segment (see `resumeFocus`).
  Future<CommandOutcome> resume({
    required String commandId,
    required String id,
  }) => _transition(
    commandId: commandId,
    type: resumeType,
    id: id,
    transition: (session, ctx) => resumeFocus(session, ctx.nowUtc),
  );

  /// The countdown reached zero (foreground) or the app was restored past the
  /// end: accumulated = planned, no running segment, status
  /// `awaiting_confirmation`. No XP and no completed record. Idempotent.
  Future<CommandOutcome> markAwaitingConfirmation({
    required String commandId,
    required String id,
  }) => _transition(
    commandId: commandId,
    type: awaitType,
    id: id,
    transition: (session, ctx) => awaitFocusConfirmation(session),
  );

  /// "Sitzung speichern": the elapsed time becomes a completed session whose
  /// whole duration counts on the local date of this confirmation (frozen with
  /// the zone). At least one second is required; below 300 seconds the time is
  /// saved but earns no XP. Eligibility is frozen from the gamification state
  /// now. Saving a completed session again (same or new command id) changes
  /// nothing: exactly ONE completion exists.
  ///
  /// The undo reopens the session in the state it had before (a running
  /// session continues from now with the time saved so far).
  Future<CommandOutcome> save({required String commandId, required String id}) {
    return _runner.run(
      commandId: commandId,
      type: saveType,
      body: (ctx) async {
        final row = await _requireActive(id);
        final before = mapFocusSession(row);
        final frozen = ctx.frozenNow;
        final result = completeFocus(
          before,
          nowUtc: ctx.nowUtc,
          completedDate: frozen.localDate,
          timezoneId: frozen.timezoneId,
          eligible: await ctx.isGamificationEnabled(),
        );
        if (!result.changed) {
          return CommandEffect(entityId: id);
        }
        await _writeState(row, result.session, ctx);
        final newVersion = row.rowVersion + 1;
        return CommandEffect(
          entityId: id,
          affectedDays: {frozen.localDate},
          extraEvents: const [FocusStateChanged()],
          undo: UndoAction(
            run: (undoId) => _reopen(
              commandId: undoId,
              id: id,
              previousStatus: before.status,
              previousTimezoneId: before.timezoneId,
              expectedRowVersion: newVersion,
              type: undoSaveType,
            ),
          ),
        );
      },
    );
  }

  /// "Früher beenden" after the user confirmed the duration so far. This is
  /// [save] from a running or paused session.
  Future<CommandOutcome> finishEarly({
    required String commandId,
    required String id,
  }) => save(commandId: commandId, id: id);

  /// "Verwerfen": the session never counts (no completed date, no duration
  /// aggregation, no XP). The undo reopens it in its previous state.
  Future<CommandOutcome> discard({
    required String commandId,
    required String id,
  }) {
    return _runner.run(
      commandId: commandId,
      type: discardType,
      body: (ctx) async {
        final row = await _requireActive(id);
        final before = mapFocusSession(row);
        final result = discardFocus(before, ctx.nowUtc);
        if (!result.changed) {
          return CommandEffect(entityId: id);
        }
        await _writeState(row, result.session, ctx);
        final newVersion = row.rowVersion + 1;
        return CommandEffect(
          entityId: id,
          extraEvents: const [FocusStateChanged()],
          undo: UndoAction(
            run: (undoId) => _reopen(
              commandId: undoId,
              id: id,
              previousStatus: before.status,
              previousTimezoneId: before.timezoneId,
              expectedRowVersion: newVersion,
              type: undoDiscardType,
            ),
          ),
        );
      },
    );
  }

  /// Changes the note of a COMPLETED session (at most 500 characters after
  /// trimming, blank removes it). The duration can never be extended
  /// afterwards. [expectedRowVersion] is the version the edit form was loaded
  /// with; a mismatch is a `ConflictFailure(staleVersion)`.
  Future<CommandOutcome> updateNote({
    required String commandId,
    required String id,
    required String? note,
    int? expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateNoteType,
      body: (ctx) async {
        final normalized = normalizeFocusNote(note);
        final row = await _requireActive(id);
        if (expectedRowVersion != null &&
            row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        if (row.status != FocusStatus.completed.key) {
          throw ConflictFailure(ConflictKind.invalidState, relatedEntityId: id);
        }
        if (row.note == normalized) {
          return CommandEffect(entityId: id);
        }
        final newVersion = row.rowVersion + 1;
        await (_database.update(
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).write(
          FocusSessionsCompanion(
            note: Value(normalized),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          undo: UndoAction(
            run: (undoId) => _restoreNote(
              commandId: undoId,
              id: id,
              previousNote: row.note,
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes a COMPLETED or DISCARDED session (an open session cannot be
  /// deleted: save or discard it first). The saved time and its XP disappear
  /// with it; the undo restores the SAME id.
  Future<CommandOutcome> delete({
    required String commandId,
    required String id,
  }) {
    return _runner.run(
      commandId: commandId,
      type: deleteType,
      body: (ctx) async {
        final row = await _requireActive(id);
        if (FocusStatus.fromKey(row.status).isOpen) {
          throw ConflictFailure(ConflictKind.invalidState, relatedEntityId: id);
        }
        final newVersion = row.rowVersion + 1;
        await (_database.update(
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).write(
          FocusSessionsCompanion(
            deletedAtUtc: Value(ctx.nowUtc),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: _daysOf(row),
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

  // -------------------------------------------------------------- helpers

  /// pause / resume / await: load, transition, persist, publish.
  Future<CommandOutcome> _transition({
    required String commandId,
    required String type,
    required String id,
    required FocusTransition Function(FocusSession session, CommandContext ctx)
    transition,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row = await _requireActive(id);
        final result = transition(mapFocusSession(row), ctx);
        if (!result.changed) {
          return CommandEffect(entityId: id);
        }
        await _writeState(row, result.session, ctx);
        return CommandEffect(
          entityId: id,
          extraEvents: const [FocusStateChanged()],
        );
      },
    );
  }

  /// Persists the state columns of [next] with a new row version.
  Future<void> _writeState(
    FocusSessionRow before,
    FocusSession next,
    CommandContext ctx,
  ) {
    return (_database.update(
      _database.focusSessions,
    )..where((f) => f.id.equals(before.id))).write(
      FocusSessionsCompanion(
        status: Value(next.status.key),
        accumulatedSeconds: Value(next.accumulatedSeconds),
        segmentStartedAtUtc: Value(next.segmentStartedAtUtc),
        endedAtUtc: Value(next.endedAtUtc),
        completedLocalDate: Value(next.completedLocalDate),
        timezoneId: Value(next.timezoneId),
        gamificationEligible: Value(next.gamificationEligible),
        updatedAtUtc: Value(ctx.nowUtc),
        rowVersion: Value(before.rowVersion + 1),
      ),
    );
  }

  /// Undo of save/discard: the session is open again in [previousStatus].
  ///
  /// The row must be unchanged since the action ([expectedRowVersion]) and no
  /// other session may have been started meanwhile. A session that was running
  /// continues with a new segment from now (the time between the action and the
  /// undo is not counted); one that was awaiting confirmation is awaiting again.
  Future<CommandOutcome> _reopen({
    required String commandId,
    required String id,
    required FocusStatus previousStatus,
    required String previousTimezoneId,
    required int expectedRowVersion,
    required String type,
  }) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row = await _requireActive(id);
        if (row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await _ensureNoOpenSession(exceptId: id);
        final accumulated = previousStatus == FocusStatus.awaitingConfirmation
            ? row.plannedSeconds
            : row.accumulatedSeconds.clamp(0, row.plannedSeconds);
        await (_database.update(
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).write(
          FocusSessionsCompanion(
            status: Value(previousStatus.key),
            accumulatedSeconds: Value(accumulated),
            segmentStartedAtUtc: Value(
              previousStatus == FocusStatus.running ? ctx.nowUtc : null,
            ),
            endedAtUtc: const Value(null),
            completedLocalDate: const Value(null),
            timezoneId: Value(previousTimezoneId),
            gamificationEligible: const Value(false),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: _daysOf(row),
          kind: row.completedLocalDate == null
              ? EffectKind.committed
              : EffectKind.removed,
          extraEvents: const [FocusStateChanged()],
        );
      },
    );
  }

  Future<CommandOutcome> _restoreNote({
    required String commandId,
    required String id,
    required String? previousNote,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: undoNoteType,
      body: (ctx) async {
        final row = await _requireActive(id);
        if (row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).write(
          FocusSessionsCompanion(
            note: Value(previousNote),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(entityId: id);
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
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'focus_session', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.focusSessions,
        )..where((f) => f.id.equals(id))).write(
          FocusSessionsCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(entityId: id, affectedDays: _daysOf(row));
      },
    );
  }

  Future<FocusSessionRow> _requireActive(String id) async {
    final row =
        await (_database.select(_database.focusSessions)
              ..where((f) => f.id.equals(id) & f.deletedAtUtc.isNull()))
            .getSingleOrNull();
    if (row == null) {
      throw NotFoundFailure(entity: 'focus_session', id: id);
    }
    return row;
  }

  /// At most one open session may exist (besides [exceptId]); otherwise a
  /// `ConflictFailure(openFocusSession)` offers the open one.
  Future<void> _ensureNoOpenSession({String? exceptId}) async {
    final open = await (_database.select(
      _database.focusSessions,
    )..where(_isOpen)).get();
    final other = open.where((row) => row.id != exceptId).firstOrNull;
    if (other != null) {
      throw ConflictFailure(
        ConflictKind.openFocusSession,
        relatedEntityId: other.id,
      );
    }
  }

  /// The projection days a row influences: its completion day, if any.
  static Set<LocalDate> _daysOf(FocusSessionRow row) {
    final date = row.completedLocalDate;
    return date == null ? const {} : {date};
  }

  static FocusSession mapFocusSession(FocusSessionRow row) => FocusSession(
    id: row.id,
    category: FocusCategory.fromKey(row.category),
    plannedSeconds: row.plannedSeconds,
    accumulatedSeconds: row.accumulatedSeconds,
    status: FocusStatus.fromKey(row.status),
    segmentStartedAtUtc: row.segmentStartedAtUtc,
    startedAtUtc: row.startedAtUtc,
    endedAtUtc: row.endedAtUtc,
    completedLocalDate: row.completedLocalDate,
    timezoneId: row.timezoneId,
    note: row.note,
    gamificationEligible: row.gamificationEligible,
    rowVersion: row.rowVersion,
    updatedAtUtc: row.updatedAtUtc,
  );
}
