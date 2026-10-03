import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/errors/app_failure.dart';

/// How the user was told about the result of a requested undo.
enum UndoResult {
  /// The inverse mutation was committed.
  undone,

  /// The record was changed in the meantime; nothing was changed.
  conflict,

  /// Persisting failed; nothing was changed.
  failed,
}

/// An action offered to the user for a short time ("Rückgängig", 8 seconds).
///
/// Executing it is a NEW command with its own id; it never overwrites changes
/// made after the original action (row version check inside the undo).
class UndoPresentation {
  UndoPresentation({required this._action, required this._ids});

  final UndoAction _action;
  final IdGenerator _ids;
  var _used = false;

  /// True once [perform] was called; an undo can only be used once.
  bool get used => _used;

  /// German message describing the failure, set when [perform] did not undo.
  String? failureMessage;

  /// Runs the inverse command. Safe against double taps: the second call is
  /// ignored and reports [UndoResult.undone] only if the first succeeded.
  Future<UndoResult> perform() async {
    if (_used) {
      return failureMessage == null ? UndoResult.undone : UndoResult.failed;
    }
    _used = true;
    try {
      await _action.run(_ids.newId());
      return UndoResult.undone;
    } on ConflictFailure catch (failure) {
      failureMessage = failure.userMessage;
      return UndoResult.conflict;
    } on AppFailure catch (failure) {
      failureMessage = failure.userMessage;
      return UndoResult.failed;
    }
  }
}

/// User feedback after commands: success messages with an optional Undo, errors
/// and infos. The Flutter implementation (snack bars) lives in the app shell;
/// feature code only talks to this interface so it stays testable.
abstract interface class FeedbackService {
  /// A success message after a committed command. With [undo] the snack bar
  /// shows "Rückgängig" for 8 seconds (at most one Undo is visible; a new
  /// message replaces the previous one).
  void showSaved(String message, {UndoAction? undo});

  /// An error message (e.g. save failed). It stays until it is dismissed or
  /// the user acts. With [onRetry] the snack bar offers the action
  /// [retryLabel]; the typed input of the form is kept by the caller.
  void showError(
    String message, {
    VoidCallback? onRetry,
    String retryLabel = 'Erneut',
  });

  /// A neutral information message.
  void showInfo(String message);
}

/// The feedback service. Overridden at the app root with the snack bar
/// implementation and in tests with [RecordingFeedbackService].
final feedbackServiceProvider = Provider<FeedbackService>(
  (ref) =>
      throw UnimplementedError('feedbackServiceProvider must be overridden'),
);

/// One recorded feedback call.
class RecordedFeedback {
  RecordedFeedback(this.kind, this.message, [this.undo, this.onRetry]);

  /// `saved`, `error` or `info`.
  final String kind;
  final String message;
  final UndoPresentation? undo;

  /// The retry action of an error (null when none was offered).
  final VoidCallback? onRetry;
}

/// Test double that records feedback calls and lets a test press "Rückgängig".
class RecordingFeedbackService implements FeedbackService {
  RecordingFeedbackService({IdGenerator? ids})
    : _ids = ids ?? const UuidGenerator();

  final IdGenerator _ids;
  final List<RecordedFeedback> events = [];

  RecordedFeedback? get last => events.isEmpty ? null : events.last;

  @override
  void showSaved(String message, {UndoAction? undo}) => events.add(
    RecordedFeedback(
      'saved',
      message,
      undo == null ? null : UndoPresentation(action: undo, ids: _ids),
    ),
  );

  @override
  void showError(
    String message, {
    VoidCallback? onRetry,
    String retryLabel = 'Erneut',
  }) => events.add(RecordedFeedback('error', message, null, onRetry));

  @override
  void showInfo(String message) =>
      events.add(RecordedFeedback('info', message));
}
