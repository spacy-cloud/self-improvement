import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A persisted focus session (one row of `focus_sessions`).
///
/// The time is NOT stored as a ticking value: the session keeps finished
/// segments in [accumulatedSeconds] and, only while [FocusStatus.running], the
/// UTC start of the current segment. The remaining time is always derived with
/// `computeFocusElapsed`, so the countdown survives a closed or killed app.
@immutable
final class FocusSession {
  const FocusSession({
    required this.id,
    required this.category,
    required this.plannedSeconds,
    required this.accumulatedSeconds,
    required this.status,
    required this.startedAtUtc,
    required this.timezoneId,
    required this.rowVersion,
    required this.updatedAtUtc,
    this.segmentStartedAtUtc,
    this.endedAtUtc,
    this.completedLocalDate,
    this.note,
    this.gamificationEligible = false,
  });

  final String id;
  final FocusCategory category;

  /// Planned countdown in seconds (300 to 10800).
  final int plannedSeconds;

  /// Seconds of finished segments; never above [plannedSeconds]. For a
  /// completed session this is the saved duration.
  final int accumulatedSeconds;

  final FocusStatus status;

  /// Start of the running segment; set if and only if [status] is running.
  final DateTime? segmentStartedAtUtc;

  /// When the session was started (UTC).
  final DateTime startedAtUtc;

  /// Confirmation time of a completed session (UTC); null otherwise.
  final DateTime? endedAtUtc;

  /// Business date of the confirmation (the whole duration counts on this
  /// day, sessions are never split at midnight). Set if and only if the
  /// session is completed.
  final LocalDate? completedLocalDate;

  /// IANA zone: the zone at the start of the session, replaced by the zone of
  /// the confirmation when the session is completed (it explains
  /// [completedLocalDate]).
  final String timezoneId;

  /// At most 500 characters; only editable for completed sessions.
  final String? note;

  /// Frozen at completion (was gamification enabled then); false before.
  final bool gamificationEligible;

  /// Incremented on every change; used for conflict detection and undo.
  final int rowVersion;

  /// Time of the last change (UTC). For a paused session this is the moment of
  /// the pause, see [pausedAtUtc].
  final DateTime updatedAtUtc;

  /// Whether the session still occupies the single open slot.
  bool get isOpen => status.isOpen;

  /// The planned end while the countdown runs: segment start plus the planned
  /// time that is left. Null in every other state. The reminder engine
  /// schedules the end-of-focus notification for this instant.
  DateTime? get expectedEndUtc {
    final start = segmentStartedAtUtc;
    if (status != FocusStatus.running || start == null) {
      return null;
    }
    return start.add(Duration(seconds: plannedSeconds - accumulatedSeconds));
  }

  /// When the session was paused ("pausiert seit ..."); null unless paused.
  /// A paused session is only changed by the pause itself (and later by
  /// resume/save/discard), so the last change time is the pause time.
  DateTime? get pausedAtUtc =>
      status == FocusStatus.paused ? updatedAtUtc : null;

  /// Returns a copy with the given changes. Nullable fields are replaced
  /// through a function so that `() => null` can clear them.
  FocusSession copyWith({
    FocusStatus? status,
    int? accumulatedSeconds,
    DateTime? Function()? segmentStartedAtUtc,
    DateTime? Function()? endedAtUtc,
    LocalDate? Function()? completedLocalDate,
    String? timezoneId,
    String? Function()? note,
    bool? gamificationEligible,
    int? rowVersion,
    DateTime? updatedAtUtc,
  }) => FocusSession(
    id: id,
    category: category,
    plannedSeconds: plannedSeconds,
    accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
    status: status ?? this.status,
    startedAtUtc: startedAtUtc,
    timezoneId: timezoneId ?? this.timezoneId,
    rowVersion: rowVersion ?? this.rowVersion,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    segmentStartedAtUtc: segmentStartedAtUtc == null
        ? this.segmentStartedAtUtc
        : segmentStartedAtUtc(),
    endedAtUtc: endedAtUtc == null ? this.endedAtUtc : endedAtUtc(),
    completedLocalDate: completedLocalDate == null
        ? this.completedLocalDate
        : completedLocalDate(),
    note: note == null ? this.note : note(),
    gamificationEligible: gamificationEligible ?? this.gamificationEligible,
  );

  @override
  bool operator ==(Object other) =>
      other is FocusSession &&
      other.id == id &&
      other.category == category &&
      other.plannedSeconds == plannedSeconds &&
      other.accumulatedSeconds == accumulatedSeconds &&
      other.status == status &&
      other.segmentStartedAtUtc == segmentStartedAtUtc &&
      other.startedAtUtc == startedAtUtc &&
      other.endedAtUtc == endedAtUtc &&
      other.completedLocalDate == completedLocalDate &&
      other.timezoneId == timezoneId &&
      other.note == note &&
      other.gamificationEligible == gamificationEligible &&
      other.rowVersion == rowVersion &&
      other.updatedAtUtc == updatedAtUtc;

  @override
  int get hashCode => Object.hash(
    id,
    category,
    plannedSeconds,
    accumulatedSeconds,
    status,
    segmentStartedAtUtc,
    startedAtUtc,
    endedAtUtc,
    completedLocalDate,
    timezoneId,
    note,
    gamificationEligible,
    rowVersion,
    updatedAtUtc,
  );

  @override
  String toString() =>
      'FocusSession($id, ${category.key}, ${status.key}, '
      'planned: $plannedSeconds, accumulated: $accumulatedSeconds)';
}
