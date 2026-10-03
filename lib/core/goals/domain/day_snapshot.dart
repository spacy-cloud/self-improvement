import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The calendar facts of a habit that decide on which days it is a goal.
///
/// Persisted as `habits.started_local_date` and `habits.archived_from_date`.
@immutable
final class HabitSnapshotInput {
  const HabitSnapshotInput({
    required this.id,
    required this.startedOn,
    this.archivedFrom,
  });

  /// Habit id (UUID); unique among the inputs of one snapshot.
  final String id;

  /// First day the habit applies. A habit created today starts today.
  final LocalDate startedOn;

  /// First day the habit no longer applies. Archiving takes effect from
  /// tomorrow, so the data layer stores `tomorrow` here and the habit is still
  /// applicable on the day it was archived. `null` while the habit is active.
  final LocalDate? archivedFrom;

  /// Whether the habit is a daily goal on [day].
  bool applicableOn(LocalDate day) {
    if (day.isBefore(startedOn)) {
      return false;
    }
    final end = archivedFrom;
    return end == null || day.isBefore(end);
  }
}

/// One goal of a day snapshot (persisted as a `daily_goal_snapshots` row).
@immutable
final class GoalSnapshotItem {
  const GoalSnapshotItem({
    required this.goalKey,
    required this.module,
    required this.target,
    required this.applicable,
  });

  /// `GoalType.key` of a daily goal type, or `habit:<id>` (see [habitGoalKey]).
  final String goalKey;

  /// The module this goal depends on (`tasks` for habits).
  final ModuleId module;

  /// The frozen threshold in the unit of the goal type: ml, steps, minutes, or
  /// 1 for the two on/off goals. `null` for habits. It is kept even while
  /// [applicable] is `false`, so restoring an item never needs the goal
  /// versions again.
  final int? target;

  /// Whether the goal counts on this day (enabled and its module active).
  final bool applicable;

  /// The goal type for the five daily keys, `null` for habits and unknown keys.
  GoalType? get type => GoalType.tryParse(goalKey);

  /// The habit id for habit keys, otherwise `null`.
  String? get habitId => habitIdFromKey(goalKey);

  /// A copy with another [applicable] flag; target and module stay frozen.
  GoalSnapshotItem withApplicable(bool value) => GoalSnapshotItem(
    goalKey: goalKey,
    module: module,
    target: target,
    applicable: value,
  );

  @override
  bool operator ==(Object other) =>
      other is GoalSnapshotItem &&
      other.goalKey == goalKey &&
      other.module == module &&
      other.target == target &&
      other.applicable == applicable;

  @override
  int get hashCode => Object.hash(goalKey, module, target, applicable);

  @override
  String toString() =>
      'GoalSnapshotItem($goalKey, ${module.key}, target: $target, '
      'applicable: $applicable)';
}

/// The goals that count on one local day, with their frozen thresholds.
///
/// Items are ordered deterministically: the five daily goal types in
/// `GoalType` enum order, then the applicable habits sorted by habit id. Every
/// snapshot contains all five daily types (not applicable ones included).
@immutable
final class DaySnapshot {
  const DaySnapshot({required this.date, required this.items});

  final LocalDate date;
  final List<GoalSnapshotItem> items;

  /// The item with [goalKey], or `null` when the day has none.
  GoalSnapshotItem? itemFor(String goalKey) {
    for (final item in items) {
      if (item.goalKey == goalKey) {
        return item;
      }
    }
    return null;
  }

  /// The threshold of [goalKey] if it applies on this day, otherwise `null`.
  ///
  /// This is the `applicableTarget` input of `decideStepsEligibility` when
  /// called with `GoalType.steps.key`.
  int? applicableTargetFor(String goalKey) {
    final item = itemFor(goalKey);
    return item != null && item.applicable ? item.target : null;
  }
}

/// Builds the snapshot of [day] from the stored sources, or returns `null` for
/// days before [profileStart] (no snapshot and no goals before the profile
/// started).
///
/// Contract for the data layer:
/// - [versions]: all stored goal versions. Per daily type the version in
///   effect on [day] is used ([effectiveGoalOrDefault]); the snapshot target
///   is frozen from it. A disabled version makes the goal not applicable.
///   Versions that start after [day] never change the day.
/// - [isModuleEnabledOn]: the module status in effect at the END of [day], i.e.
///   the latest module status entry with a local date up to and including
///   [day] (enabled when there is none). Changes made on [day] itself count,
///   changes of later days must not. For today this is the live status, so
///   the snapshot of today masks a module change immediately; for past days
///   it is derived from the history and is not affected by today's choice;
///   for future days it is the current status.
/// - [habits]: all habits including archived ones. A habit contributes an item
///   only on days it applies ([HabitSnapshotInput.applicableOn]); its item is
///   applicable only while the `tasks` module is enabled on that day.
///
/// Workout week goal, meals and XP are not daily goals and never appear.
DaySnapshot? buildDaySnapshot({
  required LocalDate day,
  required LocalDate profileStart,
  required Iterable<GoalVersion> versions,
  required bool Function(ModuleId module, LocalDate day) isModuleEnabledOn,
  required Iterable<HabitSnapshotInput> habits,
}) {
  if (day.isBefore(profileStart)) {
    return null;
  }
  return DaySnapshot(
    date: day,
    items: _deriveItems(
      day: day,
      versions: versions,
      habits: habits,
      isModuleEnabled: (module) => isModuleEnabledOn(module, day),
    ),
  );
}

/// Re-derives the snapshot of TODAY after a module (or habit) change.
///
/// A module change takes effect for today immediately: goals of a disabled
/// module become not applicable, and enabling the module again restores them
/// with the ORIGINAL frozen target and the goal's own enabled flag (a goal that
/// was switched off stays off). Items are never dropped and never retargeted:
/// the targets of [stored] are kept even if [versions] would resolve to
/// something else by now. Habits that became applicable meanwhile (a habit
/// created today) are added.
///
/// Days other than [today] are returned unchanged: a module choice made today
/// never rewrites a past day (and future days are not stored).
///
/// Inputs: [stored] is the persisted snapshot of the day, [versions] and
/// [habits] as for [buildDaySnapshot] (they supply the goal-level enabled
/// flags), [isModuleEnabledNow] the live module status. When the sources are
/// unchanged this equals [buildDaySnapshot] for today with the live status.
DaySnapshot maskTodaySnapshot({
  required LocalDate today,
  required DaySnapshot stored,
  required Iterable<GoalVersion> versions,
  required Iterable<HabitSnapshotInput> habits,
  required bool Function(ModuleId module) isModuleEnabledNow,
}) {
  if (stored.date != today) {
    return stored;
  }
  return DaySnapshot(
    date: today,
    items: _deriveItems(
      day: today,
      versions: versions,
      habits: habits,
      isModuleEnabled: isModuleEnabledNow,
      frozenTargets: {
        for (final item in stored.items) item.goalKey: item.target,
      },
    ),
  );
}

List<GoalSnapshotItem> _deriveItems({
  required LocalDate day,
  required Iterable<GoalVersion> versions,
  required Iterable<HabitSnapshotInput> habits,
  required bool Function(ModuleId module) isModuleEnabled,
  Map<String, int?> frozenTargets = const {},
}) {
  final items = <GoalSnapshotItem>[];
  for (final type in GoalType.dailyTypes) {
    final version = effectiveGoalOrDefault(versions, type, day);
    items.add(
      GoalSnapshotItem(
        goalKey: type.key,
        module: type.module,
        target: frozenTargets.containsKey(type.key)
            ? frozenTargets[type.key]
            : type.resolveTarget(version.target),
        applicable: version.enabled && isModuleEnabled(type.module),
      ),
    );
  }
  final applicableHabits = [
    for (final habit in habits)
      if (habit.applicableOn(day)) habit,
  ]..sort((a, b) => a.id.compareTo(b.id));
  final tasksEnabled = isModuleEnabled(ModuleId.tasks);
  for (final habit in applicableHabits) {
    items.add(
      GoalSnapshotItem(
        goalKey: habitGoalKey(habit.id),
        module: ModuleId.tasks,
        target: null,
        applicable: tasksEnabled,
      ),
    );
  }
  return List.unmodifiable(items);
}
