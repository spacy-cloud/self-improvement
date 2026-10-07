import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/tasks/application/habit_day_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The Home card "Heute abhaken": today's tasks and habits as one list (BS-110).
///
/// It reads the streams the lists read ([tasksProvider], [habitsProvider] and,
/// through [habitTodayProvider], the checks), so a check on Home shows up in
/// the habits tab and the other way round, and the card follows the day
/// change. An error of a stream is an error of the card; the card is loading
/// until all of them delivered.
final todayChecklistProvider = Provider<AsyncValue<TodayChecklist>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final habitDay = ref.watch(habitTodayProvider);
  final habits = ref.watch(habitsProvider);
  final clock = ref.watch(clockProvider);
  final inputs = <AsyncValue<Object?>>[tasks, habitDay, habits];
  for (final input in inputs) {
    if (input.hasError) {
      return AsyncError<TodayChecklist>(
        input.error!,
        input.stackTrace ?? StackTrace.empty,
      );
    }
  }
  if (inputs.any((input) => !input.hasValue)) {
    return const AsyncLoading<TodayChecklist>();
  }
  return AsyncData<TodayChecklist>(
    buildTodayChecklist(
      tasks: tasks.requireValue,
      habitDay: habitDay.requireValue,
      anyHabitExists: habits.requireValue.isNotEmpty,
      completedAt: (task) => _completionTime(clock, task),
    ),
  );
});

/// The wall clock time of the completion of [task] in the zone it happened in;
/// null when the task is open or its zone is unknown.
LocalTime? _completionTime(ClockService clock, Task task) {
  final at = task.completedAtUtc;
  final zone = task.completionTimezoneId;
  if (at == null || zone == null || !TimeZones.isKnown(zone)) {
    return null;
  }
  return clock.toLocal(at.toUtc(), timeZoneId: zone).time;
}
