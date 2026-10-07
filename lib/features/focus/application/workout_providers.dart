import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => WorkoutRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// Rest days and skipped days (BS-99).
final workoutDayMarkRepositoryProvider = Provider<WorkoutDayMarkRepository>(
  (ref) => WorkoutDayMarkRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// All active workouts, newest first ("Alle Trainings").
final workoutEntriesProvider = StreamProvider<List<WorkoutEntry>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchActive(),
);

/// The newest [limit] workouts; a lazy list loads more by raising the limit.
/// Auto-disposed: a page that is no longer shown stops watching the database.
final workoutEntriesPageProvider = StreamProvider.autoDispose
    .family<List<WorkoutEntry>, int>(
      (ref, limit) =>
          ref.watch(workoutRepositoryProvider).watchActive(limit: limit),
    );

/// One workout by id; emits null when it does not exist (any more).
final workoutEntryProvider = StreamProvider.family<WorkoutEntry?, String>(
  (ref, id) => ref.watch(workoutRepositoryProvider).watchById(id),
);

/// The workouts of the current Monday-to-Sunday week, newest first. Follows
/// the calendar day.
final workoutWeekEntriesProvider = StreamProvider<List<WorkoutEntry>>((ref) {
  final weekStart = ref.watch(todayProvider).startOfWeek;
  return ref
      .watch(workoutRepositoryProvider)
      .watchBetween(weekStart, weekStart.addDays(6));
});

/// This week's workouts: count (real, never capped), total minutes, the weekly
/// target from the goal version in effect, the ring fraction (capped at 100 %)
/// and the latest workout of the week. Recomputed only when workouts, goals or
/// the day change.
final workoutWeekSummaryProvider = Provider<AsyncValue<WorkoutWeekSummary>>((
  ref,
) {
  final entries = ref.watch(workoutWeekEntriesProvider);
  final versions = ref.watch(goalVersionsProvider);
  final today = ref.watch(todayProvider);
  return entries.when(
    loading: () => const AsyncLoading(),
    error: AsyncError.new,
    data: (list) {
      final goalVersions = versions.value;
      if (goalVersions == null) {
        return versions.hasError
            ? AsyncError(versions.error!, versions.stackTrace!)
            : const AsyncLoading();
      }
      return AsyncData(
        buildWorkoutWeekSummary(
          entries: list,
          today: today,
          weeklyTarget: workoutWeeklyTargetOn(goalVersions, today),
        ),
      );
    },
  );
});
