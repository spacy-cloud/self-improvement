import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The day of the week strip the user picked; null follows today. The choice
/// is dropped when the day changes, so the app never opens on yesterday's list
/// after midnight.
class SelectedHabitDayController extends Notifier<LocalDate?> {
  @override
  LocalDate? build() {
    ref.watch(todayProvider);
    return null;
  }

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
  final selected = ref.watch(selectedHabitDayProvider);
  return _habitDay(ref, (today) => effectiveHabitDay(selected, today));
});

/// The habit list of TODAY, whatever day the habits tab shows: the Home card
/// follows today, not the selection of the week strip (BS-110). It is the same
/// model, built by the same function from the same streams as
/// [habitDayProvider] (which is this list when nothing is selected), so a check
/// made on Home or in the tab shows up in both without a second calculation.
final habitTodayProvider = Provider<AsyncValue<HabitDay>>(
  (ref) => _habitDay(ref, (today) => today),
);

/// Builds the [HabitDay] of the day [pick] chooses from today, from the habit
/// and check streams; an error wins, then loading, then the data.
AsyncValue<HabitDay> _habitDay(
  Ref ref,
  LocalDate Function(LocalDate today) pick,
) {
  final habits = ref.watch(habitsProvider);
  final checks = ref.watch(habitCheckIndexProvider);
  final today = ref.watch(todayProvider);
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
        date: pick(today),
        today: today,
      ),
    );
  }
  return AsyncLoading<HabitDay>();
}
