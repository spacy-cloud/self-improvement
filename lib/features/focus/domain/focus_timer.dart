/// The pure focus timer rules (specification section 8.2): elapsed time,
/// state transitions, restoration after a closed app and input validation.
///
/// Nothing here touches the database or reads a clock: every function receives
/// the instants it needs, so each rule is unit-testable. The repository applies
/// the returned [FocusTransition]s inside a command.
///
/// ## State transitions
///
/// | Command | running | paused | awaiting_confirmation | completed | discarded |
/// |---|---|---|---|---|---|
/// | pause | paused (or awaiting if the plan is over) | no-op | refused | refused | refused |
/// | resume | no-op | running (new segment) | refused | refused | refused |
/// | await confirmation | awaiting (accumulated = plan) | refused (awaiting if accumulated = plan) | no-op | refused | refused |
/// | save | completed | completed | completed | no-op | refused |
/// | discard | discarded | discarded | discarded | refused | no-op |
///
/// "No-op" means the session already is in the requested state (a double tap
/// or a replay with a new command id changes nothing); "refused" is a
/// `ConflictFailure(invalidState)`.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Shortest planned countdown: 5 minutes.
const int minFocusPlannedSeconds = 300;

/// Longest planned countdown: 180 minutes.
const int maxFocusPlannedSeconds = 10800;

/// Planned countdown preselected in the setup: 25 minutes.
const int defaultFocusPlannedSeconds = 1500;

/// Step of the duration stepper: 5 minutes.
const int focusPlanStepSeconds = 300;

/// A session can be saved from this duration on (1 second).
const int minFocusSavedSeconds = 1;

/// Maximum length of a session note (characters).
const int maxFocusNoteLength = 500;

/// Field keys of focus inputs (keys of [ValidationFailure.fieldErrors]).
abstract final class FocusFields {
  /// The planned duration of a new session.
  static const String planned = 'planned';

  /// The duration of the session that is being saved.
  static const String duration = 'duration';

  /// The note of a completed session.
  static const String note = 'note';
}

/// Shown when the device clock obviously went back during a session.
const String focusClockAnomalyMessage =
    'Die Uhr des Geräts wurde zurückgestellt. Bitte prüfe die Sitzungsdauer.';

/// German message for a planned duration outside 5 to 180 minutes.
const String focusPlanRangeMessage =
    'Bitte wähle eine Dauer zwischen 5 und 180 Minuten.';

/// German message when a session is shorter than one second.
const String focusTooShortMessage =
    'Die Sitzung ist zu kurz zum Speichern. Es wird mindestens eine Sekunde '
    'benötigt.';

/// German message for a note longer than [maxFocusNoteLength].
const String focusNoteTooLongMessage =
    'Die Notiz darf höchstens $maxFocusNoteLength Zeichen lang sein.';

/// Throws a [ValidationFailure] unless [plannedSeconds] is within 300 to 10800
/// (5 to 180 minutes, both inclusive).
void validateFocusPlan(int plannedSeconds) {
  if (plannedSeconds < minFocusPlannedSeconds ||
      plannedSeconds > maxFocusPlannedSeconds) {
    throw ValidationFailure.field(FocusFields.planned, focusPlanRangeMessage);
  }
}

/// Trims a note; blank means no note (null). More than 500 characters is a
/// [ValidationFailure].
String? normalizeFocusNote(String? note) {
  final trimmed = note?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (trimmed.runes.length > maxFocusNoteLength) {
    throw ValidationFailure.field(FocusFields.note, focusNoteTooLongMessage);
  }
  return trimmed;
}

/// Elapsed and remaining time of a session at one instant.
@immutable
final class FocusElapsed {
  const FocusElapsed({
    required this.elapsedSeconds,
    required this.remainingSeconds,
    required this.clockAnomaly,
  });

  /// Seconds of focus time so far, in `0..planned`.
  final int elapsedSeconds;

  /// `planned - elapsed`.
  final int remainingSeconds;

  /// True when the running segment lies in the future: the device clock was
  /// set back. The negative difference counts as 0 seconds; the UI asks the
  /// user to check the duration ([focusClockAnomalyMessage]).
  final bool clockAnomaly;

  /// The planned time is over.
  bool get reachedPlan => remainingSeconds <= 0;

  @override
  bool operator ==(Object other) =>
      other is FocusElapsed &&
      other.elapsedSeconds == elapsedSeconds &&
      other.remainingSeconds == remainingSeconds &&
      other.clockAnomaly == clockAnomaly;

  @override
  int get hashCode =>
      Object.hash(elapsedSeconds, remainingSeconds, clockAnomaly);

  @override
  String toString() =>
      'FocusElapsed($elapsedSeconds elapsed, $remainingSeconds remaining'
      '${clockAnomaly ? ', clock anomaly' : ''})';
}

/// Elapsed time of [session] at [nowUtc].
///
/// While running: `elapsed = clamp(accumulated + floor(now - segmentStart), 0,
/// planned)`. A negative difference (clock set back) counts as 0 and sets
/// [FocusElapsed.clockAnomaly]. Paused: the accumulated value. Awaiting
/// confirmation: the planned time. Completed and discarded: the stored value.
/// The elapsed time never exceeds the plan.
FocusElapsed computeFocusElapsed(FocusSession session, DateTime nowUtc) {
  final planned = session.plannedSeconds;
  var anomaly = false;
  final int raw;
  switch (session.status) {
    case FocusStatus.running:
      var segmentSeconds = 0;
      final start = session.segmentStartedAtUtc;
      if (start != null) {
        if (nowUtc.isBefore(start)) {
          anomaly = true;
        } else {
          segmentSeconds = nowUtc.difference(start).inSeconds;
        }
      }
      raw = session.accumulatedSeconds + segmentSeconds;
    case FocusStatus.awaitingConfirmation:
      raw = planned;
    case FocusStatus.paused:
    case FocusStatus.completed:
    case FocusStatus.discarded:
      raw = session.accumulatedSeconds;
  }
  final elapsed = raw.clamp(0, planned);
  return FocusElapsed(
    elapsedSeconds: elapsed,
    remainingSeconds: planned - elapsed,
    clockAnomaly: anomaly,
  );
}

/// Result of a pure state transition.
@immutable
final class FocusTransition {
  const FocusTransition._(this.session, {required this.changed});

  /// The session already was in the requested state (nothing to persist).
  const FocusTransition.unchanged(FocusSession session)
    : this._(session, changed: false);

  /// The session after the transition (persist it).
  const FocusTransition.changed(FocusSession session)
    : this._(session, changed: true);

  /// The session after the transition.
  final FocusSession session;

  /// Whether the transition changed anything.
  final bool changed;
}

ConflictFailure _invalidState(FocusSession session) =>
    ConflictFailure(ConflictKind.invalidState, relatedEntityId: session.id);

/// `awaiting_confirmation`: the plan is over, accumulated = planned, no
/// running segment.
FocusSession _awaiting(FocusSession session) => session.copyWith(
  status: FocusStatus.awaitingConfirmation,
  accumulatedSeconds: session.plannedSeconds,
  segmentStartedAtUtc: () => null,
);

/// Pause: adds the seconds since the last segment start to the accumulated
/// value (clamped to the plan) and stops the segment. If the planned time is
/// already over, the session becomes `awaiting_confirmation` instead.
FocusTransition pauseFocus(FocusSession session, DateTime nowUtc) {
  switch (session.status) {
    case FocusStatus.paused:
      return FocusTransition.unchanged(session);
    case FocusStatus.running:
      final elapsed = computeFocusElapsed(session, nowUtc);
      if (elapsed.reachedPlan) {
        return FocusTransition.changed(_awaiting(session));
      }
      return FocusTransition.changed(
        session.copyWith(
          status: FocusStatus.paused,
          accumulatedSeconds: elapsed.elapsedSeconds,
          segmentStartedAtUtc: () => null,
        ),
      );
    case FocusStatus.awaitingConfirmation:
    case FocusStatus.completed:
    case FocusStatus.discarded:
      throw _invalidState(session);
  }
}

/// Resume: keeps the accumulated value and starts a new UTC segment at
/// [nowUtc]. A paused session whose plan is already used up goes to
/// `awaiting_confirmation` instead.
FocusTransition resumeFocus(FocusSession session, DateTime nowUtc) {
  switch (session.status) {
    case FocusStatus.running:
      return FocusTransition.unchanged(session);
    case FocusStatus.paused:
      if (session.accumulatedSeconds >= session.plannedSeconds) {
        return FocusTransition.changed(_awaiting(session));
      }
      return FocusTransition.changed(
        session.copyWith(
          status: FocusStatus.running,
          segmentStartedAtUtc: () => nowUtc,
        ),
      );
    case FocusStatus.awaitingConfirmation:
    case FocusStatus.completed:
    case FocusStatus.discarded:
      throw _invalidState(session);
  }
}

/// The countdown reached zero: elapsed = planned, status
/// `awaiting_confirmation`. No XP and no completed record yet.
///
/// Trusts the caller that the time is over (the foreground countdown measures
/// it monotonically, the restoration checks the persisted segments); it does
/// not re-check against the wall clock. A paused session may only move on if
/// its plan is already used up.
FocusTransition awaitFocusConfirmation(FocusSession session) {
  switch (session.status) {
    case FocusStatus.awaitingConfirmation:
      return FocusTransition.unchanged(session);
    case FocusStatus.running:
      return FocusTransition.changed(_awaiting(session));
    case FocusStatus.paused:
      if (session.accumulatedSeconds >= session.plannedSeconds) {
        return FocusTransition.changed(_awaiting(session));
      }
      throw _invalidState(session);
    case FocusStatus.completed:
    case FocusStatus.discarded:
      throw _invalidState(session);
  }
}

/// "Sitzung speichern" (also "Früher beenden" from running or paused).
///
/// The saved duration is the elapsed time at [nowUtc] (running), the
/// accumulated time (paused) or the planned time (awaiting confirmation). The
/// end is the confirmation time, the whole duration counts on
/// [completedDate] (the local date of the confirmation, frozen with
/// [timezoneId]); [eligible] is frozen for the XP rules. Less than one second
/// is a [ValidationFailure]. Saving an already completed session is a no-op.
FocusTransition completeFocus(
  FocusSession session, {
  required DateTime nowUtc,
  required LocalDate completedDate,
  required String timezoneId,
  required bool eligible,
}) {
  switch (session.status) {
    case FocusStatus.completed:
      return FocusTransition.unchanged(session);
    case FocusStatus.discarded:
      throw _invalidState(session);
    case FocusStatus.running:
    case FocusStatus.paused:
    case FocusStatus.awaitingConfirmation:
      final seconds = computeFocusElapsed(session, nowUtc).elapsedSeconds;
      if (seconds < minFocusSavedSeconds) {
        throw ValidationFailure.field(
          FocusFields.duration,
          focusTooShortMessage,
        );
      }
      return FocusTransition.changed(
        session.copyWith(
          status: FocusStatus.completed,
          accumulatedSeconds: seconds,
          segmentStartedAtUtc: () => null,
          endedAtUtc: () => nowUtc,
          completedLocalDate: () => completedDate,
          timezoneId: timezoneId,
          gamificationEligible: eligible,
        ),
      );
  }
}

/// "Verwerfen": the session never counts (no completed date, no duration
/// aggregation, no XP). The time spent so far stays in `accumulated_seconds`
/// for the record. Discarding a discarded session is a no-op.
FocusTransition discardFocus(FocusSession session, DateTime nowUtc) {
  switch (session.status) {
    case FocusStatus.discarded:
      return FocusTransition.unchanged(session);
    case FocusStatus.completed:
      throw _invalidState(session);
    case FocusStatus.running:
    case FocusStatus.paused:
    case FocusStatus.awaitingConfirmation:
      return FocusTransition.changed(
        session.copyWith(
          status: FocusStatus.discarded,
          accumulatedSeconds: computeFocusElapsed(
            session,
            nowUtc,
          ).elapsedSeconds,
          segmentStartedAtUtc: () => null,
        ),
      );
  }
}

/// The state of an open session after a process restart.
@immutable
final class FocusRestoration {
  const FocusRestoration({
    required this.session,
    required this.elapsed,
    required this.movedToAwaitingConfirmation,
  });

  /// The session as it must be persisted now.
  final FocusSession session;

  /// Elapsed and remaining time of [session] at the restoration instant.
  final FocusElapsed elapsed;

  /// True when a running session was past its planned end: it is turned into
  /// `awaiting_confirmation` (no automatic XP, no automatic focus time).
  final bool movedToAwaitingConfirmation;
}

/// Restores [session] at [nowUtc] (app start or resume).
///
/// A running session whose planned time has passed becomes
/// `awaiting_confirmation` with accumulated = planned; a running session with
/// time left stays running (the remaining time is recomputed from the UTC
/// segment); paused, awaiting and final sessions are left untouched. Being
/// closed never earns focus time or XP: the user still has to confirm.
FocusRestoration restoreSession(FocusSession session, DateTime nowUtc) {
  final elapsed = computeFocusElapsed(session, nowUtc);
  if (session.status == FocusStatus.running && elapsed.reachedPlan) {
    final restored = _awaiting(session);
    return FocusRestoration(
      session: restored,
      elapsed: computeFocusElapsed(restored, nowUtc),
      movedToAwaitingConfirmation: true,
    );
  }
  return FocusRestoration(
    session: session,
    elapsed: elapsed,
    movedToAwaitingConfirmation: false,
  );
}
