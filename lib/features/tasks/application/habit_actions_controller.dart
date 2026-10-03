import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Which habit actions are running right now. Use it to disable the checkbox
/// of a day or the archive/delete buttons while their command runs (repeated
/// taps are ignored anyway, the state only makes that visible).
@immutable
final class HabitActionsState {
  const HabitActionsState({this.busyKeys = const {}, this.undoRunning = false});

  /// Busy keys: one per running check command (habit and day) and one per
  /// running archive or delete command (habit).
  final Set<String> busyKeys;

  /// True while an undo runs.
  final bool undoRunning;

  /// Whether the check of [habitId] on [date] is being set right now.
  bool isCheckBusy(String habitId, LocalDate date) =>
      busyKeys.contains(HabitActionsController.checkKey(habitId, date));

  /// Whether an archive or delete of [habitId] is running right now.
  bool isHabitBusy(String habitId) => busyKeys.contains(habitId);
}

/// Result of a habit action (check, uncheck, archive, delete, undo).
sealed class HabitActionResult {
  const HabitActionResult();
}

/// The command committed or was a harmless no-op / replay.
///
/// [message] is the German success text for the snackbar. Offer "Rückgängig"
/// only when [undo] is not null: a no-op (the day already had the desired
/// state), a replay and the final archiving carry no undo.
final class HabitActionSucceeded extends HabitActionResult {
  const HabitActionSucceeded(this.outcome, this.message);

  final CommandOutcome outcome;
  final String message;

  UndoAction? get undo => outcome.undo;
}

/// The command did not commit; nothing changed. [message] is the German text
/// for the snackbar (for a date outside the window it names the rule).
final class HabitActionFailed extends HabitActionResult {
  const HabitActionFailed(this.failure);

  final AppFailure failure;

  String get message => failure.userMessage;
}

/// Ignored: the same action is already running (or another undo is running).
final class HabitActionBusy extends HabitActionResult {
  const HabitActionBusy();
}

/// Commands of the habit list and the habit detail: set a check for a day (a
/// desired state), archive, delete and undo.
///
/// Every call is one user action with its own command id; repeated taps while a
/// command runs are ignored ([HabitActionBusy]); a retry after a failure of the
/// same action reuses the failed attempt's id so it can never apply twice.
class HabitActionsController extends Notifier<HabitActionsState> {
  late Map<String, SubmissionTracker> _trackers;

  /// The busy key of a check command.
  static String checkKey(String habitId, LocalDate date) =>
      '$habitId|${date.toIso()}';

  @override
  HabitActionsState build() {
    _trackers = {};
    return const HabitActionsState();
  }

  /// Sets the check of [habitId] on [date] to the DESIRED state (never a
  /// toggle). Allowed are the habit's start day up to today, at most 30 days
  /// back; other dates fail with the German rule text. Checking a day that is
  /// already checked is a success without undo.
  Future<HabitActionResult> setChecked(
    String habitId,
    LocalDate date, {
    required bool checked,
  }) => _run(
    checkKey(habitId, date),
    fingerprint: checked ? 'check' : 'uncheck',
    message: checked ? 'Abgehakt' : 'Haken entfernt',
    command: (commandId) => ref
        .read(habitRepositoryProvider)
        .setChecked(
          commandId: commandId,
          habitId: habitId,
          date: date,
          checked: checked,
        ),
  );

  /// Archives the habit from TOMORROW on (the UI asks for confirmation first).
  /// Today it still applies; checks and history stay. Archiving is final, so
  /// the success carries no undo.
  Future<HabitActionResult> archive(String habitId) => _run(
    habitId,
    fingerprint: 'archive',
    message: habitArchivePendingHint,
    command: (commandId) => ref
        .read(habitRepositoryProvider)
        .archive(commandId: commandId, id: habitId),
  );

  /// Soft-deletes the habit (the UI asks for confirmation first); its checks
  /// stop counting. The success carries an undo.
  Future<HabitActionResult> delete(String habitId) => _run(
    habitId,
    fingerprint: 'delete',
    message: 'Gewohnheit gelöscht',
    command: (commandId) => ref
        .read(habitRepositoryProvider)
        .delete(commandId: commandId, id: habitId),
  );

  /// Runs the inverse of an earlier action (the snackbar's "Rückgängig"). A
  /// record that changed since is reported as a conflict, never overwritten.
  Future<HabitActionResult> undo(UndoAction action) async {
    if (state.undoRunning) {
      return const HabitActionBusy();
    }
    state = HabitActionsState(busyKeys: state.busyKeys, undoRunning: true);
    try {
      final outcome = await action.run(ref.read(idGeneratorProvider).newId());
      return HabitActionSucceeded(outcome, 'Rückgängig gemacht');
    } on AppFailure catch (failure) {
      return HabitActionFailed(failure);
    } finally {
      if (ref.mounted) {
        state = HabitActionsState(busyKeys: state.busyKeys);
      }
    }
  }

  Future<HabitActionResult> _run(
    String busyKey, {
    required Object fingerprint,
    required String message,
    required Future<CommandOutcome> Function(String commandId) command,
  }) async {
    if (state.busyKeys.contains(busyKey)) {
      return const HabitActionBusy();
    }
    final tracker = _trackers.putIfAbsent(
      busyKey,
      () => SubmissionTracker(ref.read(idGeneratorProvider)),
    );
    final commandId = tracker.idFor(fingerprint);
    state = HabitActionsState(
      busyKeys: {...state.busyKeys, busyKey},
      undoRunning: state.undoRunning,
    );
    try {
      final outcome = await command(commandId);
      tracker.completed();
      return HabitActionSucceeded(outcome, message);
    } on AppFailure catch (failure) {
      return HabitActionFailed(failure);
    } finally {
      if (ref.mounted) {
        state = HabitActionsState(
          busyKeys: {...state.busyKeys}..remove(busyKey),
          undoRunning: state.undoRunning,
        );
      }
    }
  }
}

final habitActionsProvider =
    NotifierProvider<HabitActionsController, HabitActionsState>(
      HabitActionsController.new,
    );
