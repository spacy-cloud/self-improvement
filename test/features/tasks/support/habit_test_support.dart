import 'dart:async';

import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// A pure-domain [Habit] for rule and read model tests (no database involved).
Habit makeHabit({
  String id = 'h1',
  String title = 'Lesen',
  HabitIcon icon = HabitIcon.book,
  LocalDate? startedOn,
  LocalDate? archivedFrom,
  LocalTime? reminderTime,
  DateTime? createdAtUtc,
}) {
  final created = createdAtUtc ?? DateTime.utc(2026, 9, 1, 8);
  return Habit(
    id: id,
    title: title,
    icon: icon,
    startedOn: startedOn ?? LocalDate(2026, 9, 1),
    archivedFrom: archivedFrom,
    reminderTime: reminderTime,
    createdAtUtc: created,
    updatedAtUtc: created,
    rowVersion: 1,
  );
}

/// A real [HabitRepository] that records the command id of every call and can
/// fail the next calls with a [StorageFailure] or hold them at a gate (see the
/// task counterpart `ScriptedTaskRepository`).
class ScriptedHabitRepository extends HabitRepository {
  ScriptedHabitRepository({required super.database, required super.runner});

  /// The command ids of all create/update/setChecked/archive/delete calls.
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
    required HabitDraft draft,
  }) async {
    await _before(commandId);
    return super.create(commandId: commandId, draft: draft);
  }

  @override
  Future<CommandOutcome> update({
    required String commandId,
    required String id,
    required HabitDraft draft,
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
  Future<CommandOutcome> setChecked({
    required String commandId,
    required String habitId,
    required LocalDate date,
    required bool checked,
  }) async {
    await _before(commandId);
    return super.setChecked(
      commandId: commandId,
      habitId: habitId,
      date: date,
      checked: checked,
    );
  }

  @override
  Future<CommandOutcome> archive({
    required String commandId,
    required String id,
  }) async {
    await _before(commandId);
    return super.archive(commandId: commandId, id: id);
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
