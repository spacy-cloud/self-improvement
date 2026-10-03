import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/data/meal_repository.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/shared/local_date.dart';

final mealRepositoryProvider = Provider<MealRepository>(
  (ref) => MealRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// The meals of one local day with the calorie summary (count, known sum,
/// completeness), newest meal first. Released when the screen stops watching
/// it.
final mealsDayProvider = StreamProvider.autoDispose.family<MealDay, LocalDate>(
  (ref, day) => ref.watch(mealRepositoryProvider).watchDay(day),
);

/// Today's meals with the calorie summary; switches to the new day when
/// `todayProvider` changes.
final mealsTodayProvider = StreamProvider<MealDay>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(mealRepositoryProvider).watchDay(today);
});

/// The meals of the last N local days (including today) grouped per day,
/// newest first, each day with its calorie summary. [defaultMealHistoryDays]
/// is the default window; a longer one makes older meals reachable.
final mealHistoryProvider = StreamProvider.autoDispose.family<MealHistory, int>(
  (ref, days) {
    final today = ref.watch(todayProvider);
    return ref
        .watch(mealRepositoryProvider)
        .watchHistory(today: today, days: days);
  },
);

/// One meal by id; emits null when it does not exist (any more). Released when
/// the screen stops watching it.
final mealEntryProvider = StreamProvider.autoDispose.family<MealEntry?, String>(
  (ref, id) => ref.watch(mealRepositoryProvider).watchById(id),
);
