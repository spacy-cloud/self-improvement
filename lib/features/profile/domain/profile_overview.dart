/// The read model of the profile page, built from real data only.
///
/// Nothing here is invented: a missing value stays missing, parts of switched
/// off modules are left out, and "Gewicht seit Start" needs an explicit start
/// weight and a current measurement.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/profile/domain/profile_formatting.dart';

/// Which goal a line of the profile summary shows.
enum ProfileGoalKind {
  water,
  steps,
  focusMinutes,
  weightEntry,
  taskCompletion,
  workoutWeekly,

  /// The body target weight (a profile value, effective immediately).
  targetWeight,
}

/// One row of "Meine Ziele".
@immutable
final class ProfileGoalLine {
  const ProfileGoalLine({
    required this.kind,
    required this.title,
    required this.value,
    this.pending,
  });

  final ProfileGoalKind kind;

  /// Goal name, for example "Wasser".
  final String title;

  /// What applies today, for example "2,5 l pro Tag", "Aus" or "Nicht gesetzt".
  final String value;

  /// What applies from tomorrow when that differs from today, for example
  /// "Ab morgen: 3 l pro Tag".
  final String? pending;

  @override
  bool operator ==(Object other) =>
      other is ProfileGoalLine &&
      other.kind == kind &&
      other.title == title &&
      other.value == value &&
      other.pending == pending;

  @override
  int get hashCode => Object.hash(kind, title, value, pending);
}

/// Everything the profile page shows.
@immutable
final class ProfileOverview {
  const ProfileOverview({
    required this.name,
    required this.hasName,
    required this.initials,
    required this.memberSince,
    required this.showGamification,
    required this.showBody,
    required this.goals,
    this.streak,
    this.level,
    this.totalXp,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.sinceStartGrams,
  });

  /// The name to show: the entered name or "Mein Profil".
  final String name;

  /// Whether the user entered a name (without one the avatar shows the neutral
  /// profile icon).
  final bool hasName;

  /// Initials of at most two name parts, or `null` without a name.
  final String? initials;

  /// "Dabei seit Oktober 2026".
  final String memberSince;

  /// Whether the gamification module is on (streak and level are shown).
  final bool showGamification;

  /// Whether the body module is on (body data and weight change are shown).
  final bool showBody;

  /// The global streak, or `null` while it is not available.
  final StreakSummary? streak;

  /// Level and XP of the gamification module, or `null` while not available.
  final LevelProgress? level;
  final int? totalXp;

  final int? heightCm;
  final int? ageYears;
  final int? startWeightGrams;

  /// Current measurement minus start weight. `null` unless both exist.
  final int? sinceStartGrams;

  /// The goals of switched-on modules, plus the target weight with the body
  /// module.
  final List<ProfileGoalLine> goals;

  /// Whether at least one body value was entered.
  bool get hasBodyData =>
      heightCm != null || ageYears != null || startWeightGrams != null;
}

/// Builds the profile page model.
///
/// [currentWeightGrams] is the latest weight measurement (only read when the
/// body module is on). [streak], [level] and [totalXp] are `null` while their
/// providers have no value; they are ignored when gamification is off.
ProfileOverview buildProfileOverview({
  required UserProfile profile,
  required Map<ModuleId, bool> modules,
  required GoalEditorModel goals,
  StreakSummary? streak,
  LevelProgress? level,
  int? totalXp,
  int? currentWeightGrams,
}) {
  final showBody = modules[ModuleId.body] ?? true;
  final showGamification = modules[ModuleId.gamification] ?? true;
  final start = profile.startWeightGrams;
  final current = currentWeightGrams;

  final lines = <ProfileGoalLine>[
    for (final row in goals.visibleRows)
      ProfileGoalLine(
        kind: _kindOf(row.type),
        title: goalEditorSpec(row.type).title,
        value: goalSummaryText(
          row.type,
          target: row.today.target,
          enabled: row.today.enabled,
        ),
        pending: row.hasPendingChange
            ? 'Ab morgen: ${goalSummaryText(row.type, target: row.tomorrow.target, enabled: row.tomorrow.enabled)}'
            : null,
      ),
    if (showBody)
      ProfileGoalLine(
        kind: ProfileGoalKind.targetWeight,
        title: 'Zielgewicht',
        value: profile.targetWeightGrams == null
            ? 'Nicht gesetzt'
            : formatWeightKg(profile.targetWeightGrams!),
      ),
  ];

  return ProfileOverview(
    name: profile.effectiveName,
    hasName: profile.displayName != null,
    initials: profile.initials,
    memberSince: formatMemberSince(profile.startedOn),
    showGamification: showGamification,
    showBody: showBody,
    streak: showGamification ? streak : null,
    level: showGamification ? level : null,
    totalXp: showGamification ? totalXp : null,
    heightCm: showBody ? profile.heightCm : null,
    ageYears: showBody ? profile.ageYears : null,
    startWeightGrams: showBody ? start : null,
    sinceStartGrams: showBody && start != null && current != null
        ? current - start
        : null,
    goals: List.unmodifiable(lines),
  );
}

ProfileGoalKind _kindOf(GoalType type) {
  return switch (type) {
    GoalType.water => ProfileGoalKind.water,
    GoalType.steps => ProfileGoalKind.steps,
    GoalType.focusMinutes => ProfileGoalKind.focusMinutes,
    GoalType.weightEntry => ProfileGoalKind.weightEntry,
    GoalType.taskCompletion => ProfileGoalKind.taskCompletion,
    GoalType.workoutWeekly => ProfileGoalKind.workoutWeekly,
  };
}
