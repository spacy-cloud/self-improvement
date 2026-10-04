import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';

/// Which task actions are running right now. Use it to disable the checkbox or
/// menu entry of a task while its command runs (repeated taps are ignored
/// anyway, the state only makes that visible).
@immutable
final class TaskActionsState {
  const TaskActionsState({
    this.busyTaskIds = const {},
    this.undoRunning = false,
  });

  /// Ids of tasks with a running command.
  final Set<String> busyTaskIds;

  /// True while an undo runs.
  final bool undoRunning;

  /// Whether a command for [taskId] is running.
  bool isBusy(String taskId) => busyTaskIds.contains(taskId);
}

/// Result of a task action (completion, reopening, delete, undo).
sealed class TaskActionResult {
  const TaskActionResult();
}

/// The command committed or was a harmless no-op / replay.
///
/// [message] is the German success text for the snackbar. Offer "Rückgängig"
/// only when [undo] is not null: a no-op (the task already had the desired
/// state) and a replay carry no undo.
final class TaskActionSucceeded extends TaskActionResult {
  const TaskActionSucceeded(this.outcome, this.message);

  final CommandOutcome outcome;
  final String message;

  UndoAction? get undo => outcome.undo;
}

/// The command did not commit; nothing changed. [message] is the German text
/// for the snackbar; a retry with the same action reuses the command id.
final class TaskActionFailed extends TaskActionResult {
  const TaskActionFailed(this.failure);

  final AppFailure failure;

  String get message => failure.userMessage;
}

/// Ignored: another command for the same task (or another undo) is running.
final class TaskActionBusy extends TaskActionResult {
  const TaskActionBusy();
}

/// Commands of the task list, the dashboard card and the task detail:
/// completing and reopening (as a desired state), deleting and undo.
///
/// Every call is one user action with its own command id; repeated taps while
/// a command runs are ignored ([TaskActionBusy]); a retry after a failure of
/// the same action reuses the failed attempt's id so it can never apply twice.
class TaskActionsController extends Notifier<TaskActionsState> {
  late Map<String, SubmissionTracker> _trackers;

  @override
  TaskActionsState build() {
    _trackers = {};
    return const TaskActionsState();
  }

  /// Sets the completion to the DESIRED state. Never a toggle: completing an
  /// already completed task keeps its completion (success without undo).
  Future<TaskActionResult> setCompleted(
    String taskId, {
    required bool completed,
  }) => _run(
    taskId,
    fingerprint: completed ? 'complete' : 'reopen',
    message: completed ? 'Aufgabe erledigt' : 'Aufgabe wieder geöffnet',
    command: (commandId) => ref
        .read(taskRepositoryProvider)
        .setCompleted(commandId: commandId, id: taskId, completed: completed),
  );

  /// Soft-deletes the task (the UI asks for confirmation first).
  Future<TaskActionResult> delete(String taskId) => _run(
    taskId,
    fingerprint: 'delete',
    message: 'Aufgabe gelöscht',
    command: (commandId) => ref
        .read(taskRepositoryProvider)
        .delete(commandId: commandId, id: taskId),
  );

  /// Runs the inverse of an earlier action (the snackbar's "Rückgängig"). A
  /// task that changed since is reported as a conflict, never overwritten.
  Future<TaskActionResult> undo(UndoAction action) async {
    if (state.undoRunning) {
      return const TaskActionBusy();
    }
    state = TaskActionsState(busyTaskIds: state.busyTaskIds, undoRunning: true);
    try {
      final outcome = await action.run(ref.read(idGeneratorProvider).newId());
      return TaskActionSucceeded(outcome, 'Rückgängig gemacht');
    } on AppFailure catch (failure) {
      return TaskActionFailed(failure);
    } finally {
      if (ref.mounted) {
        state = TaskActionsState(busyTaskIds: state.busyTaskIds);
      }
    }
  }

  Future<TaskActionResult> _run(
    String taskId, {
    required Object fingerprint,
    required String message,
    required Future<CommandOutcome> Function(String commandId) command,
  }) async {
    if (state.isBusy(taskId)) {
      return const TaskActionBusy();
    }
    final tracker = _trackers.putIfAbsent(
      taskId,
      () => SubmissionTracker(ref.read(idGeneratorProvider)),
    );
    final commandId = tracker.idFor(fingerprint);
    state = TaskActionsState(
      busyTaskIds: {...state.busyTaskIds, taskId},
      undoRunning: state.undoRunning,
    );
    try {
      final outcome = await command(commandId);
      tracker.completed();
      return TaskActionSucceeded(outcome, message);
    } on AppFailure catch (failure) {
      return TaskActionFailed(failure);
    } finally {
      if (ref.mounted) {
        state = TaskActionsState(
          busyTaskIds: {...state.busyTaskIds}..remove(taskId),
          undoRunning: state.undoRunning,
        );
      }
    }
  }
}

final taskActionsProvider =
    NotifierProvider<TaskActionsController, TaskActionsState>(
      TaskActionsController.new,
    );
