import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';

/// What "Ziele heute" shows: the day status of `DashboardView.dayStatus` (the
/// object the day ring on Home counts, so the numbers always agree) put into
/// rows.
///
/// Three more sources add words and the weekly goal, never numbers of the ring,
/// and each is read only when the page needs it: the names of the habits (when
/// a habit goal applies), how "Workout heute" was answered (when that goal
/// applies today) and the workouts of the week (when the focus module is on and
/// a daily goal applies).
/// Loading until all of them arrived; an error in one of them is an error of
/// the page.
final goalsTodayProvider = Provider<AsyncValue<GoalsDay>>((ref) {
  final view = ref.watch(dashboardViewProvider);
  final model = view.value;
  if (model == null) {
    return view.hasError
        ? AsyncError<GoalsDay>(view.error!, view.stackTrace ?? StackTrace.empty)
        : const AsyncLoading<GoalsDay>();
  }
  final status = model.dayStatus;
  if (status == null) {
    // No snapshot (before the profile start): nothing counts yet.
    return AsyncData<GoalsDay>(GoalsDay.none(date: model.today, isToday: true));
  }

  final isToday = status.date == model.today;
  final hasHabitGoals = status.goals.any(
    (goal) => goal.applicable && isHabitGoalKey(goal.goalKey),
  );
  final workoutGoalCounts =
      isToday &&
      (status.progressOf(GoalType.workoutDaily)?.applicable ?? false);
  final focusIsOn = model.moduleStatuses[ModuleId.focus] ?? true;

  final habits = hasHabitGoals ? ref.watch(habitsProvider) : null;
  final workoutDay = workoutGoalCounts
      ? ref.watch(workoutDayStateProvider)
      : null;
  final week = isToday && focusIsOn && status.hasApplicableGoals
      ? ref.watch(workoutWeekSummaryProvider)
      : null;

  final needed = <AsyncValue<Object?>>[?habits, ?workoutDay, ?week];
  for (final input in needed) {
    if (input.hasError) {
      return AsyncError<GoalsDay>(
        input.error!,
        input.stackTrace ?? StackTrace.empty,
      );
    }
  }
  if (needed.any((input) => !input.hasValue)) {
    return const AsyncLoading<GoalsDay>();
  }

  final habitList = habits?.requireValue;
  return AsyncData<GoalsDay>(
    buildGoalsDay(
      status: status,
      today: model.today,
      habits: <GoalHabit>[
        if (habitList != null)
          for (final habit in habitList)
            (id: habit.id, title: habit.title, icon: habit.icon),
      ],
      workoutOutcome: workoutDay?.requireValue.outcome,
      week: week?.requireValue,
    ),
  );
});

/// Re-reads everything the page depends on ("Erneut versuchen").
void reloadGoalsToday(WidgetRef ref) {
  reloadDashboard(ref);
  ref
    ..invalidate(habitsProvider)
    ..invalidate(workoutTodayEntriesProvider)
    ..invalidate(workoutDayMarkTodayProvider)
    ..invalidate(workoutWeekEntriesProvider)
    ..invalidate(goalVersionsProvider);
}
