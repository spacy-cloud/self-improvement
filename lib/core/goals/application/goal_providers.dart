import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

final goalVersionRepositoryProvider = Provider<GoalVersionRepository>(
  (ref) => GoalVersionRepository(ref.watch(appDatabaseProvider)),
);

final goalSnapshotServiceProvider = Provider<GoalSnapshotService>(
  (ref) => GoalSnapshotService(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final dayFactsSourceProvider = Provider<DayFactsSource>(
  (ref) => DayFactsSource(ref.watch(appDatabaseProvider)),
);

final dayStatusRepositoryProvider = Provider<DayStatusRepository>(
  (ref) => DayStatusRepository(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    snapshots: ref.watch(goalSnapshotServiceProvider),
    facts: ref.watch(dayFactsSourceProvider),
  ),
);

/// All stored goal versions.
final goalVersionsProvider = StreamProvider<List<GoalVersion>>(
  (ref) => ref.watch(goalVersionRepositoryProvider).watchAll(),
);

/// Status of today: the ring (`fulfilled / applicable`). Null before the
/// profile start or when no snapshot exists.
final todayStatusProvider = StreamProvider<DayStatus?>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(dayStatusRepositoryProvider).watchDay(today);
});

/// Status of one day (BS-93): the ring and the goals of that day, from the
/// snapshot of that day (the goals and thresholds that counted THEN) and the
/// facts of that day. For today it is the same status as [todayStatusProvider].
/// Null for a day before the profile start. Released when no page shows it.
final dayStatusProvider = StreamProvider.autoDispose
    .family<DayStatus?, LocalDate>(
      (ref, day) => ref.watch(dayStatusRepositoryProvider).watchDay(day),
    );

/// The global streak (today, longest, active days, milestone, last seven days).
final streakProvider = StreamProvider<StreakSummary?>((ref) {
  // Recomputed when the calendar day changes.
  ref.watch(todayProvider);
  return ref.watch(dayStatusRepositoryProvider).watchStreak();
});
