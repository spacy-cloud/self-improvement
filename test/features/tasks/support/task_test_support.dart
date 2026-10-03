import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
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
