import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/profile/domain/profile_overview.dart';

/// The latest weight measurement in grams, or `null` without a measurement
/// (or while the measurements are loading). Read-only use of the body module.
final currentWeightGramsProvider = Provider<int?>((ref) {
  final entries = ref.watch(weightEntriesProvider).value;
  if (entries == null || entries.isEmpty) {
    return null;
  }
  final current = currentWeight([
    for (final entry in entries)
      WeightSample(
        id: entry.id,
        occurredAtUtc: entry.occurredAtUtc,
        localDate: entry.localDate,
        grams: entry.weightGrams,
      ),
  ]);
  return current?.grams;
});

/// The goal editor model of today: per goal the version in effect today and
/// the one in effect tomorrow, plus which goals are visible (module on).
final goalEditorModelProvider = Provider<AsyncValue<GoalEditorModel>>((ref) {
  final versions = ref.watch(goalVersionsProvider);
  final modules = ref.watch(moduleStatusesProvider);
  final today = ref.watch(todayProvider);
  final failed = _firstFailure([versions, modules]);
  if (failed != null) {
    return AsyncError(failed.error, failed.stackTrace);
  }
  final versionList = versions.value;
  final moduleMap = modules.value;
  if (versionList == null || moduleMap == null) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildGoalEditorModel(
      versions: versionList,
      today: today,
      modules: moduleMap,
    ),
  );
});

/// The read model of the profile page. Loading until the profile, the module
/// states and the goal versions are there; streak, level and the latest weight
/// fill in as they arrive (and are not even watched when their module is off).
final profileOverviewProvider = Provider<AsyncValue<ProfileOverview>>((ref) {
  final profile = ref.watch(profileProvider);
  final modules = ref.watch(moduleStatusesProvider);
  final goals = ref.watch(goalEditorModelProvider);
  final failed = _firstFailure([profile, modules, goals]);
  if (failed != null) {
    return AsyncError(failed.error, failed.stackTrace);
  }
  if (profile.hasValue && profile.value == null) {
    return AsyncError(
      const NotFoundFailure(entity: 'profile'),
      StackTrace.current,
    );
  }
  final profileValue = profile.value;
  final moduleMap = modules.value;
  final goalModel = goals.value;
  if (profileValue == null || moduleMap == null || goalModel == null) {
    return const AsyncLoading();
  }

  final gamificationOn = moduleMap[ModuleId.gamification] ?? true;
  final bodyOn = moduleMap[ModuleId.body] ?? true;
  final streak = gamificationOn ? ref.watch(streakProvider).value : null;
  final summary = gamificationOn
      ? ref.watch(gamificationSummaryProvider).value
      : null;
  final currentWeightGrams = bodyOn
      ? ref.watch(currentWeightGramsProvider)
      : null;

  return AsyncData(
    buildProfileOverview(
      profile: profileValue,
      modules: moduleMap,
      goals: goalModel,
      streak: streak,
      level: summary?.level,
      totalXp: summary?.totalXp,
      currentWeightGrams: currentWeightGrams,
    ),
  );
});

/// Invalidates everything the profile page reads, so an error state can try
/// again ("Erneut versuchen").
void retryProfileOverview(WidgetRef ref) {
  ref
    ..invalidate(profileProvider)
    ..invalidate(moduleStatusesProvider)
    ..invalidate(goalVersionsProvider)
    ..invalidate(streakProvider)
    ..invalidate(gamificationSummaryProvider)
    ..invalidate(weightEntriesProvider);
}

AsyncError<Object?>? _firstFailure(Iterable<AsyncValue<Object?>> sources) {
  for (final source in sources) {
    if (source.hasError) {
      return AsyncError<Object?>(
        source.error!,
        source.stackTrace ?? StackTrace.current,
      );
    }
  }
  return null;
}
