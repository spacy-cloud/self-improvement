import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/profile/domain/profile_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

final today = LocalDate(2026, 10, 3);
final allOn = <ModuleId, bool>{
  for (final module in ModuleId.values) module: true,
};

UserProfile profile({
  String? name,
  int? height,
  int? age,
  int? start,
  int? target,
}) => UserProfile(
  startedOn: LocalDate(2026, 8, 20),
  onboardingCompleted: true,
  rowVersion: 1,
  displayName: name,
  heightCm: height,
  ageYears: age,
  startWeightGrams: start,
  targetWeightGrams: target,
);

GoalEditorModel goals({
  Map<ModuleId, bool>? modules,
  List<GoalVersion> extra = const [],
}) => buildGoalEditorModel(
  versions: [
    for (final type in GoalType.values)
      GoalVersion(
        type: type,
        target: type.defaultTarget,
        effectiveFrom: LocalDate(2026, 8, 20),
      ),
    ...extra,
  ],
  today: today,
  modules: modules ?? allOn,
);

final streak = StreakSummary(
  current: 11,
  longest: 12,
  activeDays: 48,
  nextMilestone: 14,
  todayActive: true,
  lastSevenDays: const [],
);

ProfileOverview build(
  UserProfile profile, {
  Map<ModuleId, bool>? modules,
  StreakSummary? streak,
  LevelProgress? level,
  int? totalXp,
  int? current,
  List<GoalVersion> extra = const [],
}) => buildProfileOverview(
  profile: profile,
  modules: modules ?? allOn,
  goals: goals(modules: modules, extra: extra),
  streak: streak,
  level: level,
  totalXp: totalXp,
  currentWeightGrams: current,
);

void main() {
  group('a profile without any entry', () {
    final overview = build(profile());

    test('shows the default name, a neutral avatar and the start month', () {
      expect(overview.name, 'Mein Profil');
      expect(overview.hasName, isFalse);
      expect(overview.initials, isNull);
      expect(overview.memberSince, 'Dabei seit August 2026');
    });

    test('has no body data and no weight change, nothing is invented', () {
      expect(overview.hasBodyData, isFalse);
      expect(overview.heightCm, isNull);
      expect(overview.ageYears, isNull);
      expect(overview.startWeightGrams, isNull);
      expect(overview.sinceStartGrams, isNull);
    });

    test('the target weight reads "Nicht gesetzt"', () {
      final line = overview.goals.last;
      expect(line.kind, ProfileGoalKind.targetWeight);
      expect(line.value, 'Nicht gesetzt');
    });
  });

  group('weight since start (W02)', () {
    test('needs an explicit start weight AND a current measurement', () {
      expect(build(profile(), current: 71500).sinceStartGrams, isNull);
      expect(build(profile(start: 74000)).sinceStartGrams, isNull);
      expect(
        build(profile(start: 74000), current: 71500).sinceStartGrams,
        -2500,
      );
    });

    test('is positive for a gain and zero for an unchanged weight', () {
      expect(
        build(profile(start: 70000), current: 72000).sinceStartGrams,
        2000,
      );
      expect(build(profile(start: 70000), current: 70000).sinceStartGrams, 0);
    });

    test('target weight shows as entered, also equal to the start (AT09)', () {
      for (final target in [68000, 74000, 80000]) {
        final line = build(profile(start: 74000, target: target)).goals.last;
        expect(line.value, '${target ~/ 1000},0 kg');
      }
    });
  });

  test('name and initials come from the stored profile', () {
    final overview = build(profile(name: 'Max Mustermann'));
    expect(overview.name, 'Max Mustermann');
    expect(overview.hasName, isTrue);
    expect(overview.initials, 'MM');
  });

  group('modules', () {
    test('body off hides body data, target weight and weight change', () {
      final overview = build(
        profile(height: 180, start: 74000, target: 68000),
        modules: {...allOn, ModuleId.body: false},
        current: 71500,
      );
      expect(overview.showBody, isFalse);
      expect(overview.heightCm, isNull);
      expect(overview.startWeightGrams, isNull);
      expect(overview.sinceStartGrams, isNull);
      expect(
        overview.goals.any((line) => line.kind == ProfileGoalKind.targetWeight),
        isFalse,
      );
    });

    test('gamification off hides streak, level and XP', () {
      final overview = build(
        profile(),
        modules: {...allOn, ModuleId.gamification: false},
        streak: streak,
        level: const LevelProgress(level: 3, xpInLevel: 20),
        totalXp: 220,
      );
      expect(overview.showGamification, isFalse);
      expect(overview.streak, isNull);
      expect(overview.level, isNull);
      expect(overview.totalXp, isNull);
    });

    test('gamification on keeps what the providers delivered', () {
      final overview = build(
        profile(),
        streak: streak,
        level: const LevelProgress(level: 3, xpInLevel: 20),
        totalXp: 220,
      );
      expect(overview.streak!.current, 11);
      expect(overview.streak!.activeDays, 48);
      expect(overview.level!.level, 3);
      expect(overview.totalXp, 220);
    });

    test('goals of switched-off modules leave the list', () {
      final overview = build(
        profile(),
        modules: {...allOn, ModuleId.nutrition: false, ModuleId.focus: false},
      );
      expect(overview.goals.map((line) => line.kind), [
        ProfileGoalKind.steps,
        ProfileGoalKind.weightEntry,
        ProfileGoalKind.taskCompletion,
        ProfileGoalKind.targetWeight,
      ]);
    });

    test('all modules off leave no goal at all', () {
      final overview = build(
        profile(target: 68000),
        modules: {for (final module in ModuleId.values) module: false},
      );
      expect(overview.goals, isEmpty);
    });
  });

  group('goal lines', () {
    test('show what applies today', () {
      final lines = {for (final l in build(profile()).goals) l.kind: l};
      expect(lines[ProfileGoalKind.water]!.value, '2,5 l pro Tag');
      expect(lines[ProfileGoalKind.steps]!.value, '10.000 pro Tag');
      expect(lines[ProfileGoalKind.focusMinutes]!.value, '25 Min. pro Tag');
      expect(lines[ProfileGoalKind.weightEntry]!.value, 'Täglich');
      expect(lines[ProfileGoalKind.workoutWeekly]!.value, '3× pro Woche');
      expect(lines.values.every((l) => l.pending == null), isTrue);
    });

    test('name the change that starts tomorrow', () {
      final overview = build(
        profile(),
        extra: [
          GoalVersion(
            type: GoalType.water,
            target: 3000,
            effectiveFrom: today.addDays(1),
          ),
          GoalVersion(
            type: GoalType.steps,
            target: 10000,
            enabled: false,
            effectiveFrom: today.addDays(1),
          ),
        ],
      );
      final water = overview.goals.firstWhere(
        (l) => l.kind == ProfileGoalKind.water,
      );
      expect(water.value, '2,5 l pro Tag', reason: 'today is unchanged');
      expect(water.pending, 'Ab morgen: 3 l pro Tag');
      final steps = overview.goals.firstWhere(
        (l) => l.kind == ProfileGoalKind.steps,
      );
      expect(steps.pending, 'Ab morgen: Aus');
    });
  });
}
