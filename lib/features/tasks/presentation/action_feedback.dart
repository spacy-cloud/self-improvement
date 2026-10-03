import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/tasks/application/habit_actions_controller.dart';
import 'package:self_improvement/features/tasks/application/task_actions_controller.dart';
import 'package:self_improvement/shared/local_date.dart';

// The actions of the task and habit screens and what the user is told about
// them. Every function takes the ProviderContainer (not a WidgetRef): the
// "Erneut" button of an error message can outlive the widget that started the
// action, and a retry reuses the command id of the failed attempt (the
// controllers keep it), so it can never apply twice.
//
// Success feedback is shown only after the command committed; a failure shows
// the German message next to the unchanged state. Repeated taps while the same
// command runs are ignored by the controllers (busy).

/// Sets the completion of a task to the DESIRED state [completed] (never a
/// blind toggle): "Aufgabe erledigt" / "Aufgabe wieder geöffnet" with undo.
Future<void> setTaskCompleted(
  ProviderContainer container,
  String taskId, {
  required bool completed,
}) async {
  final feedback = container.read(feedbackServiceProvider);
  final result = await container
      .read(taskActionsProvider.notifier)
      .setCompleted(taskId, completed: completed);
  switch (result) {
    case TaskActionSucceeded():
      feedback.showSaved(result.message, undo: result.undo);
    case TaskActionFailed():
      feedback.showError(
        result.message,
        onRetry: () => unawaited(
          setTaskCompleted(container, taskId, completed: completed),
        ),
      );
    case TaskActionBusy():
      break;
  }
}

/// Deletes a task (the caller asked for confirmation before). Returns whether
/// it was deleted.
Future<bool> deleteTaskWithFeedback(
  ProviderContainer container,
  String taskId,
) async {
  final feedback = container.read(feedbackServiceProvider);
  final result = await container
      .read(taskActionsProvider.notifier)
      .delete(taskId);
  switch (result) {
    case TaskActionSucceeded():
      feedback.showSaved(result.message, undo: result.undo);
      return true;
    case TaskActionFailed():
      feedback.showError(
        result.failure is StorageFailure
            ? 'Löschen fehlgeschlagen. Die Aufgabe ist unverändert.'
            : result.message,
        onRetry: result.failure is StorageFailure
            ? () => unawaited(deleteTaskWithFeedback(container, taskId))
            : null,
      );
      return false;
    case TaskActionBusy():
      return false;
  }
}

/// Sets the check of [habitId] on [date] to the desired state [checked]:
/// "Abgehakt" / "Haken entfernt" with undo.
Future<void> setHabitChecked(
  ProviderContainer container,
  String habitId,
  LocalDate date, {
  required bool checked,
}) async {
  final feedback = container.read(feedbackServiceProvider);
  final result = await container
      .read(habitActionsProvider.notifier)
      .setChecked(habitId, date, checked: checked);
  switch (result) {
    case HabitActionSucceeded():
      feedback.showSaved(result.message, undo: result.undo);
    case HabitActionFailed():
      // A rule violation (future day, before the start, after the archive
      // date, more than 30 days back) names the rule; retrying cannot help.
      feedback.showError(
        result.message,
        onRetry: result.failure is ValidationFailure
            ? null
            : () => unawaited(
                setHabitChecked(container, habitId, date, checked: checked),
              ),
      );
    case HabitActionBusy():
      break;
  }
}

/// Archives a habit from tomorrow on (the caller asked for confirmation).
/// Returns whether it was archived.
Future<bool> archiveHabitWithFeedback(
  ProviderContainer container,
  String habitId,
) async {
  final feedback = container.read(feedbackServiceProvider);
  final result = await container
      .read(habitActionsProvider.notifier)
      .archive(habitId);
  switch (result) {
    case HabitActionSucceeded():
      feedback.showSaved(result.message, undo: result.undo);
      return true;
    case HabitActionFailed():
      feedback.showError(
        result.failure is StorageFailure
            ? 'Archivieren fehlgeschlagen. Die Gewohnheit ist unverändert.'
            : result.message,
        onRetry: result.failure is StorageFailure
            ? () => unawaited(archiveHabitWithFeedback(container, habitId))
            : null,
      );
      return false;
    case HabitActionBusy():
      return false;
  }
}

/// Deletes a habit (the caller asked for confirmation). Returns whether it was
/// deleted.
Future<bool> deleteHabitWithFeedback(
  ProviderContainer container,
  String habitId,
) async {
  final feedback = container.read(feedbackServiceProvider);
  final result = await container
      .read(habitActionsProvider.notifier)
      .delete(habitId);
  switch (result) {
    case HabitActionSucceeded():
      feedback.showSaved(result.message, undo: result.undo);
      return true;
    case HabitActionFailed():
      feedback.showError(
        result.failure is StorageFailure
            ? 'Löschen fehlgeschlagen. Die Gewohnheit ist unverändert.'
            : result.message,
        onRetry: result.failure is StorageFailure
            ? () => unawaited(deleteHabitWithFeedback(container, habitId))
            : null,
      );
      return false;
    case HabitActionBusy():
      return false;
  }
}
