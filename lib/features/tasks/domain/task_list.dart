/// Pure list rules of the tasks: status filter, search, priority filter, the
/// default sort and the dashboard selection (specification section 9.1).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The status segments of the task list: "Offen", "Erledigt", "Alle".
enum TaskStatusFilter {
  open('Offen'),
  completed('Erledigt'),
  all('Alle');

  const TaskStatusFilter(this.label);

  /// German label of the segment.
  final String label;
}

/// How many tasks the dashboard card lists at most.
const int dashboardTaskLimit = 3;

/// The complete filter state of the task list.
@immutable
final class TaskFilter {
  const TaskFilter({
    this.status = TaskStatusFilter.open,
    this.query = '',
    this.priority,
  });

  /// Which tasks to show; the list opens on "Offen".
  final TaskStatusFilter status;

  /// Search text as typed. Matching trims it and ignores case; it looks at the
  /// title and the description only (diacritics are compared as typed).
  final String query;

  /// Restricts the list to one priority; null shows all priorities.
  final TaskPriority? priority;

  /// The trimmed search text; empty means no search.
  String get normalizedQuery => query.trim();

  /// Whether the search or the priority filter narrows the list (the status
  /// segment is not counted: it always selects something).
  bool get isNarrowed => normalizedQuery.isNotEmpty || priority != null;

  TaskFilter copyWith({
    TaskStatusFilter? status,
    String? query,
    TaskPriority? priority,
    bool clearPriority = false,
  }) => TaskFilter(
    status: status ?? this.status,
    query: query ?? this.query,
    priority: clearPriority ? null : (priority ?? this.priority),
  );

  @override
  bool operator ==(Object other) =>
      other is TaskFilter &&
      other.status == status &&
      other.query == query &&
      other.priority == priority;

  @override
  int get hashCode => Object.hash(status, query, priority);

  @override
  String toString() =>
      'TaskFilter(${status.name}, query: "$query", priority: ${priority?.key})';
}

/// The default order: high priority first, then due date ascending (no date
/// last), then creation time (oldest first) and finally the id. Total and
/// deterministic: two different tasks never compare equal.
int compareTasks(Task a, Task b) {
  final byPriority = b.priority.rank.compareTo(a.priority.rank);
  if (byPriority != 0) {
    return byPriority;
  }
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null) {
    final byDue = aDue.compareTo(bDue);
    if (byDue != 0) {
      return byDue;
    }
  } else if (aDue != null) {
    return -1;
  } else if (bDue != null) {
    return 1;
  }
  final byCreated = a.createdAtUtc.compareTo(b.createdAtUtc);
  if (byCreated != 0) {
    return byCreated;
  }
  return a.id.compareTo(b.id);
}

/// Whether [task] matches the trimmed, lower-cased search [query] in its title
/// or description. An empty query matches everything.
bool taskMatchesQuery(Task task, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  if (task.title.toLowerCase().contains(needle)) {
    return true;
  }
  return task.description?.toLowerCase().contains(needle) ?? false;
}

/// Applies the status, search and priority filters and sorts the result with
/// [compareTasks]. The input is not modified.
List<Task> filterAndSortTasks(Iterable<Task> tasks, TaskFilter filter) {
  final needle = filter.normalizedQuery;
  final priority = filter.priority;
  final result = <Task>[
    for (final task in tasks)
      if (_matchesStatus(task, filter.status) &&
          (priority == null || task.priority == priority) &&
          taskMatchesQuery(task, needle))
        task,
  ]..sort(compareTasks);
  return result;
}

bool _matchesStatus(Task task, TaskStatusFilter status) => switch (status) {
  TaskStatusFilter.open => task.isOpen,
  TaskStatusFilter.completed => task.isCompleted,
  TaskStatusFilter.all => true,
};

/// A task together with the day it is displayed on: the pre-computed overdue
/// flag and due text for list rows, so widgets contain no date rules.
@immutable
final class TaskListItem {
  const TaskListItem({required this.task, required this.today});

  final Task task;

  /// The local day this item is rendered for.
  final LocalDate today;

  /// Open and due before [today]. Show the word "Überfällig" (see [dueText]) in
  /// addition to any colour.
  bool get overdue => task.isOverdueOn(today);

  /// German due text, for example "Überfällig seit 02.10.2026", "Heute fällig"
  /// or "Morgen fällig"; null without a due date.
  String? get dueText => taskDueText(task, today);
}

/// What the dashboard card shows.
@immutable
final class DashboardTasks {
  const DashboardTasks({
    required this.items,
    required this.applicableOpenCount,
  });

  /// Up to [dashboardTaskLimit] open tasks that apply today, in default order.
  final List<TaskListItem> items;

  /// All open tasks that apply today (no due date or due up to today).
  final int applicableOpenCount;

  /// How many applicable tasks are not listed ("und 2 weitere").
  int get moreCount => applicableOpenCount - items.length;
}

/// The dashboard selection: OPEN tasks without a due date or due up to and
/// including [today], sorted with [compareTasks], at most [limit]. Tasks due in
/// the future only appear in the "Alle" list.
DashboardTasks buildDashboardTasks(
  Iterable<Task> tasks,
  LocalDate today, {
  int limit = dashboardTaskLimit,
}) {
  final applicable = <Task>[
    for (final task in tasks)
      if (task.appliesOn(today)) task,
  ]..sort(compareTasks);
  return DashboardTasks(
    items: List.unmodifiable([
      for (final task in applicable.take(limit))
        TaskListItem(task: task, today: today),
    ]),
    applicableOpenCount: applicable.length,
  );
}

/// Why a task list shows nothing, so the UI can pick the right empty state.
enum TaskListEmptyReason {
  /// There is no task at all yet ("Noch keine Aufgaben").
  noTasks,

  /// Search or priority filter match nothing ("Keine Treffer").
  noMatches,

  /// "Offen" is selected and everything is done.
  nothingOpen,

  /// "Erledigt" is selected and nothing has been completed yet.
  nothingCompleted,
}

/// Everything the task list screen shows for one filter state.
@immutable
final class TaskListView {
  const TaskListView({
    required this.filter,
    required this.today,
    required this.items,
    required this.totalCount,
    required this.openCount,
    required this.completedCount,
  });

  final TaskFilter filter;

  /// The local day the list was built for (drives the overdue flags).
  final LocalDate today;

  /// The filtered tasks in default order, with overdue flag and due text.
  final List<TaskListItem> items;

  /// All active tasks, whatever the filter (open plus completed).
  final int totalCount;

  /// All open tasks, whatever the filter (for "Offen (3)").
  final int openCount;

  /// All completed tasks, whatever the filter.
  final int completedCount;

  /// The empty state to show, or null when [items] is not empty.
  TaskListEmptyReason? get emptyReason {
    if (items.isNotEmpty) {
      return null;
    }
    if (totalCount == 0) {
      return TaskListEmptyReason.noTasks;
    }
    if (filter.isNarrowed) {
      return TaskListEmptyReason.noMatches;
    }
    return switch (filter.status) {
      TaskStatusFilter.open => TaskListEmptyReason.nothingOpen,
      TaskStatusFilter.completed => TaskListEmptyReason.nothingCompleted,
      // Unreachable: "Alle" without narrowing shows every existing task.
      TaskStatusFilter.all => TaskListEmptyReason.noTasks,
    };
  }
}

/// Builds the list view model of [tasks] for [filter] on the day [today].
TaskListView buildTaskListView(
  Iterable<Task> tasks,
  TaskFilter filter,
  LocalDate today,
) {
  final all = tasks.toList();
  final completed = all.where((task) => task.isCompleted).length;
  return TaskListView(
    filter: filter,
    today: today,
    items: List.unmodifiable([
      for (final task in filterAndSortTasks(all, filter))
        TaskListItem(task: task, today: today),
    ]),
    totalCount: all.length,
    openCount: all.length - completed,
    completedCount: completed,
  );
}
