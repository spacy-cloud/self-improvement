import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_recency.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';

/// How many workouts the overview lists under "Letzte Trainings".
const int workoutOverviewLatestCount = 5;

/// The newest workouts of the overview (a bounded query, so a long history
/// never loads as a whole).
final workoutLatestProvider = Provider<AsyncValue<List<WorkoutEntry>>>(
  (ref) => ref.watch(workoutEntriesPageProvider(workoutOverviewLatestCount)),
);

/// The workouts of the recency window (the last four weeks).
final workoutRecentEntriesProvider = StreamProvider<List<WorkoutEntry>>((ref) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(workoutRepositoryProvider)
      .watchBetween(today.addDays(-(muscleRecencyWindowDays - 1)), today);
});

/// "Zuletzt trainiert": the muscle groups of the recent workouts with the day
/// they were trained last. Recomputed only when workouts or the day change.
final workoutMuscleRecencyProvider = Provider<AsyncValue<List<MuscleRecency>>>((
  ref,
) {
  final today = ref.watch(todayProvider);
  return ref
      .watch(workoutRecentEntriesProvider)
      .whenData((entries) => buildMuscleRecency(entries, today));
});
