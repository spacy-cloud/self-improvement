import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/habit_test_support.dart';
import '../support/task_test_support.dart';

/// The card "Aufgaben und Gewohnheiten" for a day that is not today (BS-93):
/// what is a fact on that day: the tasks completed on it and the habits that
/// applied with their state. Open tasks are not rebuilt, and nothing says
/// "heute".
void main() {
  final today = LocalDate(2026, 10, 7);
  final day = LocalDate(2026, 10, 5);
  final other = LocalDate(2026, 10, 4);

  HabitDay habitDayOf(
    List<Habit> habits, {
    Map<String, List<LocalDate>> checks = const {},
    LocalDate? date,
  }) => buildHabitDay(
    habits: habits,
    checks: HabitCheckIndex({
      for (final entry in checks.entries) entry.key: entry.value.toSet(),
    }),
    date: date ?? day,
    today: today,
  );

  TodayChecklist build({
    List<Task> tasks = const <Task>[],
    List<Habit> habits = const <Habit>[],
    Map<String, List<LocalDate>> checks = const {},
    LocalTime? Function(Task task)? completedAt,
  }) => buildDayChecklist(
    tasks: tasks,
    habitDay: habitDayOf(habits, checks: checks),
    completedAt: completedAt ?? (_) => null,
  );

  Task done(String id, String title, LocalDate on) => makeTask(
    id: id,
    title: title,
    completedAtUtc: DateTime.utc(on.year, on.month, on.day, 6, 15),
    completedLocalDate: on,
  );

  group('the tasks of the day (BS-93)', () {
    test('(BS-93) only the tasks completed on that day are listed', () {
      final list = build(
        tasks: <Task>[
          done('a', 'Steuer machen', day),
          done('b', 'Anderer Tag', other),
          done('c', 'Heute erledigt', today),
          makeTask(id: 'd', title: 'Noch offen'),
        ],
      );
      expect(list.tasks.map((entry) => entry.title), <String>['Steuer machen']);
      expect(list.moreTasks, 0);
    });

    test('(BS-93) open tasks are not rebuilt for a day that has passed: they '
        'are neither listed nor counted', () {
      final list = build(
        tasks: <Task>[
          makeTask(id: 'o1', title: 'Offen 1'),
          makeTask(id: 'o2', title: 'Offen 2', dueDate: day),
          done('a', 'Erledigt', day),
        ],
      );
      expect(list.tasks, hasLength(1));
      expect(list.totalCount, 1);
      expect(list.doneCount, 1);
    });

    test('(BS-93) a completed task says when it was done and that it is '
        'done', () {
      final list = build(
        tasks: <Task>[done('a', 'Steuer machen', day)],
        completedAt: (_) => const LocalTime(8, 15),
      );
      final entry = list.tasks.single;
      expect(entry.done, isTrue);
      expect(entry.subtitle, 'Erledigt um 08:15');
      expect(entry.semanticsLabel, 'Aufgabe Steuer machen, erledigt um 08:15');
    });

    test('(BS-93) there is no limit: every task completed that day is a row, '
        'in the order of the task list', () {
      final list = build(
        tasks: <Task>[
          for (var i = 0; i < 6; i++) done('t$i', 'Aufgabe $i', day),
        ],
      );
      expect(list.tasks, hasLength(6));
      expect(list.moreTasks, 0);
    });
  });

  group('the habits of the day (BS-93)', () {
    test('(BS-93) every habit that applied is a row, checked or open, with no '
        'series and no archive hint', () {
      final lesen = makeHabit(id: 'a', title: 'Lesen');
      final laufen = makeHabit(
        id: 'b',
        title: 'Laufen',
        createdAtUtc: DateTime.utc(2026, 9, 2),
      );
      final list = build(
        habits: <Habit>[lesen, laufen],
        checks: <String, List<LocalDate>>{
          'a': <LocalDate>[day],
        },
      );
      expect(list.habits.map((entry) => entry.title), <String>[
        'Lesen',
        'Laufen',
      ]);
      expect(list.habits.map((entry) => entry.done), <bool>[true, false]);
      expect(list.habits.first.subtitle, 'erledigt');
      expect(list.habits.last.subtitle, isNull);
    });

    test(
      '(BS-93) a habit that did not exist yet, or had ended, is not a row of '
      'that day',
      () {
        final later = makeHabit(
          id: 'a',
          title: 'Später',
          startedOn: LocalDate(2026, 10, 6),
        );
        final ended = makeHabit(
          id: 'b',
          title: 'Beendet',
          archivedFrom: LocalDate(2026, 10, 5),
        );
        final present = makeHabit(id: 'c', title: 'Dabei');
        final list = build(habits: <Habit>[later, ended, present]);
        expect(list.habits.map((entry) => entry.title), <String>['Dabei']);
      },
    );

    test('(BS-93) no limit and no "und N weitere": every habit of the day is '
        'shown (that line would open the list of another day)', () {
      final habits = <Habit>[
        for (var i = 0; i < 9; i++)
          makeHabit(
            id: 'h$i',
            title: 'Gewohnheit $i',
            createdAtUtc: DateTime.utc(2026, 9, 1, 8, i),
          ),
      ];
      final list = build(habits: habits);
      expect(list.habits, hasLength(9));
      expect(list.moreHabits, 0);
      expect(list.habits.length, greaterThan(dashboardHabitLimit));
    });

    test(
      '(BS-93, AT34) the spoken words say "an diesem Tag", never "heute"',
      () {
        final habit = makeHabit(id: 'a', title: 'Lesen');
        final list = build(
          habits: <Habit>[
            habit,
            makeHabit(id: 'b', title: 'Laufen'),
          ],
          checks: <String, List<LocalDate>>{
            'a': <LocalDate>[day],
          },
        );
        final checked = list.habits.first;
        final open = list.habits.last;
        expect(
          checked.semanticsLabel,
          'Gewohnheit Lesen, an diesem Tag erledigt',
        );
        expect(open.semanticsLabel, 'Gewohnheit Laufen, an diesem Tag offen');
        expect(checked.checkedStateLabel, 'an diesem Tag erledigt');
        expect(open.uncheckedStateLabel, 'an diesem Tag offen');
        for (final entry in list.entries) {
          expect(entry.semanticsLabel, isNot(contains('heute')));
        }
      },
    );

    test('(BS-93) the live card still says "heute"', () {
      final habit = makeHabit(id: 'a', title: 'Lesen');
      final live = buildTodayChecklist(
        tasks: const <Task>[],
        habitDay: buildHabitDay(
          habits: <Habit>[habit],
          checks: HabitCheckIndex(const <String, Set<LocalDate>>{}),
          date: today,
          today: today,
        ),
        anyHabitExists: true,
        completedAt: (_) => null,
      );
      expect(live.habits.single.semanticsLabel, contains('heute offen'));
      expect(live.habits.single.uncheckedStateLabel, 'heute offen');
    });
  });

  group('the counts of the day (BS-93)', () {
    test('(BS-93) done and total are those of the rows: the completed tasks '
        'and the habits of the day', () {
      final list = build(
        tasks: <Task>[done('a', 'A', day), done('b', 'B', day)],
        habits: <Habit>[
          makeHabit(id: 'h1', title: 'Lesen'),
          makeHabit(id: 'h2', title: 'Laufen'),
        ],
        checks: <String, List<LocalDate>>{
          'h1': <LocalDate>[day],
        },
      );
      expect(list.doneCount, 3);
      expect(list.totalCount, 4);
      expect(list.progressText, '3 von 4 erledigt');
      expect(list.allDone, isFalse);
    });

    test('(BS-93) the card belongs to the day: it carries the date of that '
        'day, where the live card carries today', () {
      expect(build().today, day);
    });

    test('(BS-93) a day without a task and a habit is empty', () {
      final list = build();
      expect(list.isEmpty, isTrue);
      expect(list.totalCount, 0);
      expect(list.habitPresence, HabitPresence.none);
    });

    test('(BS-93) all rows done is "all done"', () {
      final list = build(
        tasks: <Task>[done('a', 'A', day)],
        habits: <Habit>[makeHabit(id: 'h1', title: 'Lesen')],
        checks: <String, List<LocalDate>>{
          'h1': <LocalDate>[day],
        },
      );
      expect(list.allDone, isTrue);
      expect(list.progressText, '2 von 2 erledigt');
    });
  });

  test('(BS-93, R2-03) the card of today is not built by this function, and '
      'the message names this function and the one that builds it', () {
    expect(
      () => buildDayChecklist(
        tasks: const <Task>[],
        habitDay: buildHabitDay(
          habits: const <Habit>[],
          checks: HabitCheckIndex(const <String, Set<LocalDate>>{}),
          date: today,
          today: today,
        ),
        completedAt: (_) => null,
      ),
      throwsA(
        isA<AssertionError>().having(
          (error) => error.message.toString(),
          'message',
          allOf(
            contains('buildDayChecklist'),
            contains('a day before today'),
            contains('buildTodayChecklist'),
          ),
        ),
      ),
    );
  });
}
