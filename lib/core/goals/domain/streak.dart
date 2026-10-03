import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Streak milestones in days. After the last one the next multiple of 100
/// follows.
const List<int> streakMilestones = [3, 7, 14, 30, 60, 100];

/// The smallest milestone greater than [current]; beyond 100 days the next
/// higher multiple of 100 (100 -> 200, 101 -> 200, 199 -> 200, 200 -> 300).
int nextStreakMilestone(int current) {
  for (final milestone in streakMilestones) {
    if (milestone > current) {
      return milestone;
    }
  }
  return (current ~/ 100 + 1) * 100;
}

/// Display status of one day in the seven day calendar.
enum StreakDayStatus {
  /// At least one applicable goal was fulfilled.
  active,

  /// A past day without a fulfilled applicable goal.
  inactive,

  /// Today, not active yet. The streak survives until the end of today.
  todayOpen,

  /// The day lies before the profile start and does not count at all.
  beforeStart,
}

/// One day of the seven day calendar, with its concrete date.
@immutable
final class StreakDay {
  const StreakDay({required this.date, required this.status});

  final LocalDate date;
  final StreakDayStatus status;

  /// Whether the day counts as an active day.
  bool get active => status == StreakDayStatus.active;

  @override
  bool operator ==(Object other) =>
      other is StreakDay && other.date == date && other.status == status;

  @override
  int get hashCode => Object.hash(date, status);

  @override
  String toString() => 'StreakDay($date, ${status.name})';
}

/// The derived streak figures. Nothing here is stored: it is recomputed after
/// every change, so edits, undo, import and deletion can lower it.
@immutable
final class StreakSummary {
  const StreakSummary({
    required this.current,
    required this.longest,
    required this.activeDays,
    required this.nextMilestone,
    required this.todayActive,
    required this.lastSevenDays,
  });

  /// Length of the running streak (see [computeStreak]).
  final int current;

  /// Longest run of consecutive active days since the profile start.
  final int longest;

  /// Number of distinct active days since the profile start.
  final int activeDays;

  /// The next milestone above [current] ([nextStreakMilestone]).
  final int nextMilestone;

  /// Whether today already counts as an active day.
  final bool todayActive;

  /// Seven entries, oldest first, the last one is today.
  final List<StreakDay> lastSevenDays;

  /// Days still missing to the next milestone.
  int get daysUntilNextMilestone => nextMilestone - current;
}

/// Computes the global streak.
///
/// An active day has at least one fulfilled applicable daily goal; the caller
/// derives [isActiveDay] from `DayStatus.isActive` (a day without applicable
/// goals is inactive: no free extension). The predicate must be pure and is
/// only asked for days in `[profileStart, today]`; days before the profile
/// start never count.
///
/// - Today active: [StreakSummary.current] counts the consecutive active days
///   backwards from today.
/// - Today not active (yet): counting starts at yesterday, because the streak
///   lasts until the end of today. If yesterday is inactive as well, it is 0.
/// - `longest`: longest consecutive run since [profileStart] (today included
///   when active).
/// - `activeDays`: number of active days since [profileStart].
///
/// The data layer typically passes `activeDays.contains` of a set it built from
/// the day statuses of `[profileStart, today]`. Only [LocalDate] arithmetic is
/// used, so daylight saving changes and month or year boundaries cannot shift
/// a day.
StreakSummary computeStreak({
  required LocalDate today,
  required LocalDate profileStart,
  required bool Function(LocalDate day) isActiveDay,
}) {
  final scan = _scanSeries(
    first: profileStart,
    last: today,
    today: today,
    isActive: isActiveDay,
  );
  final days = <StreakDay>[];
  for (var back = 6; back >= 0; back--) {
    final date = today.addDays(-back);
    final StreakDayStatus status;
    if (date.isBefore(profileStart)) {
      status = StreakDayStatus.beforeStart;
    } else if (scan.flags[profileStart.daysUntil(date)]) {
      status = StreakDayStatus.active;
    } else if (date == today) {
      status = StreakDayStatus.todayOpen;
    } else {
      status = StreakDayStatus.inactive;
    }
    days.add(StreakDay(date: date, status: status));
  }
  return StreakSummary(
    current: scan.current,
    longest: scan.longest,
    activeDays: scan.activeDays,
    nextMilestone: nextStreakMilestone(scan.current),
    todayActive: scan.flags.isNotEmpty && scan.flags.last,
    lastSevenDays: List.unmodifiable(days),
  );
}

/// Current and longest series of one habit.
@immutable
final class HabitSeries {
  const HabitSeries({required this.current, required this.longest});

  /// Running series (see [computeHabitSeries]).
  final int current;

  /// Longest run of consecutive checked days.
  final int longest;

  @override
  bool operator ==(Object other) =>
      other is HabitSeries &&
      other.current == current &&
      other.longest == longest;

  @override
  int get hashCode => Object.hash(current, longest);

  @override
  String toString() => 'HabitSeries(current: $current, longest: $longest)';
}

/// Computes the series of a single habit with the same calendar rules as the
/// global streak, restricted to the days the habit applies: from [habitStart]
/// up to the day before [archivedFrom] (or today for an active habit).
///
/// An applicable day is active when [isChecked]; the predicate is only asked
/// for applicable days up to today. An unchecked TODAY does not break the
/// series yet (counting starts at yesterday); an unchecked past day does. For
/// an archived habit the series is frozen at its last applicable day: it
/// keeps its length when that day was checked and is 0 otherwise.
HabitSeries computeHabitSeries({
  required LocalDate today,
  required LocalDate habitStart,
  required LocalDate? archivedFrom,
  required bool Function(LocalDate day) isChecked,
}) {
  final archived = archivedFrom;
  final lastApplicable = archived == null
      ? today
      : LocalDate.earlier(today, archived.addDays(-1));
  final scan = _scanSeries(
    first: habitStart,
    last: lastApplicable,
    today: today,
    isActive: isChecked,
  );
  return HabitSeries(current: scan.current, longest: scan.longest);
}

/// Shared calendar rule of the global streak and the habit series.
///
/// Walks the days `[first, last]` once. `current` is the run ending at [last];
/// if [last] is inactive it is the run ending the day before when [last] is
/// today (the day is still open), and 0 for a past [last] (the series broke).
({int current, int longest, int activeDays, List<bool> flags}) _scanSeries({
  required LocalDate first,
  required LocalDate last,
  required LocalDate today,
  required bool Function(LocalDate day) isActive,
}) {
  final flags = <bool>[];
  var run = 0;
  var runBeforeLast = 0;
  var longest = 0;
  var activeDays = 0;
  for (final day in first.rangeTo(last)) {
    if (day == last) {
      runBeforeLast = run;
    }
    final active = isActive(day);
    flags.add(active);
    if (active) {
      run++;
      activeDays++;
      if (run > longest) {
        longest = run;
      }
    } else {
      run = 0;
    }
  }
  final int current;
  if (flags.isEmpty) {
    current = 0;
  } else if (flags.last) {
    current = run;
  } else {
    current = last == today ? runBeforeLast : 0;
  }
  return (
    current: current,
    longest: longest,
    activeDays: activeDays,
    flags: flags,
  );
}
