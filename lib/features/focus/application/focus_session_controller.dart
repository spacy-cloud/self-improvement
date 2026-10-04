import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';

/// The user actions of the focus screens (for result messages).
enum FocusAction {
  start('Fokus gestartet'),
  pause('Pausiert'),
  resume('Fokus fortgesetzt'),
  save('Sitzung gespeichert'),
  discard('Sitzung verworfen'),
  updateNote('Notiz gespeichert'),
  delete('Sitzung gelöscht');

  const FocusAction(this.successMessage);

  /// German confirmation text (snackbar) after the action committed.
  final String successMessage;
}

/// Outcome of a focus action.
sealed class FocusActionResult {
  const FocusActionResult();
}

/// The command committed (or was a no-op because the session already was in
/// the requested state). [outcome] carries the undo for save, discard, note
/// changes and delete.
final class FocusActionDone extends FocusActionResult {
  const FocusActionDone(this.action, this.outcome);

  final FocusAction action;
  final CommandOutcome outcome;

  /// The session that was started or changed.
  String? get sessionId => outcome.entityId;

  /// Inverse action for the snackbar; null if there is nothing to undo.
  UndoAction? get undo => outcome.undo;

  String get message => action.successMessage;
}

/// Not done; nothing was changed. The failure carries a German message and,
/// for a [ValidationFailure], the field errors; for
/// `ConflictFailure(openFocusSession)` it names the open session.
final class FocusActionFailed extends FocusActionResult {
  const FocusActionFailed(this.failure);

  final AppFailure failure;

  Map<String, String> get fieldErrors => switch (failure) {
    ValidationFailure(:final fieldErrors) => fieldErrors,
    _ => const {},
  };

  String get message => failure.userMessage;
}

/// Another action was still running (double tap); nothing happened.
final class FocusActionIgnored extends FocusActionResult {
  const FocusActionIgnored();
}

/// State of [FocusSessionController].
@immutable
final class FocusActionState {
  const FocusActionState({this.busy = false, this.failure});

  /// An action is running: buttons are disabled, further actions are ignored.
  final bool busy;

  /// The failure of the last action; cleared by the next action.
  final AppFailure? failure;
}

/// Runs the actions of the open session and of the history: pause, resume,
/// save ("Sitzung speichern", also "Früher beenden" - the UI confirms the
/// duration so far first), discard, note change and delete.
///
/// Every action is one command. A double tap is ignored while an action runs;
/// a retry after a failure reuses the command id, a new user action gets a new
/// one (`SubmissionTracker`). Starting a session is done by
/// `FocusSetupController`.
class FocusSessionController extends Notifier<FocusActionState> {
  late SubmissionTracker _tracker;

  @override
  FocusActionState build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return const FocusActionState();
  }

  FocusRepository get _repository => ref.read(focusRepositoryProvider);

  /// Pauses the running session [sessionId].
  Future<FocusActionResult> pause(String sessionId) => _run(FocusAction.pause, (
    FocusAction.pause,
    sessionId,
  ), (commandId) => _repository.pause(commandId: commandId, id: sessionId));

  /// Resumes the paused session [sessionId].
  Future<FocusActionResult> resume(String sessionId) => _run(
    FocusAction.resume,
    (FocusAction.resume, sessionId),
    (commandId) => _repository.resume(commandId: commandId, id: sessionId),
  );

  /// Saves the session ("Sitzung speichern"): from awaiting confirmation the
  /// planned time, from running or paused the time so far. A session below one
  /// second fails with a field error under `FocusFields.duration`.
  Future<FocusActionResult> save(String sessionId) => _run(FocusAction.save, (
    FocusAction.save,
    sessionId,
  ), (commandId) => _repository.save(commandId: commandId, id: sessionId));

  /// "Früher beenden": the same as [save] (the UI confirms with the duration
  /// so far before calling it).
  Future<FocusActionResult> finishEarly(String sessionId) => save(sessionId);

  /// Discards the session ("Verwerfen"; the UI confirms first).
  Future<FocusActionResult> discard(String sessionId) => _run(
    FocusAction.discard,
    (FocusAction.discard, sessionId),
    (commandId) => _repository.discard(commandId: commandId, id: sessionId),
  );

  /// Changes the note of a completed session. [expectedRowVersion] is the
  /// version the edit form was loaded with (conflict detection).
  Future<FocusActionResult> updateNote(
    String sessionId,
    String? note, {
    int? expectedRowVersion,
  }) => _run(
    FocusAction.updateNote,
    (FocusAction.updateNote, sessionId, note?.trim() ?? '', expectedRowVersion),
    (commandId) => _repository.updateNote(
      commandId: commandId,
      id: sessionId,
      note: note,
      expectedRowVersion: expectedRowVersion,
    ),
  );

  /// Deletes a completed or discarded session (soft delete with undo).
  Future<FocusActionResult> delete(String sessionId) => _run(
    FocusAction.delete,
    (FocusAction.delete, sessionId),
    (commandId) => _repository.delete(commandId: commandId, id: sessionId),
  );

  /// Forgets the last failure after the UI showed it.
  void clearFailure() {
    if (!state.busy && state.failure != null) {
      state = const FocusActionState();
    }
  }

  Future<FocusActionResult> _run(
    FocusAction action,
    Object fingerprint,
    Future<CommandOutcome> Function(String commandId) call,
  ) async {
    if (state.busy) {
      return const FocusActionIgnored();
    }
    final commandId = _tracker.idFor(fingerprint);
    state = const FocusActionState(busy: true);
    try {
      final outcome = await call(commandId);
      _tracker.completed();
      state = const FocusActionState();
      return FocusActionDone(action, outcome);
    } on AppFailure catch (failure) {
      state = FocusActionState(failure: failure);
      return FocusActionFailed(failure);
    }
  }
}

/// The focus action controller (one per app; actions are serialized).
final focusSessionControllerProvider =
    NotifierProvider<FocusSessionController, FocusActionState>(
      FocusSessionController.new,
    );
