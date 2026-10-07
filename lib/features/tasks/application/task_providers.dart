import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// All active tasks (open and completed), oldest first. The screens use the
/// derived [taskListProvider], [dashboardTasksProvider] and
/// `todayChecklistProvider` instead.
final tasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(taskRepositoryProvider).watchActive(),
);

/// One task by id. Emits null when it does not exist (any more, for example
/// after a delete): the UI then shows the not-found screen.
final taskProvider = StreamProvider.autoDispose.family<Task?, String>(
  (ref, id) => ref.watch(taskRepositoryProvider).watchById(id),
);

/// The filter state of the task list: status segment, search text and priority.
///
/// Kept alive with the app so the filter survives tab switches. Starts on
/// "Offen" without search and without priority filter.
class TaskListController extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => const TaskFilter();

  void setStatus(TaskStatusFilter status) =>
      state = state.copyWith(status: status);

  /// Sets the search text as typed (matching trims it and ignores case).
  void setQuery(String query) => state = state.copyWith(query: query);

  /// Restricts the list to [priority]; null shows all priorities.
  void setPriority(TaskPriority? priority) => state = priority == null
      ? state.copyWith(clearPriority: true)
      : state.copyWith(priority: priority);

  /// Clears search and priority filter; the status segment stays.
  void clearNarrowing() =>
      state = state.copyWith(query: '', clearPriority: true);
}

final taskListControllerProvider =
    NotifierProvider<TaskListController, TaskFilter>(TaskListController.new);

/// The task list for the current filter and the current local day: filtered,
/// sorted, with overdue flags, counts and the empty-state reason. Recomputed
/// when a task, the filter or the day changes, never per frame.
final taskListProvider = Provider<AsyncValue<TaskListView>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final filter = ref.watch(taskListControllerProvider);
  final today = ref.watch(todayProvider);
  return tasks.whenData((list) => buildTaskListView(list, filter, today));
});

/// The open part of the dashboard card: up to three open tasks that apply today
/// (no due date or due up to today). Future tasks only show up in the "Alle"
/// list. The Home card itself ("Heute abhaken", tasks and habits) reads
/// `todayChecklistProvider`, which builds on the same rule
/// (`buildDashboardTasks`).
final dashboardTasksProvider = Provider<AsyncValue<DashboardTasks>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final today = ref.watch(todayProvider);
  return tasks.whenData((list) => buildDashboardTasks(list, today));
});
