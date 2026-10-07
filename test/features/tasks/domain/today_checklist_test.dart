import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/habit_test_support.dart';
import '../support/task_test_support.dart';

void main() {
  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);
  final tomorrow = LocalDate(2026, 10, 4);

  HabitDay habitDay(
    List<Habit> habits, {
    Map<String, List<LocalDate>> checks = const {},
  }) => buildHabitDay(
    habits: habits,
    checks: HabitCheckIndex({
      for (final entry in checks.entries) entry.key: entry.value.toSet(),
    }),
    date: today,
    today: today,
  );

  List<Habit> habits(int count) => [
    for (var i = 0; i < count; i++)
      makeHabit(
        id: 'h$i',
        title: 'Gewohnheit $i',
        createdAtUtc: DateTime.utc(2026, 9, 1, 8, i),
      ),
  ];

  TodayChecklist build({
    List<Task> tasks = const [],
    List<Habit>? habitList,
    Map<String, List<LocalDate>> checks = const {},
    bool? anyHabitExists,
    LocalTime? Function(Task task)? completedAt,
    int habitLimit = dashboardHabitLimit,
  }) {
    final list = habitList ?? const <Habit>[];
    return buildTodayChecklist(
      tasks: tasks,
      habitDay: habitDay(list, checks: checks),
      anyHabitExists: anyHabitExists ?? list.isNotEmpty,
      completedAt: completedAt ?? (_) => null,
      habitLimit: habitLimit,
    );
  }

  Task done(
    String id, {
    String title = 'Erledigt',
    LocalDate? on,
    TaskPriority priority = TaskPriority.normal,
    LocalDate? dueDate,
  }) => makeTask(
    id: id,
    title: title,
    priority: priority,
    dueDate: dueDate,
    completedAtUtc: DateTime.utc(2026, 10, 3, 6, 15),
    completedLocalDate: on ?? today,
  );

  group('kinds and order (BS-110)', () {
    test('tasks come first, then habits, each entry knows its kind', () {
      final list = build(
        tasks: [makeTask(id: 't1', title: 'Steuer machen')],
        habitList: [makeHabit(title: 'Lesen')],
      );

      expect(list.entries.map((e) => e.kind), [
        ChecklistKind.task,
        ChecklistKind.habit,
      ]);
      expect(list.entries.map((e) => e.title), ['Steuer machen', 'Lesen']);
      expect(ChecklistKind.task.label, 'Aufgabe');
      expect(ChecklistKind.habit.label, 'Gewohnheit');
    });

    test(
      'a task and a habit are two kinds even with the same id and title',
      () {
        final list = build(
          tasks: [makeTask(id: 'x', title: 'Lesen')],
          habitList: [makeHabit(id: 'x', title: 'Lesen')],
        );

        expect(list.tasks.single.kind, ChecklistKind.task);
        expect(list.habits.single.kind, ChecklistKind.habit);
        expect(list.tasks.single.checkboxLabel, 'Aufgabe Lesen');
        expect(list.habits.single.checkboxLabel, 'Gewohnheit Lesen');
      },
    );

    test(
      'the habits keep the order of the habits tab (oldest habit first)',
      () {
        final newer = makeHabit(
          id: 'b',
          title: 'Neu',
          createdAtUtc: DateTime.utc(2026, 9, 2),
        );
        final older = makeHabit(
          id: 'a',
          title: 'Alt',
          createdAtUtc: DateTime.utc(2026, 9, 1),
        );
        final list = build(habitList: [newer, older]);
        final tab = habitDay([newer, older]);

        expect(list.habits.map((e) => e.id), ['a', 'b']);
        expect(list.habits.map((e) => e.id), tab.items.map((i) => i.habit.id));
      },
    );
  });

  group('tasks (BS-110, T01)', () {
    test(
      'at most three open tasks in the order of the list, the rest is counted',
      () {
        final tasks = [
          makeTask(id: '5', priority: TaskPriority.low),
          makeTask(id: '1', priority: TaskPriority.high, dueDate: yesterday),
          makeTask(id: '4'),
          makeTask(id: '2', priority: TaskPriority.high, dueDate: today),
          makeTask(id: '3', dueDate: today),
        ];

        final list = build(tasks: tasks);

        expect(list.tasks.map((e) => e.id), ['1', '2', '3']);
        expect(list.moreTasks, 2);
        expect(list.totalCount, 5);
        expect(list.doneCount, 0);
      },
    );

    test('a task due later is not on the card and not counted', () {
      final list = build(
        tasks: [
          makeTask(id: 'now'),
          makeTask(id: 'later', dueDate: tomorrow),
        ],
      );

      expect(list.tasks.map((e) => e.id), ['now']);
      expect(list.totalCount, 1);
    });

    test('a task completed today stays on the card, in its place, and counts as done', () {
      final list = build(
        tasks: [
          makeTask(id: 'open', title: 'Offen', dueDate: today),
          done('first', title: 'Zuerst', priority: TaskPriority.high),
          done('last', title: 'Zuletzt', priority: TaskPriority.low),
        ],
      );

      // The order of the task list (priority, then due date): the done task
      // keeps the place it had when it was open.
      expect(list.tasks.map((e) => e.id), ['first', 'open', 'last']);
      expect(list.tasks.map((e) => e.done), [true, false, true]);
      expect(list.doneCount, 2);
      expect(list.totalCount, 3);
      expect(list.progressText, '2 von 3 erledigt');
    });

    test('a task completed on another day is not on the card', () {
      final list = build(
        tasks: [
          done('yesterday', on: yesterday),
          done('today'),
        ],
      );

      expect(list.tasks.map((e) => e.id), ['today']);
      expect(list.totalCount, 1);
    });

    test('the open limit does not hide a completed task', () {
      final tasks = [
        for (var i = 0; i < 4; i++) makeTask(id: 'o$i', title: 'Offen $i'),
        done('d', title: 'Fertig', priority: TaskPriority.high),
      ];

      final list = build(tasks: tasks);

      expect(list.tasks, hasLength(4), reason: 'three open and the done one');
      expect(list.tasks.map((e) => e.id), contains('d'));
      expect(list.moreTasks, 1);
      expect(list.doneCount, 1);
      expect(list.totalCount, 5);
    });

    test('an open task says when it is due and flags an overdue one', () {
      final list = build(
        tasks: [
          makeTask(id: 'late', dueDate: yesterday),
          makeTask(id: 'today', dueDate: today),
          makeTask(id: 'none'),
        ],
      );
      final byId = {for (final e in list.tasks) e.id: e};

      expect(byId['late']!.subtitle, startsWith('Überfällig seit'));
      expect(byId['late']!.overdue, isTrue);
      expect(byId['today']!.subtitle, 'Heute fällig');
      expect(byId['today']!.overdue, isFalse);
      expect(byId['none']!.subtitle, isNull);
    });

    test('a completed task shows the time of the completion in words', () {
      final list = build(
        tasks: [done('d', title: 'Mathe-Hausaufgabe')],
        completedAt: (_) => const LocalTime(8, 15),
      );
      final entry = list.tasks.single;

      expect(entry.subtitle, 'Erledigt um 08:15');
      expect(
        entry.semanticsLabel,
        'Aufgabe Mathe-Hausaufgabe, erledigt um 08:15',
      );
    });

    test('without a known time the completed task only says "Erledigt"', () {
      final entry = build(tasks: [done('d', title: 'Steuer')]).tasks.single;

      expect(entry.subtitle, 'Erledigt');
      expect(entry.semanticsLabel, 'Aufgabe Steuer, erledigt');
    });

    test(
      'an open task is spoken with its kind, priority, due text and state',
      () {
        final entry = build(
          tasks: [
            makeTask(
              title: 'Steuer machen',
              priority: TaskPriority.high,
              dueDate: yesterday,
            ),
          ],
        ).tasks.single;

        expect(
          entry.semanticsLabel,
          'Aufgabe Steuer machen, Priorität Hoch, '
          'Überfällig seit 02.10.2026, offen',
        );
        expect(entry.uncheckedStateLabel, 'offen');
        expect(entry.checkedStateLabel, 'erledigt');
      },
    );
  });

  group('habits (BS-110, T02, AT21)', () {
    test('every habit of today is listed, checked ones included', () {
      final list = build(
        habitList: habits(3),
        checks: {
          'h1': [today],
        },
      );

      expect(list.habits.map((e) => e.done), [false, true, false]);
      expect(list.doneCount, 1);
      expect(list.totalCount, 3);
    });

    test('the state is the one of the habit list of today, habit by habit', () {
      final all = habits(4);
      final checks = {
        'h0': [today, yesterday],
        'h2': [yesterday],
        'h3': [today],
      };
      final list = build(habitList: all, checks: checks);
      final tab = habitDay(all, checks: checks);

      expect(
        list.habits.map((e) => e.done),
        tab.items.map((i) => i.checked),
        reason: 'one model for the card and the tab',
      );
      expect(list.doneCount, tab.doneCount);
      expect(list.totalCount, tab.totalCount);
    });

    test(
      'a habit is spoken with its kind, the day, the series and the state',
      () {
        final lesen = makeHabit(
          title: 'Lesen',
          startedOn: LocalDate(2026, 9, 28),
        );
        final open = build(
          habitList: [lesen],
          checks: {
            'h1': [
              LocalDate(2026, 9, 28),
              LocalDate(2026, 9, 29),
              LocalDate(2026, 9, 30),
              LocalDate(2026, 10, 1),
              yesterday,
            ],
          },
        ).habits.single;

        expect(open.done, isFalse);
        expect(open.subtitle, '5 Tage in Folge');
        expect(
          open.semanticsLabel,
          'Gewohnheit Lesen, heute offen, 5 Tage in Folge',
        );
        expect(open.uncheckedStateLabel, 'heute offen');
        expect(open.checkedStateLabel, 'heute erledigt');
      },
    );

    test('a checked habit says so in words and keeps the series', () {
      final entry = build(
        habitList: [makeHabit(title: 'Vitamine')],
        checks: {
          'h1': [yesterday, today],
        },
      ).habits.single;

      expect(entry.done, isTrue);
      expect(entry.subtitle, '2 Tage in Folge · erledigt');
      expect(
        entry.semanticsLabel,
        'Gewohnheit Vitamine, heute erledigt, 2 Tage in Folge',
      );
    });

    test('a habit without a series says so', () {
      final entry = build(habitList: [makeHabit(title: 'Dehnen')])
          .habits
          .single;

      expect(entry.subtitle, 'Noch keine Serie');
    });

    test('a habit that is archived from tomorrow carries the hint', () {
      final entry = build(
        habitList: [makeHabit(title: 'Lesen', archivedFrom: tomorrow)],
      ).habits.single;

      expect(entry.subtitle, 'Noch keine Serie · Ab morgen archiviert');
      expect(entry.semanticsLabel, endsWith('Ab morgen archiviert'));
    });

    test('a habit that has ended is not listed and not counted', () {
      final list = build(
        habitList: [
          makeHabit(id: 'old', archivedFrom: today),
          makeHabit(id: 'live'),
        ],
      );

      expect(list.habits.map((e) => e.id), ['live']);
      expect(list.totalCount, 1);
    });

    test('the editable flag is the one of the habit list', () {
      final entry = build(habitList: [makeHabit()]).habits.single;

      expect(entry.editable, isTrue);
    });

    test('at most five habits, the rest is counted with everything else', () {
      final all = habits(8);
      final list = build(
        habitList: all,
        checks: {
          'h0': [today],
          'h6': [today],
          'h7': [today],
        },
      );

      expect(dashboardHabitLimit, 5);
      expect(list.habits.map((e) => e.id), ['h0', 'h1', 'h2', 'h3', 'h4']);
      expect(list.moreHabits, 3);
      expect(list.totalCount, 8, reason: 'the hidden ones count');
      expect(list.doneCount, 3, reason: 'a hidden check counts');
    });

    test('with exactly five habits nothing is hidden', () {
      final list = build(habitList: habits(5));

      expect(list.habits, hasLength(5));
      expect(list.moreHabits, 0);
    });

    test('a smaller limit can be requested', () {
      final list = build(habitList: habits(4), habitLimit: 2);

      expect(list.habits, hasLength(2));
      expect(list.moreHabits, 2);
    });
  });

  group('counts and states (BS-110)', () {
    test('everything done: the count says so', () {
      final list = build(
        tasks: [done('d')],
        habitList: habits(2),
        checks: {
          'h0': [today],
          'h1': [today],
        },
      );

      expect(list.allDone, isTrue);
      expect(list.progressText, '3 von 3 erledigt');
    });

    test('one missing is not all done', () {
      final list = build(
        tasks: [
          done('d'),
          makeTask(id: 'o'),
        ],
        habitList: habits(1),
        checks: {
          'h0': [today],
        },
      );

      expect(list.allDone, isFalse);
      expect(list.progressText, '2 von 3 erledigt');
    });

    test('nothing at all is empty and never "all done"', () {
      final list = build();

      expect(list.isEmpty, isTrue);
      expect(list.allDone, isFalse);
      expect(list.totalCount, 0);
      expect(list.entries, isEmpty);
    });

    test('a task alone or a habit alone is not empty', () {
      expect(build(tasks: [makeTask()]).isEmpty, isFalse);
      expect(build(habitList: habits(1)).isEmpty, isFalse);
    });

    test('the presence of habits tells the three cases apart', () {
      expect(build().habitPresence, HabitPresence.none);
      expect(
        build(
          habitList: [makeHabit(archivedFrom: yesterday)],
          anyHabitExists: true,
        ).habitPresence,
        HabitPresence.ended,
      );
      expect(build(habitList: habits(1)).habitPresence, HabitPresence.active);
    });

    test('an archived habit alone leaves the card without habit rows', () {
      final list = build(
        tasks: [makeTask()],
        habitList: [makeHabit(archivedFrom: yesterday)],
        anyHabitExists: true,
      );

      expect(list.habits, isEmpty);
      expect(list.habitPresence, HabitPresence.ended);
      expect(list.isEmpty, isFalse, reason: 'the task is still there');
    });

    test('the day of the card is the day of the habit list', () {
      expect(build().today, today);
    });
  });

  group('limits of the lists stay where they were (BS-110)', () {
    test('the task limit is the one of the dashboard selection', () {
      expect(dashboardTaskLimit, 3);
      final tasks = [for (var i = 0; i < 6; i++) makeTask(id: 'id$i')];

      expect(
        build(tasks: tasks).tasks.map((e) => e.id),
        buildDashboardTasks(tasks, today).items.map((i) => i.task.id),
      );
    });
  });
}
