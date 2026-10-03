import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Default length of the water history window in local days (including today).
const int defaultWaterHistoryDays = 14;

/// Sum of the amounts in ml.
int sumWaterMl(Iterable<WaterEntry> entries) =>
    entries.fold<int>(0, (sum, entry) => sum + entry.amountMl);

/// The real percentage of [targetMl] reached by [totalMl], rounded half up
/// (`112` for 2800 of 2500 ml). It is never 100 while the target is not
/// reached: 2490 of 2500 ml shows `99`, so "100 %" and "goal reached" always
/// agree.
int waterPercent({required int totalMl, required int targetMl}) {
  assert(targetMl > 0, 'a target is always positive');
  final rounded = (totalMl * 200 + targetMl) ~/ (2 * targetMl);
  if (totalMl < targetMl && rounded > 99) {
    return 99;
  }
  return rounded;
}

/// The daily water target of [day] in ml, or null when no water goal applies.
///
/// - A stored [snapshot] of the day wins: its frozen threshold, or null when
///   its water item is not applicable (goal switched off or module off).
/// - Without a snapshot: null before [profileStart] (no goals exist before the
///   profile start) or while the nutrition module is off
///   ([nutritionEnabledOnDay]); otherwise the goal version in effect on [day]
///   (the default of 2500 ml when none is stored), null when that version is
///   switched off.
int? resolveWaterTarget({
  required LocalDate day,
  required Iterable<GoalVersion> versions,
  required bool nutritionEnabledOnDay,
  DaySnapshot? snapshot,
  LocalDate? profileStart,
}) {
  final item = snapshot?.itemFor(GoalType.water.key);
  if (item != null) {
    return item.applicable ? GoalType.water.resolveTarget(item.target) : null;
  }
  if (profileStart != null && day.isBefore(profileStart)) {
    return null;
  }
  if (!nutritionEnabledOnDay) {
    return null;
  }
  final version = effectiveGoalOrDefault(versions, GoalType.water, day);
  return version.enabled ? GoalType.water.resolveTarget(version.target) : null;
}

/// Everything the water screen and the dashboard card show for one day,
/// derived from the database.
///
/// The progress fields exist only with a target: without one (goal switched
/// off or not applicable) [targetMl], [fraction], [percent] and
/// [remainingMl] are null and [goalReached] is false; only the real total and
/// the entries remain.
@immutable
final class WaterToday {
  const WaterToday({
    required this.date,
    required this.totalMl,
    required this.entriesNewestFirst,
    this.targetMl,
    this.fraction,
    this.percent,
    this.remainingMl,
    this.goalReached = false,
  });

  /// The local calendar day.
  final LocalDate date;

  /// Sum of the active entries of [date] in ml (the real amount, never capped).
  final int totalMl;

  /// The day's threshold in ml: the frozen snapshot target, or the goal in
  /// effect. Null when no water goal applies.
  final int? targetMl;

  /// Progress bar value in 0..1, capped at 1.0. Null without a target.
  final double? fraction;

  /// Real percentage, uncapped (`112` for 2800 of 2500 ml). Null without a
  /// target; see [waterPercent] for the rounding.
  final int? percent;

  /// ml still missing to the target, 0 once reached. Null without a target.
  final int? remainingMl;

  /// Whether [totalMl] reached or exceeded [targetMl]. Reaching the target
  /// creates no extra record.
  final bool goalReached;

  /// The day's active entries, newest first.
  final List<WaterEntry> entriesNewestFirst;

  bool get hasTarget => targetMl != null;

  bool get isEmpty => entriesNewestFirst.isEmpty;

  int get entryCount => entriesNewestFirst.length;

  @override
  bool operator ==(Object other) =>
      other is WaterToday &&
      other.date == date &&
      other.totalMl == totalMl &&
      other.targetMl == targetMl &&
      other.fraction == fraction &&
      other.percent == percent &&
      other.remainingMl == remainingMl &&
      other.goalReached == goalReached &&
      listEquals(other.entriesNewestFirst, entriesNewestFirst);

  @override
  int get hashCode => Object.hash(
    date,
    totalMl,
    targetMl,
    fraction,
    percent,
    remainingMl,
    goalReached,
    Object.hashAll(entriesNewestFirst),
  );
}

/// Builds the model of [date] from its active [entries] (any order) and the
/// day's [targetMl] (null when no goal applies). Pure.
WaterToday buildWaterToday({
  required LocalDate date,
  required Iterable<WaterEntry> entries,
  required int? targetMl,
}) {
  final sorted = [...entries]..sort(compareWaterNewestFirst);
  final total = sumWaterMl(sorted);
  // A target is always positive; anything else cannot be a goal.
  if (targetMl == null || targetMl <= 0) {
    return WaterToday(
      date: date,
      totalMl: total,
      entriesNewestFirst: List.unmodifiable(sorted),
    );
  }
  final reached = total >= targetMl;
  return WaterToday(
    date: date,
    totalMl: total,
    targetMl: targetMl,
    fraction: reached ? 1.0 : total / targetMl,
    percent: waterPercent(totalMl: total, targetMl: targetMl),
    remainingMl: reached ? 0 : targetMl - total,
    goalReached: reached,
    entriesNewestFirst: List.unmodifiable(sorted),
  );
}

/// One local day of the water history.
@immutable
final class WaterHistoryDay {
  const WaterHistoryDay({
    required this.date,
    required this.totalMl,
    required this.entriesNewestFirst,
    this.targetMl,
    this.goalReached = false,
  });

  final LocalDate date;

  /// Sum of the day's active entries in ml.
  final int totalMl;

  /// The day's threshold (frozen snapshot, else the goal in effect); null when
  /// no goal applied that day.
  final int? targetMl;

  /// Whether the day's total reached its own threshold.
  final bool goalReached;

  /// The day's active entries, newest first.
  final List<WaterEntry> entriesNewestFirst;

  int get entryCount => entriesNewestFirst.length;

  @override
  bool operator ==(Object other) =>
      other is WaterHistoryDay &&
      other.date == date &&
      other.totalMl == totalMl &&
      other.targetMl == targetMl &&
      other.goalReached == goalReached &&
      listEquals(other.entriesNewestFirst, entriesNewestFirst);

  @override
  int get hashCode => Object.hash(
    date,
    totalMl,
    targetMl,
    goalReached,
    Object.hashAll(entriesNewestFirst),
  );
}

/// Water entries grouped per local day, newest day first. Only days with at
/// least one active entry appear (a missing day is "nothing recorded", not a
/// zero).
@immutable
final class WaterHistory {
  const WaterHistory({required this.days, required this.daysNewestFirst});

  /// Length of the window in local days, including today.
  final int days;

  final List<WaterHistoryDay> daysNewestFirst;

  bool get isEmpty => daysNewestFirst.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is WaterHistory &&
      other.days == days &&
      listEquals(other.daysNewestFirst, daysNewestFirst);

  @override
  int get hashCode => Object.hash(days, Object.hashAll(daysNewestFirst));
}

/// Groups [entries] (any order) per stored local day, newest day first, each
/// day with its newest-first entries, total and threshold ([targetFor] returns
/// null when no goal applied that day). Pure.
WaterHistory buildWaterHistory({
  required int days,
  required Iterable<WaterEntry> entries,
  required int? Function(LocalDate day) targetFor,
}) {
  final byDay = <LocalDate, List<WaterEntry>>{};
  for (final entry in entries) {
    byDay.putIfAbsent(entry.localDate, () => []).add(entry);
  }
  final dates = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return WaterHistory(
    days: days,
    daysNewestFirst: List.unmodifiable([
      for (final date in dates)
        _historyDay(date, byDay[date]!, targetFor(date)),
    ]),
  );
}

WaterHistoryDay _historyDay(
  LocalDate date,
  List<WaterEntry> entries,
  int? targetMl,
) {
  final sorted = [...entries]..sort(compareWaterNewestFirst);
  final total = sumWaterMl(sorted);
  return WaterHistoryDay(
    date: date,
    totalMl: total,
    targetMl: targetMl,
    goalReached: targetMl != null && targetMl > 0 && total >= targetMl,
    entriesNewestFirst: List.unmodifiable(sorted),
  );
}

/// The state of the daily water goal as the goal editor needs it.
///
/// Goal changes apply from tomorrow: [todayTargetMl] is what counts today,
/// [tomorrowTargetMl] and [tomorrowEnabled] are what will count from
/// [effectiveFrom] (a change made today is already visible here).
@immutable
final class WaterGoalSettings {
  const WaterGoalSettings({
    required this.effectiveFrom,
    required this.todayTargetMl,
    required this.tomorrowTargetMl,
    required this.tomorrowEnabled,
  });

  /// The day a change made today takes effect (tomorrow).
  final LocalDate effectiveFrom;

  /// Today's threshold; null when no goal applies today.
  final int? todayTargetMl;

  /// The stored target from [effectiveFrom] on (kept even while the goal is
  /// switched off).
  final int tomorrowTargetMl;

  /// Whether the goal is switched on from [effectiveFrom] on.
  final bool tomorrowEnabled;

  /// Whether tomorrow's goal differs from today's (the UI shows "gilt ab
  /// morgen").
  bool get hasPendingChange =>
      todayTargetMl != (tomorrowEnabled ? tomorrowTargetMl : null);

  @override
  bool operator ==(Object other) =>
      other is WaterGoalSettings &&
      other.effectiveFrom == effectiveFrom &&
      other.todayTargetMl == todayTargetMl &&
      other.tomorrowTargetMl == tomorrowTargetMl &&
      other.tomorrowEnabled == tomorrowEnabled;

  @override
  int get hashCode => Object.hash(
    effectiveFrom,
    todayTargetMl,
    tomorrowTargetMl,
    tomorrowEnabled,
  );
}

/// Builds [WaterGoalSettings] from all stored goal [versions]. Pure.
WaterGoalSettings buildWaterGoalSettings({
  required Iterable<GoalVersion> versions,
  required LocalDate today,
  required int? todayTargetMl,
}) {
  final effectiveFrom = nextEffectiveDate(today);
  final version = effectiveGoalOrDefault(
    versions,
    GoalType.water,
    effectiveFrom,
  );
  return WaterGoalSettings(
    effectiveFrom: effectiveFrom,
    todayTargetMl: todayTargetMl,
    tomorrowTargetMl: GoalType.water.resolveTarget(version.target),
    tomorrowEnabled: version.enabled,
  );
}
