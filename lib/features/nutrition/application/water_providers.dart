import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';

final waterRepositoryProvider = Provider<WaterRepository>(
  (ref) => WaterRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
    snapshots: ref.watch(goalSnapshotServiceProvider),
    goalVersions: ref.watch(goalVersionRepositoryProvider),
  ),
);

/// Today's water model: real total, target (null when no goal applies),
/// progress, goal flag and today's entries newest first. Recomputed from the
/// database streams; switches to the new day when `todayProvider` changes.
final waterTodayProvider = StreamProvider<WaterToday>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(waterRepositoryProvider).watchToday(today);
});

/// The entries of the last N local days (including today) grouped per day,
/// newest first, with each day's total. [defaultWaterHistoryDays] is the
/// default window; a longer one makes older entries reachable for editing.
final waterHistoryProvider = StreamProvider.family<WaterHistory, int>((
  ref,
  days,
) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(waterRepositoryProvider)
      .watchHistory(today: today, days: days);
});

/// One water entry by id; emits null when it does not exist (any more).
final waterEntryProvider = StreamProvider.family<WaterEntry?, String>(
  (ref, id) => ref.watch(waterRepositoryProvider).watchById(id),
);

/// The daily goal as the goal editor needs it: today's threshold and what
/// applies from tomorrow. Loading until goals and today's model are known.
final waterGoalSettingsProvider = Provider<AsyncValue<WaterGoalSettings>>((
  ref,
) {
  final versions = ref.watch(goalVersionsProvider);
  final water = ref.watch(waterTodayProvider);
  final today = ref.watch(todayProvider);
  if (versions case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }
  if (water case AsyncError(:final error, :final stackTrace)) {
    return AsyncError(error, stackTrace);
  }
  final versionList = versions.value;
  final waterToday = water.value;
  if (versionList == null || waterToday == null) {
    return const AsyncLoading();
  }
  return AsyncData(
    buildWaterGoalSettings(
      versions: versionList,
      today: today,
      todayTargetMl: waterToday.targetMl,
    ),
  );
});
