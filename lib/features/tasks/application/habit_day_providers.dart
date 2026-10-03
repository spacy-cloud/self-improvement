import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The day of the week strip the user picked; null follows today (so after
/// midnight the list moves on to the new day by itself).
class SelectedHabitDayController extends Notifier<LocalDate?> {
  @override
  LocalDate? build() => null;

  /// Picks [date]; null (or today) goes back to following today.
  void select(LocalDate? date) => state = date;
}

final selectedHabitDayProvider =
    NotifierProvider<SelectedHabitDayController, LocalDate?>(
      SelectedHabitDayController.new,
    );

/// The habit list of the selected day (today by default) and the week strip.
/// Recomputed when a habit, a check, the selection or the day changes.
final habitDayProvider = Provider<AsyncValue<HabitDay>>((ref) {
  final habits = ref.watch(habitsProvider);
  final checks = ref.watch(habitCheckIndexProvider);
  final today = ref.watch(todayProvider);
  final selected = ref.watch(selectedHabitDayProvider);
  if (habits case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<HabitDay>(error, stackTrace);
  }
  if (checks case AsyncError(:final error, :final stackTrace)) {
    return AsyncError<HabitDay>(error, stackTrace);
  }
  if (habits case AsyncData(:final value) when checks is AsyncData) {
    return AsyncData<HabitDay>(
      buildHabitDay(
        habits: value,
        checks: checks.requireValue,
        date: effectiveHabitDay(selected, today),
        today: today,
      ),
    );
  }
  return AsyncLoading<HabitDay>();
});
