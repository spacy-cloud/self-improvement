import 'dart:async';

import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// A pure-domain [Task] for list and rule tests (no database involved).
Task makeTask({
  String id = 't1',
  String title = 'Aufgabe',
  TaskPriority priority = TaskPriority.normal,
  String? description,
  LocalDate? dueDate,
  List<String> tags = const [],
  DateTime? createdAtUtc,
  DateTime? completedAtUtc,
  LocalDate? completedLocalDate,
  bool? completionEligibility,
}) {
  final created = createdAtUtc ?? DateTime.utc(2026, 9, 1, 8);
  final completed = completedAtUtc != null;
  return Task(
    id: id,
    title: title,
    priority: priority,
    description: description,
    dueDate: dueDate,
    tags: tags,
    completedAtUtc: completedAtUtc,
    completedLocalDate:
        completedLocalDate ?? (completed ? LocalDate(2026, 10, 3) : null),
    completionTimezoneId: completed ? 'Europe/Berlin' : null,
    completionEligibility: completed ? (completionEligibility ?? true) : null,
    createdAtUtc: created,
    updatedAtUtc: created,
    rowVersion: 1,
  );
}

/// Moves the harness clock to a Berlin wall clock moment (never ambiguous or
/// non-existent in the tests that use it).
void setLocalNow(
  DataHarness harness,
  LocalDate date, [
  LocalTime time = const LocalTime(10, 0),
]) {
  final resolved = harness.clock.toUtc(date, time);
  if (resolved is! ZonedResolved) {
    throw StateError('Wall clock time does not exist: $date $time');
  }
  harness.clock.setNow(resolved.utc);
}

/// Appends a module status row, like the module manager does. Time must move
/// forward between two calls for the same module (the latest change wins).
Future<void> setModuleEnabled(
  DataHarness harness,
  ModuleId module, {
  required bool enabled,
}) async {
  await harness.database
      .into(harness.database.moduleStatusHistory)
      .insert(
        ModuleStatusHistoryCompanion.insert(
          id: harness.ids.newId(),
          moduleId: module.key,
          effectiveAtUtc: harness.clock.nowUtc(),
          localDate: harness.clock.today(),
          enabled: enabled,
        ),
      );
}

/// The awards of the harness database, keyed by award key.
Future<Map<String, int>> awardPoints(DataHarness harness) async {
  final rows = await harness.database.select(harness.database.xpAwards).get();
  return {for (final row in rows) row.awardKey: row.points};
}

/// Silences the drift warning about several in-memory databases per test file.
void allowMultipleDatabases() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
}

/// A real [TaskRepository] that records the command id of every call and can
/// fail the next calls with a [StorageFailure] or hold them at a gate, so tests
/// can observe retries, busy states and double taps.
class ScriptedTaskRepository extends TaskRepository {
  ScriptedTaskRepository({required super.database, required super.runner});

  /// The command ids of all create/update/setCompleted/delete calls, in order.
  final List<String> commandIds = [];

  /// How many of the next calls fail with a [StorageFailure] before doing
  /// anything.
  int failNext = 0;

  /// While set, calls wait here before they run.
  Completer<void>? gate;

  Future<void> _before(String commandId) async {
    commandIds.add(commandId);
    final pending = gate;
    if (pending != null) {
      await pending.future;
    }
    if (failNext > 0) {
      failNext--;
      throw const StorageFailure();
    }
  }

  @override
  Future<CommandOutcome> create({
    required String commandId,
    required TaskDraft draft,
  }) async {
    await _before(commandId);
    return super.create(commandId: commandId, draft: draft);
  }

  @override
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required TaskDraft draft,
    required int expectedRowVersion,
  }) async {
    await _before(commandId);
    return super.update(
      commandId: commandId,
      id: id,
      draft: draft,
      expectedRowVersion: expectedRowVersion,
    );
  }

  @override
  Future<CommandOutcome> setCompleted({
    required String commandId,
    required String id,
    required bool completed,
  }) async {
    await _before(commandId);
    return super.setCompleted(
      commandId: commandId,
      id: id,
      completed: completed,
    );
  }

  @override
  Future<CommandOutcome> delete({
    required String commandId,
    required String id,
  }) async {
    await _before(commandId);
    return super.delete(commandId: commandId, id: id);
  }
}

/// Makes every insert into [table] fail like a full disk, until
/// [restoreInserts] is called. A REAL database error inside the command
/// transaction (as opposed to a faked projection failure).
Future<void> failInsertsInto(DataHarness harness, String table) =>
    harness.database.customStatement(
      'CREATE TRIGGER fail_insert_$table BEFORE INSERT ON $table '
      "BEGIN SELECT RAISE(ABORT, 'disk full'); END",
    );

/// Removes the trigger of [failInsertsInto].
Future<void> restoreInserts(DataHarness harness, String table) =>
    harness.database.customStatement('DROP TRIGGER fail_insert_$table');
