import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/shared/local_date.dart';

/// One stored version of a goal: target and enabled flag that apply from
/// [effectiveFrom] (inclusive) until the next version of the same [type].
///
/// Persisted as `goal_versions`; unique per (type, effectiveFrom). Edits of a
/// goal never touch past or current days: they create (or replace) the version
/// that takes effect tomorrow, see [nextEffectiveDate] and [applyGoalChange].
@immutable
final class GoalVersion {
  const GoalVersion({
    required this.type,
    this.target,
    this.enabled = true,
    required this.effectiveFrom,
  });

  /// The implicit version of a type that has no stored version at all: the
  /// planning default, enabled, valid since the beginning of the calendar.
  factory GoalVersion.implicitDefault(GoalType type) => GoalVersion(
    type: type,
    target: type.defaultTarget,
    effectiveFrom: _beginningOfCalendar,
  );

  static final LocalDate _beginningOfCalendar = LocalDate(1, 1, 1);

  final GoalType type;

  /// Target in the unit of the type. `null` (or any value for switch goals)
  /// is resolved through [GoalType.resolveTarget].
  final int? target;

  /// Whether the goal is switched on. A disabled goal does not apply.
  final bool enabled;

  /// First local day this version applies to.
  final LocalDate effectiveFrom;

  @override
  bool operator ==(Object other) =>
      other is GoalVersion &&
      other.type == type &&
      other.target == target &&
      other.enabled == enabled &&
      other.effectiveFrom == effectiveFrom;

  @override
  int get hashCode => Object.hash(type, target, enabled, effectiveFrom);

  @override
  String toString() =>
      'GoalVersion(${type.key}, target: $target, enabled: $enabled, '
      'from: $effectiveFrom)';
}

/// The version of [type] that applies on [day]: the one with the latest
/// `effectiveFrom <= day`, or `null` when [day] lies before the first version.
///
/// The data layer passes all stored versions (any type, any order). The
/// storage constraint makes two versions with the same (type, effectiveFrom)
/// impossible; should it happen anyway, the one that appears later in
/// [versions] wins, so the result is still deterministic.
GoalVersion? resolveGoalVersion(
  Iterable<GoalVersion> versions,
  GoalType type,
  LocalDate day,
) {
  GoalVersion? best;
  for (final version in versions) {
    if (version.type != type || version.effectiveFrom.isAfter(day)) {
      continue;
    }
    if (best == null || !version.effectiveFrom.isBefore(best.effectiveFrom)) {
      best = version;
    }
  }
  return best;
}

/// Like [resolveGoalVersion], but falls back to [GoalVersion.implicitDefault]
/// (default target, enabled) when no version exists for [day] yet.
GoalVersion effectiveGoalOrDefault(
  Iterable<GoalVersion> versions,
  GoalType type,
  LocalDate day,
) =>
    resolveGoalVersion(versions, type, day) ??
    GoalVersion.implicitDefault(type);

/// The day on which goal edits made on [today] take effect: tomorrow.
LocalDate nextEffectiveDate(LocalDate today) => today.addDays(1);

/// Returns [existing] with [change] applied.
///
/// A change replaces the stored version with the same type and `effectiveFrom`
/// (so several edits made for tomorrow collapse into one version) and is
/// appended otherwise. [existing] is not modified. The data layer builds
/// [change] with `effectiveFrom: nextEffectiveDate(today)` after validating the
/// target with [GoalType.validateTarget].
List<GoalVersion> applyGoalChange(
  Iterable<GoalVersion> existing,
  GoalVersion change,
) {
  final result = <GoalVersion>[];
  var replaced = false;
  for (final version in existing) {
    final sameSlot =
        version.type == change.type &&
        version.effectiveFrom == change.effectiveFrom;
    if (!sameSlot) {
      result.add(version);
    } else if (!replaced) {
      result.add(change);
      replaced = true;
    }
  }
  if (!replaced) {
    result.add(change);
  }
  return result;
}
