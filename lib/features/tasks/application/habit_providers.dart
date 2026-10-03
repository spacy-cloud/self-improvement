import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';

final habitRepositoryProvider = Provider<HabitRepository>(
  (ref) => HabitRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// All existing habits (archived ones included), oldest first. The screens use
/// the derived [habitsOverviewProvider] and [habitDetailProvider] instead.
final habitsProvider = StreamProvider<List<Habit>>(
  (ref) => ref.watch(habitRepositoryProvider).watchAll(),
);

/// The active checks of all existing habits.
final habitCheckIndexProvider = StreamProvider<HabitCheckIndex>(
  (ref) => ref.watch(habitRepositoryProvider).watchChecks(),
);

/// One habit by id (archived ones too). Emits null when it does not exist (any
/// more, for example after a delete): the UI then shows the not-found screen.
final habitProvider = StreamProvider.autoDispose.family<Habit?, String>(
  (ref, id) => ref.watch(habitRepositoryProvider).watchById(id),
);

/// Today's habit list: every habit that applies today with its checked state,
/// series ("Ab morgen archiviert" hint included) and reminder, plus the habits
/// that have ended. Recomputed when a habit, a check or the day changes, so
/// after midnight an unchecked new day shows up without a restart.
final habitsOverviewProvider = Provider<AsyncValue<HabitsOverview>>((ref) {
  final habits = ref.watch(habitsProvider);
  final checks = ref.watch(habitCheckIndexProvider);
  final today = ref.watch(todayProvider);
  return _combine(
    habits,
    checks,
    (list, index) =>
        buildHabitsOverview(habits: list, checks: index, today: today),
  );
});

/// The detail of one habit: series, state of today, archive hint and the 30
/// day history grid with an accessible text per day. Data is null when the
/// habit does not exist (not-found screen). Recomputed on every change of the
/// habit or its checks and on a day change.
final habitDetailProvider = Provider.autoDispose
    .family<AsyncValue<HabitDetail?>, String>((ref, id) {
      final habit = ref.watch(habitProvider(id));
      final checks = ref.watch(habitCheckIndexProvider);
      final today = ref.watch(todayProvider);
      return _combine(
        habit,
        checks,
        (found, index) => found == null
            ? null
            : buildHabitDetail(
                habit: found,
                checkedDates: index.datesOf(found.id),
                today: today,
              ),
      );
    });

/// Combines two async values: an error wins, then loading, then the data.
AsyncValue<R> _combine<A, B, R>(
  AsyncValue<A> first,
  AsyncValue<B> second,
  R Function(A first, B second) combine,
) {
  if (first case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<R>(error, stackTrace);
  }
  if (second case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<R>(error, stackTrace);
  }
  if (first case AsyncData(:final value) when second is AsyncData<B>) {
    return AsyncData<R>(combine(value, second.value));
  }
  return AsyncLoading<R>();
}
