/// Read model of the Home card "Heute abhaken" (BS-110): today's tasks and
/// habits as ONE list of things to tick off. A pure function of the stored
/// tasks and of the habit list of today ([HabitDay], the model the habits tab
/// builds for the same day), so the card and the tab can never disagree.
///
/// Tasks and habits stay two kinds: every entry says which one it is, in words
/// and in the spoken label, and the card draws them differently (square and
/// round box). The rules of the lists are not repeated here: the open tasks
/// come from [buildDashboardTasks] and the habits from [buildHabitDay].
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// How many habits the card lists at most; the rest is one line "und N
/// weitere Gewohnheiten" that opens the habit list. (The tasks keep their own
/// limit, [dashboardTaskLimit].)
const int dashboardHabitLimit = 5;

/// What kind of record an entry of the card is.
enum ChecklistKind {
  /// A one-off task.
  task('Aufgabe'),

  /// A recurring (daily) habit.
  habit('Gewohnheit');

  const ChecklistKind(this.label);

  /// The German word of the type chip and of the spoken label.
  final String label;
}

/// Which habits exist, seen from today: decides the hint about creating one.
enum HabitPresence {
  /// No habit was ever created.
  none,

  /// Habits exist, but every one of them has ended (archived).
  ended,

  /// At least one habit applies today.
  active,
}

/// One row of the card: a task or a habit with its state of today.
@immutable
final class ChecklistEntry {
  const ChecklistEntry({
    required this.kind,
    required this.id,
    required this.title,
    required this.done,
    required this.editable,
    required this.semanticsLabel,
    this.subtitle,
    this.overdue = false,
  });

  final ChecklistKind kind;

  /// The id of the task or habit.
  final String id;

  final String title;

  /// A completed task, or a habit checked today.
  final bool done;

  /// Whether the box may be changed (a habit follows the rules of the check
  /// command; a task always).
  final bool editable;

  /// The line under the title: the due text or the completion time of a task,
  /// the series (and "erledigt") of a habit. Null without anything to say.
  final String? subtitle;

  /// An open task past its due day: the subtitle then carries the word
  /// "Überfällig" next to the red colour.
  final bool overdue;

  /// The complete spoken description of the row (the opening button): the
  /// kind comes first, then the title, the state, series or due text.
  final String semanticsLabel;

  /// The spoken name of the box: "Aufgabe Steuer machen", "Gewohnheit Lesen".
  String get checkboxLabel => '${kind.label} $title';

  /// The spoken state of a checked box. A habit belongs to the day.
  String get checkedStateLabel =>
      kind == ChecklistKind.habit ? 'heute erledigt' : 'erledigt';

  /// The spoken state of an unchecked box.
  String get uncheckedStateLabel =>
      kind == ChecklistKind.habit ? 'heute offen' : 'offen';
}

/// Everything the card shows.
@immutable
final class TodayChecklist {
  const TodayChecklist({
    required this.today,
    required this.tasks,
    required this.habits,
    required this.moreTasks,
    required this.moreHabits,
    required this.doneCount,
    required this.totalCount,
    required this.habitPresence,
  });

  /// The local day the list was built for.
  final LocalDate today;

  /// The listed tasks: the open ones that apply today (at most
  /// [dashboardTaskLimit]) and the ones completed today, in the order of the
  /// task list. A completed task keeps its place.
  final List<ChecklistEntry> tasks;

  /// The listed habits (at most [dashboardHabitLimit]), oldest habit first, the
  /// order of the habits tab.
  final List<ChecklistEntry> habits;

  /// Open tasks of today that are not listed.
  final int moreTasks;

  /// Habits of today that are not listed.
  final int moreHabits;

  /// Everything done today: completed tasks and checked habits, listed or not.
  final int doneCount;

  /// Everything of today: completed tasks, open tasks that apply today and the
  /// habits of today, listed or not.
  final int totalCount;

  final HabitPresence habitPresence;

  /// The rows in display order: tasks first, then habits.
  List<ChecklistEntry> get entries => <ChecklistEntry>[...tasks, ...habits];

  /// Nothing to show at all: no task and no habit for today.
  bool get isEmpty => tasks.isEmpty && habits.isEmpty;

  /// Everything of today is done (and there is something).
  bool get allDone => totalCount > 0 && doneCount >= totalCount;

  /// "2 von 5 erledigt".
  String get progressText => '$doneCount von $totalCount erledigt';
}

/// Builds the card from the stored [tasks] and the habit list of today.
///
/// [habitDay] must be the list of today (`HabitDay.isToday`). [anyHabitExists]
/// tells whether a habit exists at all (archived ones included), for the hint
/// about creating one. [completedAt] gives the wall clock time of a completion
/// ("Erledigt um 08:15"); null leaves the time out.
TodayChecklist buildTodayChecklist({
  required Iterable<Task> tasks,
  required HabitDay habitDay,
  required bool anyHabitExists,
  required LocalTime? Function(Task task) completedAt,
  int habitLimit = dashboardHabitLimit,
}) {
  assert(habitDay.isToday, 'The card lists the habits of today');
  final today = habitDay.today;
  final all = tasks.toList();
  final open = buildDashboardTasks(all, today);
  final completedToday = <TaskListItem>[
    for (final task in all)
      if (task.isCompleted && task.completedLocalDate == today)
        TaskListItem(task: task, today: today),
  ];
  final listedTasks = <TaskListItem>[...open.items, ...completedToday]
    ..sort((a, b) => compareTasks(a.task, b.task));

  final habitItems = habitDay.items;
  final listedHabits = habitItems.take(habitLimit).toList();
  final checkedHabits = habitItems.where((item) => item.checked).length;

  return TodayChecklist(
    today: today,
    tasks: List.unmodifiable(<ChecklistEntry>[
      for (final item in listedTasks) _taskEntry(item, completedAt),
    ]),
    habits: List.unmodifiable(<ChecklistEntry>[
      for (final item in listedHabits) _habitEntry(item),
    ]),
    moreTasks: open.moreCount,
    moreHabits: habitItems.length - listedHabits.length,
    doneCount: completedToday.length + checkedHabits,
    totalCount:
        open.applicableOpenCount + completedToday.length + habitItems.length,
    habitPresence: habitItems.isNotEmpty
        ? HabitPresence.active
        : (anyHabitExists ? HabitPresence.ended : HabitPresence.none),
  );
}

ChecklistEntry _taskEntry(
  TaskListItem item,
  LocalTime? Function(Task task) completedAt,
) {
  final task = item.task;
  if (task.isCompleted) {
    final time = completedAt(task);
    final text = time == null ? 'Erledigt' : 'Erledigt um ${time.toIso()}';
    return ChecklistEntry(
      kind: ChecklistKind.task,
      id: task.id,
      title: task.title,
      done: true,
      editable: true,
      subtitle: text,
      semanticsLabel:
          '${ChecklistKind.task.label} ${task.title}, '
          '${text.toLowerCase()}',
    );
  }
  return ChecklistEntry(
    kind: ChecklistKind.task,
    id: task.id,
    title: task.title,
    done: false,
    editable: true,
    subtitle: item.dueText,
    overdue: item.overdue,
    semanticsLabel: '${ChecklistKind.task.label} ${item.semanticsLabel}',
  );
}

ChecklistEntry _habitEntry(HabitDayItem item) {
  final habit = item.habit;
  final series = item.seriesText;
  final hint = item.archiveHint;
  final subtitle = <String>[
    ?series,
    if (item.checked) 'erledigt',
    ?hint,
  ].join(' · ');
  return ChecklistEntry(
    kind: ChecklistKind.habit,
    id: habit.id,
    title: habit.title,
    done: item.checked,
    editable: item.editable,
    subtitle: subtitle.isEmpty ? null : subtitle,
    semanticsLabel: <String>[
      '${ChecklistKind.habit.label} ${habit.title}',
      item.checked ? 'heute erledigt' : 'heute offen',
      ?series,
      ?hint,
    ].join(', '),
  );
}
