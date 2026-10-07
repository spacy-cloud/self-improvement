import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/workout_daily_goal.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';

/// The active workouts logged today, newest first. Follows the calendar day.
final workoutTodayEntriesProvider = StreamProvider<List<WorkoutEntry>>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(workoutRepositoryProvider).watchBetween(today, today);
});

/// The active rest or skipped mark of today, or null. Follows the calendar day.
final workoutDayMarkTodayProvider = StreamProvider<WorkoutDayMark?>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(workoutDayMarkRepositoryProvider).watchDay(today);
});

/// Today's answer to "Wie war dein Tag?": the workouts and the mark of the day
/// and what they make of it. Independent of the goal and of the weekly count.
final workoutDayStateProvider = Provider<AsyncValue<WorkoutDayState>>((ref) {
  final today = ref.watch(todayProvider);
  final entries = ref.watch(workoutTodayEntriesProvider);
  final mark = ref.watch(workoutDayMarkTodayProvider);
  if (entries.hasError) {
    return AsyncError(entries.error!, entries.stackTrace!);
  }
  if (mark.hasError) {
    return AsyncError(mark.error!, mark.stackTrace!);
  }
  final list = entries.value;
  if (list == null || !mark.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildWorkoutDayState(date: today, workouts: list, mark: mark.value),
  );
});

/// Whether the optional daily goal "Workout heute" counts today: it is switched
/// on in the goal versions of today and the focus module is on (read from the
/// snapshot of today, so the answer is the frozen one). Without the goal the
/// Workout card shows the week.
final workoutDailyGoalAppliesProvider = Provider<AsyncValue<bool>>(
  (ref) => ref
      .watch(todayStatusProvider)
      .whenData(
        (status) =>
            status?.progressOf(GoalType.workoutDaily)?.applicable ?? false,
      ),
);

final workoutDailyGoalPlanProvider = Provider<AsyncValue<WorkoutDailyGoalPlan>>(
  (ref) {
    final today = ref.watch(todayProvider);
    return ref
        .watch(goalVersionsProvider)
        .whenData((versions) => workoutDailyGoalPlanOn(versions, today));
  },
);

// -------------------------------------------------------------------- actions

/// Result of marking or taking back a day.
sealed class WorkoutDayActionResult {
  const WorkoutDayActionResult();
}

/// The command committed; [message] is the German success text. Offer
/// "Rückgängig" with [undo].
final class WorkoutDayActionDone extends WorkoutDayActionResult {
  const WorkoutDayActionDone(this.outcome, this.message);

  final CommandOutcome outcome;
  final String message;

  UndoAction? get undo => outcome.undo;
}

/// Nothing changed; [message] is the German text of the failure.
final class WorkoutDayActionFailed extends WorkoutDayActionResult {
  const WorkoutDayActionFailed(this.failure, this.message);

  final AppFailure failure;
  final String message;
}

/// Ignored: the previous action is still running (a double tap).
final class WorkoutDayActionBusy extends WorkoutDayActionResult {
  const WorkoutDayActionBusy();
}

/// Marks today as a rest day or a skipped day and takes a mark back.
///
/// One action at a time (repeated taps are ignored); a retry of the same action
/// after a failure reuses the command id, so a mark can never apply twice.
class WorkoutDayActionsController extends Notifier<bool> {
  late SubmissionTracker _tracker;

  /// The state is `true` while an action runs.
  @override
  bool build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return false;
  }

  /// Marks today as [kind].
  Future<WorkoutDayActionResult> mark(WorkoutDayMarkKind kind) => _run(
    fingerprint: 'mark:${kind.key}',
    message: workoutDayMarkedMessage(kind),
    command: (commandId) => ref
        .read(workoutDayMarkRepositoryProvider)
        .mark(commandId: commandId, kind: kind),
  );

  /// Takes the mark back: the day is open again.
  Future<WorkoutDayActionResult> takeBack(WorkoutDayMark mark) => _run(
    fingerprint: 'unmark:${mark.id}',
    message: 'Eintrag für heute zurückgenommen',
    command: (commandId) => ref
        .read(workoutDayMarkRepositoryProvider)
        .unmark(commandId: commandId, id: mark.id),
  );

  Future<WorkoutDayActionResult> _run({
    required Object fingerprint,
    required String message,
    required Future<CommandOutcome> Function(String commandId) command,
  }) async {
    if (state) {
      return const WorkoutDayActionBusy();
    }
    final commandId = _tracker.idFor(fingerprint);
    state = true;
    try {
      final outcome = await command(commandId);
      _tracker.completed();
      return WorkoutDayActionDone(outcome, message);
    } on AppFailure catch (failure) {
      return WorkoutDayActionFailed(failure, workoutDayFailureMessage(failure));
    } finally {
      if (ref.mounted) {
        state = false;
      }
    }
  }
}

final workoutDayActionsProvider =
    NotifierProvider<WorkoutDayActionsController, bool>(
      WorkoutDayActionsController.new,
    );

/// The German success text after marking today.
String workoutDayMarkedMessage(WorkoutDayMarkKind kind) => switch (kind) {
  WorkoutDayMarkKind.rest => 'Ruhetag eingetragen',
  WorkoutDayMarkKind.skipped => 'Heute übersprungen',
};

/// The German text of a failed mark or take back. A second entry for the day
/// says so; a storage failure says that nothing was changed.
String workoutDayFailureMessage(AppFailure failure) => switch (failure) {
  ConflictFailure(kind: ConflictKind.invalidState) =>
    'Für heute gibt es schon einen Eintrag.',
  StorageFailure() => 'Speichern fehlgeschlagen. Es wurde nichts geändert.',
  _ => failure.userMessage,
};

/// Marks today as [kind] with one tap: ONE command, then the success message
/// with "Rückgängig" (8 s) AFTER the commit, or the failure message.
///
/// Takes the controller and the feedback service instead of a `WidgetRef`: the
/// caller reads them before it awaits a sheet, so it may disappear in between.
Future<void> markWorkoutDay(
  WorkoutDayActionsController controller,
  FeedbackService feedback,
  WorkoutDayMarkKind kind,
) => _announce(controller.mark(kind), feedback);

/// Takes [mark] back with one tap, with the same feedback as [markWorkoutDay].
Future<void> takeBackWorkoutDay(
  WorkoutDayActionsController controller,
  FeedbackService feedback,
  WorkoutDayMark mark,
) => _announce(controller.takeBack(mark), feedback);

Future<void> _announce(
  Future<WorkoutDayActionResult> action,
  FeedbackService feedback,
) async {
  switch (await action) {
    case WorkoutDayActionDone(:final message, :final undo):
      feedback.showSaved(message, undo: undo);
    case WorkoutDayActionFailed(:final message):
      feedback.showError(message);
    case WorkoutDayActionBusy():
      break;
  }
}
