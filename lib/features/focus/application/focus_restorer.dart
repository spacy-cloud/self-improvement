import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';

/// What [FocusRestorer.restore] found.
enum FocusRestoreOutcome {
  /// There is no open session.
  noOpenSession,

  /// The open session needs no change (running with time left, paused,
  /// awaiting confirmation).
  unchanged,

  /// A running session was past its planned end and is now persisted as
  /// `awaiting_confirmation` (no XP, no focus time until the user confirms).
  movedToAwaitingConfirmation,
}

/// Result of [FocusRestorer.restore].
@immutable
final class FocusRestoreResult {
  const FocusRestoreResult(this.outcome, {this.session, this.elapsed});

  final FocusRestoreOutcome outcome;

  /// The open session as it is persisted after the restoration; null without
  /// an open session.
  final FocusSession? session;

  /// Elapsed and remaining time of [session] at the restoration instant.
  final FocusElapsed? elapsed;
}

/// Restores the open session after the process was closed or the app was
/// resumed.
///
/// The app shell calls [restore] on bootstrap and on every `resumed`
/// lifecycle event. A running session whose planned time has passed is turned
/// into `awaiting_confirmation` through the `markAwaitingConfirmation`
/// command; paused and awaiting sessions stay untouched. Being closed never
/// earns focus time or XP automatically. Afterwards the foreground countdown
/// starts a fresh phase from the persisted state (`onRestored`).
final class FocusRestorer {
  FocusRestorer({
    required this._repository,
    required this._clock,
    required this._ids,
    this._onRestored,
  });

  final FocusRepository _repository;
  final ClockService _clock;
  final IdGenerator _ids;
  final void Function()? _onRestored;

  /// Restores the open session. Safe to call repeatedly (idempotent). Storage
  /// failures are thrown as [AppFailure]; a concurrent change of the session
  /// (saved or discarded in the meantime) is not an error.
  Future<FocusRestoreResult> restore() async {
    try {
      final open = await _repository.findOpen();
      if (open == null) {
        return const FocusRestoreResult(FocusRestoreOutcome.noOpenSession);
      }
      final restoration = restoreSession(open, _clock.nowUtc());
      if (!restoration.movedToAwaitingConfirmation) {
        return FocusRestoreResult(
          FocusRestoreOutcome.unchanged,
          session: open,
          elapsed: restoration.elapsed,
        );
      }
      try {
        await _repository.markAwaitingConfirmation(
          commandId: _ids.newId(),
          id: open.id,
        );
      } on ConflictFailure {
        // The user saved or discarded the session in the meantime.
        return FocusRestoreResult(
          FocusRestoreOutcome.unchanged,
          session: await _repository.findOpen(),
        );
      } on NotFoundFailure {
        return const FocusRestoreResult(FocusRestoreOutcome.noOpenSession);
      }
      return FocusRestoreResult(
        FocusRestoreOutcome.movedToAwaitingConfirmation,
        session: await _repository.findOpen(),
        elapsed: restoration.elapsed,
      );
    } finally {
      _onRestored?.call();
    }
  }
}
