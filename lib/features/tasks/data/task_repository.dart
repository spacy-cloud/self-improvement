import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Tasks: reads plus create/update/complete/delete commands with undo.
///
/// Follows the reference pattern of the weight repository: validation first,
/// every mutation is a [CommandRunner] command (atomic, idempotent), soft
/// delete, row version checks for edit and undo, frozen business date and zone.
///
/// Completion is a DESIRED STATE ([setCompleted]), never a blind toggle: the
/// same command id is a replay, a new command id for a state the task already
/// has is a no-op that keeps the existing completion and returns no undo.
class TaskRepository {
  TaskRepository({required this._database, required this._runner});

  final AppDatabase _database;
  final CommandRunner _runner;

  static const String createType = 'task.create';
  static const String updateType = 'task.update';
  static const String completeType = 'task.complete';
  static const String reopenType = 'task.reopen';
  static const String deleteType = 'task.delete';
  static const String undoCreateType = 'task.create.undo';
  static const String undoUpdateType = 'task.update.undo';
  static const String undoCompleteType = 'task.complete.undo';
  static const String undoReopenType = 'task.reopen.undo';
  static const String undoDeleteType = 'task.delete.undo';

  // ---------------------------------------------------------------- reads

  /// All active (not deleted) tasks, open and completed, oldest first. Sorting
  /// and filtering for the screens is done by the pure list functions.
  Stream<List<Task>> watchActive() {
    final query = _database.select(_database.tasks)
      ..where((t) => t.deletedAtUtc.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAtUtc),
        (t) => OrderingTerm.asc(t.id),
      ]);
    return query.watch().map((rows) => rows.map(mapTask).toList());
  }

  /// One active task; emits null when it is missing or deleted.
  Stream<Task?> watchById(String id) {
    final query = _database.select(_database.tasks)
      ..where((t) => t.id.equals(id) & t.deletedAtUtc.isNull());
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : mapTask(row),
    );
  }

  /// One active task; null if missing or deleted.
  Future<Task?> findById(String id) async {
    final row = await _activeRow(id);
    return row == null ? null : mapTask(row);
  }

  // ------------------------------------------------------------- commands

  /// Creates an open task. Retrying the same [commandId] never duplicates.
  Future<CommandOutcome> create({
    required String commandId,
    required TaskDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: createType,
      body: (ctx) async {
        final input = validateTaskDraft(draft);
        final id = ctx.ids.newId();
        await _database
            .into(_database.tasks)
            .insert(
              TasksCompanion.insert(
                id: id,
                title: input.title,
                description: Value(input.description),
                priority: Value(input.priority.key),
                dueLocalDate: Value(input.dueDate),
                tagsJson: Value(input.tags),
                createdAtUtc: ctx.nowUtc,
                updatedAtUtc: ctx.nowUtc,
              ),
            );
        // An open task has no projection effect, so no day is affected.
        return CommandEffect(
          entityId: id,
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

  /// Edits title, description, priority, due date and tags. NEVER changes the
  /// completion. [expectedRowVersion] is the version the form was loaded with;
  /// a mismatch is a [ConflictFailure] (`staleVersion`).
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required TaskDraft draft,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      type: updateType,
      body: (ctx) async {
        final input = validateTaskDraft(draft);
        final before = await _requireActive(id);
        if (before.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        final newVersion = before.rowVersion + 1;
        await _writeContent(id, input, now: ctx.nowUtc, rowVersion: newVersion);
        // Content edits never move a completion: no day is affected.
        return CommandEffect(
          entityId: id,
          undo: UndoAction(
            run: (undoId) => _restoreContent(
              commandId: undoId,
              previous: mapTask(before),
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Sets the completion to the DESIRED state.
  ///
  /// - Completing an open task freezes `completed_at_utc` (now), the local date
  ///   and zone of that moment and `completion_eligibility` = whether
  ///   gamification is enabled right now.
  /// - Reopening a completed task clears all completion fields including the
  ///   eligibility flag; the XP of that completion disappears with the next
  ///   projection. A later completion is a new one with a NEW flag.
  /// - A task that already is in the desired state is left untouched (the
  ///   existing completion and its flag are kept): the outcome has no undo.
  /// - The same [commandId] again is a replay (`CommandOutcome.replayed`).
  ///
  /// The outcome's undo restores the exact previous state, flag included.
  Future<CommandOutcome> setCompleted({
    required String commandId,
    required String id,
    required bool completed,
  }) {
    return _runner.run(
      commandId: commandId,
      type: completed ? completeType : reopenType,
      body: (ctx) async {
        final row = await _requireActive(id);
        final isCompleted = row.completedAtUtc != null;
        if (isCompleted == completed) {
          return CommandEffect(entityId: id);
        }
        final previous = _Completion.of(row);
        final _Completion next;
        if (completed) {
          final frozen = ctx.frozenNow;
          next = _Completion(
            at: frozen.utc,
            date: frozen.localDate,
            timezoneId: frozen.timezoneId,
            eligibility: await ctx.isGamificationEnabled(),
          );
        } else {
          next = const _Completion.open();
        }
        final newVersion = row.rowVersion + 1;
        await _writeCompletion(
          id,
          next,
          now: ctx.nowUtc,
          rowVersion: newVersion,
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {?previous.date, ?next.date, ctx.today},
          kind: completed ? EffectKind.committed : EffectKind.removed,
          undo: UndoAction(
            run: (undoId) => _restoreCompletion(
              commandId: undoId,
              id: id,
              restore: previous,
              expectedRowVersion: newVersion,
            ),
          ),
        );
      },
    );
  }

  /// Soft-deletes a task (a completed one takes its XP with it). The outcome's
  /// undo restores the SAME id.
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
          _database.tasks,
        )..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            deletedAtUtc: Value(ctx.nowUtc),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(newVersion),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {?row.completedLocalDate},
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
          _database.tasks,
        )..where((t) => t.id.equals(id))).getSingleOrNull();
        if (row == null) {
          throw NotFoundFailure(entity: 'task', id: id);
        }
        if (row.deletedAtUtc == null || row.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await (_database.update(
          _database.tasks,
        )..where((t) => t.id.equals(id))).write(
          TasksCompanion(
            deletedAtUtc: const Value(null),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(row.rowVersion + 1),
          ),
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {?row.completedLocalDate},
        );
      },
    );
  }

  Future<CommandOutcome> _restoreContent({
    required String commandId,
    required Task previous,
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
          TaskDraft(
            title: previous.title,
            description: previous.description,
            priority: previous.priority,
            dueDate: previous.dueDate,
            tags: previous.tags,
          ),
          now: ctx.nowUtc,
          rowVersion: current.rowVersion + 1,
        );
        return CommandEffect(entityId: previous.id);
      },
    );
  }

  Future<CommandOutcome> _restoreCompletion({
    required String commandId,
    required String id,
    required _Completion restore,
    required int expectedRowVersion,
  }) {
    return _runner.run(
      commandId: commandId,
      // Restoring a completion undoes a reopen; restoring "open" undoes a
      // completion.
      type: restore.isCompleted ? undoReopenType : undoCompleteType,
      body: (ctx) async {
        final current = await _requireActive(id);
        if (current.rowVersion != expectedRowVersion) {
          throw ConflictFailure(ConflictKind.staleVersion, relatedEntityId: id);
        }
        await _writeCompletion(
          id,
          restore,
          now: ctx.nowUtc,
          rowVersion: current.rowVersion + 1,
        );
        return CommandEffect(
          entityId: id,
          affectedDays: {?current.completedLocalDate, ?restore.date, ctx.today},
          kind: restore.isCompleted ? EffectKind.committed : EffectKind.removed,
        );
      },
    );
  }

  Future<void> _writeContent(
    String id,
    TaskDraft input, {
    required DateTime now,
    required int rowVersion,
  }) async {
    await (_database.update(
      _database.tasks,
    )..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: Value(input.title),
        description: Value(input.description),
        priority: Value(input.priority.key),
        dueLocalDate: Value(input.dueDate),
        tagsJson: Value(input.tags),
        updatedAtUtc: Value(now),
        rowVersion: Value(rowVersion),
      ),
    );
  }

  /// Writes the four completion columns together (the schema requires them to
  /// be all set or all null).
  Future<void> _writeCompletion(
    String id,
    _Completion completion, {
    required DateTime now,
    required int rowVersion,
  }) async {
    await (_database.update(
      _database.tasks,
    )..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        completedAtUtc: Value(completion.at),
        completedLocalDate: Value(completion.date),
        timezoneId: Value(completion.timezoneId),
        completionEligibility: Value(completion.eligibility),
        updatedAtUtc: Value(now),
        rowVersion: Value(rowVersion),
      ),
    );
  }

  Future<TaskRow?> _activeRow(String id) {
    return (_database.select(_database.tasks)
          ..where((t) => t.id.equals(id) & t.deletedAtUtc.isNull()))
        .getSingleOrNull();
  }

  Future<TaskRow> _requireActive(String id) async {
    final row = await _activeRow(id);
    if (row == null) {
      throw NotFoundFailure(entity: 'task', id: id);
    }
    return row;
  }

  static Task mapTask(TaskRow row) => Task(
    id: row.id,
    title: row.title,
    description: row.description,
    priority: TaskPriority.tryParse(row.priority) ?? defaultTaskPriority,
    dueDate: row.dueLocalDate,
    tags: row.tagsJson,
    completedAtUtc: row.completedAtUtc,
    completedLocalDate: row.completedLocalDate,
    completionTimezoneId: row.timezoneId,
    completionEligibility: row.completionEligibility,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );
}

/// The completion columns of a task as one value, copied exactly (including a
/// null zone) so an undo restores the previous state byte for byte.
final class _Completion {
  const _Completion({this.at, this.date, this.timezoneId, this.eligibility});

  const _Completion.open() : this();

  factory _Completion.of(TaskRow row) => _Completion(
    at: row.completedAtUtc,
    date: row.completedLocalDate,
    timezoneId: row.timezoneId,
    eligibility: row.completionEligibility,
  );

  final DateTime? at;
  final LocalDate? date;
  final String? timezoneId;
  final bool? eligibility;

  bool get isCompleted => at != null;
}
