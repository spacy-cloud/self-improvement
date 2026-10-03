/// Read models of the focus history and of today's focus time (pure).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Whether a saved duration is long enough to qualify for focus XP (300
/// seconds). Qualification also needs eligibility and a free daily slot; the
/// projection decides the final award.
bool focusSecondsQualifyForXp(int seconds) =>
    seconds >= XpRules.focusMinSeconds;

/// How a completed session ended, as shown in the history.
enum FocusHistoryStatus {
  /// The planned time was reached before saving.
  completed('abgeschlossen'),

  /// Saved before the planned time was over ("Früher beenden").
  finishedEarly('früher beendet');

  const FocusHistoryStatus(this.label);

  /// German label.
  final String label;
}

/// One row of the focus history: a COMPLETED session (discarded and open
/// sessions never appear as completed time).
@immutable
final class FocusHistoryEntry {
  const FocusHistoryEntry({
    required this.session,
    required this.date,
    required this.endedLocalTime,
  });

  /// Builds the entry of a completed [session]. The end time is shown in the
  /// zone that was frozen with the session.
  factory FocusHistoryEntry.fromSession(
    FocusSession session,
    ClockService clock,
  ) {
    final ended = session.endedAtUtc ?? session.startedAtUtc;
    final zone = TimeZones.isKnown(session.timezoneId)
        ? session.timezoneId
        : null;
    final local = clock.toLocal(ended, timeZoneId: zone);
    return FocusHistoryEntry(
      session: session,
      date: session.completedLocalDate ?? local.date,
      endedLocalTime: local.time,
    );
  }

  final FocusSession session;

  /// The completion day (frozen at the confirmation).
  final LocalDate date;

  /// Wall clock time of the confirmation in the frozen zone.
  final LocalTime endedLocalTime;

  String get id => session.id;

  FocusCategory get category => session.category;

  String get categoryLabel => session.category.label;

  /// The saved duration in seconds (never above the plan).
  int get actualSeconds => session.accumulatedSeconds;

  /// The saved duration as text, e.g. `20 Min.`.
  String get actualDurationText => formatFocusDuration(actualSeconds);

  /// The confirmation instant (UTC).
  DateTime get endedAtUtc => session.endedAtUtc ?? session.startedAtUtc;

  /// `abgeschlossen` when the plan was reached, else `früher beendet`.
  FocusHistoryStatus get status =>
      session.accumulatedSeconds >= session.plannedSeconds
      ? FocusHistoryStatus.completed
      : FocusHistoryStatus.finishedEarly;

  /// Second line of a list row: `14:30 · abgeschlossen`.
  String get subtitle => '${endedLocalTime.toIso()} · ${status.label}';

  /// Whether the saved time reaches the XP minimum of 5 minutes.
  bool get meetsXpMinimum => focusSecondsQualifyForXp(actualSeconds);

  @override
  bool operator ==(Object other) =>
      other is FocusHistoryEntry &&
      other.session == session &&
      other.date == date &&
      other.endedLocalTime == endedLocalTime;

  @override
  int get hashCode => Object.hash(session, date, endedLocalTime);
}

/// The history entries of one completion day.
@immutable
final class FocusHistoryDay {
  const FocusHistoryDay({required this.date, required this.entries});

  final LocalDate date;

  /// Newest first.
  final List<FocusHistoryEntry> entries;

  /// Saved focus seconds of the day.
  int get totalSeconds =>
      entries.fold(0, (sum, entry) => sum + entry.actualSeconds);
}

/// Groups [entriesNewestFirst] by completion day, newest day first. Within a
/// day the given (newest first) order is kept.
List<FocusHistoryDay> groupFocusHistoryByDay(
  Iterable<FocusHistoryEntry> entriesNewestFirst,
) {
  final byDay = <LocalDate, List<FocusHistoryEntry>>{};
  for (final entry in entriesNewestFirst) {
    byDay.putIfAbsent(entry.date, () => []).add(entry);
  }
  final dates = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      FocusHistoryDay(date: date, entries: List.unmodifiable(byDay[date]!)),
  ];
}

/// Today's focus time: only SAVED durations of completed sessions count.
@immutable
final class FocusTodaySummary {
  const FocusTodaySummary({
    required this.date,
    required this.completedSeconds,
    required this.sessionCount,
    this.goalMinutes,
  });

  final LocalDate date;

  /// Sum of the saved durations of the sessions completed on [date].
  final int completedSeconds;

  /// Number of sessions completed on [date].
  final int sessionCount;

  /// The daily focus goal in minutes, or null when the goal is switched off.
  final int? goalMinutes;

  /// Whole completed minutes (rounded down, like the day ring counts them).
  int get completedMinutes => completedSeconds ~/ 60;

  bool get isEmpty => sessionCount == 0;

  /// Progress towards the goal in `0..1` (capped), null without a goal. The
  /// real time stays in [completedMinutes].
  double? get goalFraction {
    final goal = goalMinutes;
    if (goal == null || goal <= 0) {
      return null;
    }
    final fraction = completedSeconds / (goal * 60);
    return fraction > 1 ? 1 : fraction;
  }

  /// Whether the goal is reached (false without a goal).
  bool get goalReached {
    final goal = goalMinutes;
    return goal != null && completedSeconds >= goal * 60;
  }

  /// Minutes still missing to the goal (rounded up, 0 once reached), null
  /// without a goal.
  int? get remainingGoalMinutes {
    final goal = goalMinutes;
    if (goal == null) {
      return null;
    }
    final missing = goal * 60 - completedSeconds;
    return missing <= 0 ? 0 : (missing + 59) ~/ 60;
  }
}

/// The daily focus goal in minutes that applies on [day] (the goal version in
/// effect, or the default of 25 minutes), or null when the goal is switched
/// off.
int? focusGoalMinutesOn(Iterable<GoalVersion> versions, LocalDate day) {
  final goal = effectiveGoalOrDefault(versions, GoalType.focusMinutes, day);
  return goal.enabled ? GoalType.focusMinutes.resolveTarget(goal.target) : null;
}

/// Today's summary from [sessions] (any statuses and days): only COMPLETED
/// sessions whose completion day is [today] count, with their saved duration.
/// Running, paused, awaiting and discarded sessions add nothing.
FocusTodaySummary buildFocusTodaySummary(
  Iterable<FocusSession> sessions, {
  required LocalDate today,
  int? goalMinutes,
}) {
  var seconds = 0;
  var count = 0;
  for (final session in sessions) {
    if (session.status == FocusStatus.completed &&
        session.completedLocalDate == today) {
      seconds += session.accumulatedSeconds;
      count++;
    }
  }
  return FocusTodaySummary(
    date: today,
    completedSeconds: seconds,
    sessionCount: count,
    goalMinutes: goalMinutes,
  );
}
