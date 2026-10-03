import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);
  final tomorrow = LocalDate(2026, 10, 4);

  /// The ids of the sorted result, for compact assertions.
  List<String> ids(Iterable<Task> tasks) => [for (final t in tasks) t.id];

  DateTime created(int minute) => DateTime.utc(2026, 9, 1, 8, minute);

  group('default order (priority, due date, created, id)', () {
    test('high priority comes before normal and low', () {
      final tasks = [
        makeTask(id: 'low', priority: TaskPriority.low),
        makeTask(id: 'normal'),
        makeTask(id: 'high', priority: TaskPriority.high),
      ];
      expect(ids(filterAndSortTasks(tasks, const TaskFilter())), [
        'high',
        'normal',
        'low',
      ]);
    });

    test(
      'within a priority the due date ascending, tasks without date last',
      () {
        final tasks = [
          makeTask(id: 'none'),
          makeTask(id: 'later', dueDate: LocalDate(2026, 10, 20)),
          makeTask(id: 'sooner', dueDate: LocalDate(2026, 10, 5)),
          makeTask(id: 'past', dueDate: LocalDate(2026, 9, 1)),
        ];
        expect(ids(filterAndSortTasks(tasks, const TaskFilter())), [
          'past',
          'sooner',
          'later',
          'none',
        ]);
      },
    );

    test('priority beats the due date', () {
      final tasks = [
        makeTask(id: 'normal-early', dueDate: LocalDate(2026, 9, 1)),
        makeTask(id: 'high-none', priority: TaskPriority.high),
        makeTask(
          id: 'high-late',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 12, 31),
        ),
      ];
      expect(ids(filterAndSortTasks(tasks, const TaskFilter())), [
        'high-late',
        'high-none',
        'normal-early',
      ]);
    });

    test('equal priority and due date: oldest first, then by id', () {
      final tasks = [
        makeTask(id: 'c', createdAtUtc: created(5)),
        makeTask(id: 'b', createdAtUtc: created(5)),
        makeTask(id: 'a', createdAtUtc: created(9)),
        makeTask(id: 'z', createdAtUtc: created(1)),
      ];
      expect(ids(filterAndSortTasks(tasks, const TaskFilter())), [
        'z',
        'b',
        'c',
        'a',
      ]);
    });

    test('the order does not depend on the input order', () {
      final base = [
        makeTask(id: 'a', priority: TaskPriority.high),
        makeTask(id: 'b', dueDate: today),
        makeTask(id: 'c'),
        makeTask(id: 'd', priority: TaskPriority.low, dueDate: yesterday),
        makeTask(id: 'e', createdAtUtc: created(30)),
      ];
      final expected = ids(filterAndSortTasks(base, const TaskFilter()));
      expect(expected, ['a', 'b', 'c', 'e', 'd']);
      expect(
        ids(filterAndSortTasks(base.reversed, const TaskFilter())),
        expected,
      );
    });

    test('the input is not modified', () {
      final tasks = [
        makeTask(id: 'low', priority: TaskPriority.low),
        makeTask(id: 'high', priority: TaskPriority.high),
      ];
      filterAndSortTasks(tasks, const TaskFilter());
      expect(ids(tasks), ['low', 'high']);
    });

    test('compareTasks is total: two different tasks never compare equal', () {
      final a = makeTask(id: 'a');
      final b = makeTask(id: 'b');
      expect(compareTasks(a, b), isNegative);
      expect(compareTasks(b, a), isPositive);
      expect(compareTasks(a, a), 0);
    });
  });

  group('status filter', () {
    final open = makeTask(id: 'open', createdAtUtc: created(1));
    final done = makeTask(
      id: 'done',
      createdAtUtc: created(2),
      completedAtUtc: DateTime.utc(2026, 10, 3, 7),
    );
    final tasks = [open, done];

    test('"Offen" is the default and shows open tasks only', () {
      expect(const TaskFilter().status, TaskStatusFilter.open);
      expect(ids(filterAndSortTasks(tasks, const TaskFilter())), ['open']);
    });

    test('"Erledigt" shows completed tasks only', () {
      expect(
        ids(
          filterAndSortTasks(
            tasks,
            const TaskFilter(status: TaskStatusFilter.completed),
          ),
        ),
        ['done'],
      );
    });

    test('"Alle" shows both', () {
      expect(
        ids(
          filterAndSortTasks(
            tasks,
            const TaskFilter(status: TaskStatusFilter.all),
          ),
        ),
        ['open', 'done'],
      );
    });

    test('German segment labels', () {
      expect(TaskStatusFilter.values.map((s) => s.label).toList(), [
        'Offen',
        'Erledigt',
        'Alle',
      ]);
    });
  });

  group('search over title and description', () {
    final tasks = [
      makeTask(
        id: 'title',
        title: 'Steuererklärung abgeben',
        createdAtUtc: created(1),
      ),
      makeTask(
        id: 'desc',
        title: 'Papierkram',
        description: 'Dazu die STEUER-ID heraussuchen',
        createdAtUtc: created(2),
      ),
      makeTask(
        id: 'other',
        title: 'Einkaufen',
        description: 'Milch, Brot',
        createdAtUtc: created(3),
      ),
      makeTask(id: 'umlaut', title: 'Müller anrufen', createdAtUtc: created(4)),
    ];

    List<String> search(String query) => ids(
      filterAndSortTasks(
        tasks,
        TaskFilter(status: TaskStatusFilter.all, query: query),
      ),
    );

    test('matches the title, case-insensitively', () {
      expect(search('steuererklärung'), ['title']);
      expect(search('STEUERERKLÄRUNG'), ['title']);
    });

    test('matches the description', () {
      expect(search('steuer-id'), ['desc']);
      expect(search('brot'), ['other']);
    });

    test('title and description hits are both returned', () {
      expect(search('steuer'), ['title', 'desc']);
    });

    test('the query is trimmed; blank means no search', () {
      expect(search('  Brot  '), ['other']);
      expect(search('   '), hasLength(4));
      expect(search(''), hasLength(4));
    });

    test('umlauts are matched case-insensitively but diacritics as typed', () {
      expect(search('MÜLLER'), ['umlaut']);
      expect(search('müller'), ['umlaut']);
      expect(search('muller'), isEmpty, reason: 'no diacritic folding');
    });

    test('no match gives an empty list', () {
      expect(search('xyz'), isEmpty);
    });

    test('tags are not searched', () {
      final tagged = [
        makeTask(id: 'tag', title: 'a', tags: ['wichtig']),
      ];
      expect(
        filterAndSortTasks(tagged, const TaskFilter(query: 'wichtig')),
        isEmpty,
      );
    });
  });

  group('priority filter', () {
    final tasks = [
      makeTask(id: 'l', priority: TaskPriority.low),
      makeTask(id: 'n'),
      makeTask(id: 'h', priority: TaskPriority.high),
    ];

    test('null shows every priority', () {
      expect(filterAndSortTasks(tasks, const TaskFilter()), hasLength(3));
    });

    test('a priority restricts the list', () {
      expect(
        ids(
          filterAndSortTasks(
            tasks,
            const TaskFilter(priority: TaskPriority.high),
          ),
        ),
        ['h'],
      );
      expect(
        ids(
          filterAndSortTasks(
            tasks,
            const TaskFilter(priority: TaskPriority.low),
          ),
        ),
        ['l'],
      );
    });

    test('status, search and priority combine with AND', () {
      final mixed = [
        makeTask(id: '1', title: 'Bericht', priority: TaskPriority.high),
        makeTask(id: '2', title: 'Bericht', priority: TaskPriority.low),
        makeTask(
          id: '3',
          title: 'Bericht',
          priority: TaskPriority.high,
          completedAtUtc: DateTime.utc(2026, 10, 3, 7),
        ),
        makeTask(id: '4', title: 'Anderes', priority: TaskPriority.high),
      ];
      expect(
        ids(
          filterAndSortTasks(
            mixed,
            const TaskFilter(query: 'bericht', priority: TaskPriority.high),
          ),
        ),
        ['1'],
      );
    });
  });

  group('TaskFilter value', () {
    test('copyWith replaces fields and clearPriority resets the priority', () {
      const filter = TaskFilter(priority: TaskPriority.high, query: 'x');
      expect(filter.copyWith(status: TaskStatusFilter.all).priority, isNotNull);
      expect(filter.copyWith(clearPriority: true).priority, isNull);
      expect(filter.copyWith(query: 'y').query, 'y');
    });

    test('equality is by value', () {
      expect(const TaskFilter(), const TaskFilter());
      expect(const TaskFilter(query: 'a'), isNot(const TaskFilter(query: 'b')));
      expect(const TaskFilter().hashCode, const TaskFilter().hashCode);
    });

    test('isNarrowed ignores the status but sees query and priority', () {
      expect(const TaskFilter().isNarrowed, isFalse);
      expect(
        const TaskFilter(status: TaskStatusFilter.all).isNarrowed,
        isFalse,
      );
      expect(const TaskFilter(query: '  ').isNarrowed, isFalse);
      expect(const TaskFilter(query: 'a').isNarrowed, isTrue);
      expect(const TaskFilter(priority: TaskPriority.low).isNarrowed, isTrue);
    });
  });

  group('overdue and due text (specification 9.1)', () {
    test('overdue is open AND due before today', () {
      expect(makeTask(dueDate: yesterday).isOverdueOn(today), isTrue);
      expect(makeTask(dueDate: today).isOverdueOn(today), isFalse);
      expect(makeTask(dueDate: tomorrow).isOverdueOn(today), isFalse);
      expect(makeTask().isOverdueOn(today), isFalse);
    });

    test('a completed task is never overdue', () {
      final done = makeTask(
        dueDate: yesterday,
        completedAtUtc: DateTime.utc(2026, 10, 3, 7),
      );
      expect(done.isOverdueOn(today), isFalse);
    });

    test('due today is exactly today and open', () {
      expect(makeTask(dueDate: today).isDueTodayOn(today), isTrue);
      expect(makeTask(dueDate: tomorrow).isDueTodayOn(today), isFalse);
      expect(makeTask(dueDate: yesterday).isDueTodayOn(today), isFalse);
    });

    test('overdue becomes true when the day changes', () {
      final task = makeTask(dueDate: today);
      expect(task.isOverdueOn(today), isFalse);
      expect(task.isOverdueOn(tomorrow), isTrue);
    });

    test('the due text names the state in words, not only colour', () {
      expect(
        taskDueText(makeTask(dueDate: yesterday), today),
        'Überfällig seit 02.10.2026',
      );
      expect(taskDueText(makeTask(dueDate: today), today), 'Heute fällig');
      expect(taskDueText(makeTask(dueDate: tomorrow), today), 'Morgen fällig');
      expect(
        taskDueText(makeTask(dueDate: LocalDate(2026, 10, 15)), today),
        'Fällig am 15.10.2026',
      );
      expect(taskDueText(makeTask(), today), isNull);
      expect(
        taskDueText(
          makeTask(
            dueDate: yesterday,
            completedAtUtc: DateTime.utc(2026, 10, 3, 7),
          ),
          today,
        ),
        'Fällig am 02.10.2026',
        reason: 'a completed task is not overdue',
      );
    });

    test('TaskListItem exposes the flag and the text for the UI', () {
      final item = TaskListItem(
        task: makeTask(dueDate: yesterday),
        today: today,
      );
      expect(item.overdue, isTrue);
      expect(item.dueText, startsWith('Überfällig'));
      final plain = TaskListItem(task: makeTask(), today: today);
      expect(plain.overdue, isFalse);
      expect(plain.dueText, isNull);
    });
  });

  group('dashboard list (up to three open tasks that apply today)', () {
    test('open tasks without date or due up to today apply', () {
      expect(makeTask().appliesOn(today), isTrue);
      expect(makeTask(dueDate: yesterday).appliesOn(today), isTrue);
      expect(makeTask(dueDate: today).appliesOn(today), isTrue);
    });

    test('due tomorrow does not apply today, due today does', () {
      expect(makeTask(dueDate: tomorrow).appliesOn(today), isFalse);
      expect(makeTask(dueDate: today).appliesOn(today), isTrue);
      expect(
        makeTask(dueDate: tomorrow).appliesOn(tomorrow),
        isTrue,
        reason: 'it shows up when its day has come',
      );
    });

    test('completed tasks never appear', () {
      final done = makeTask(completedAtUtc: DateTime.utc(2026, 10, 3, 7));
      expect(done.appliesOn(today), isFalse);
      expect(buildDashboardTasks([done], today).items, isEmpty);
    });

    test('at most three tasks, in default order', () {
      final tasks = [
        makeTask(id: '5', priority: TaskPriority.low),
        makeTask(id: '1', priority: TaskPriority.high, dueDate: yesterday),
        makeTask(id: '4'),
        makeTask(id: '2', priority: TaskPriority.high, dueDate: today),
        makeTask(id: '3', dueDate: today),
      ];
      final dashboard = buildDashboardTasks(tasks, today);
      expect(ids(dashboard.items.map((i) => i.task)), ['1', '2', '3']);
      expect(dashboard.applicableOpenCount, 5);
      expect(dashboard.moreCount, 2);
    });

    test('future tasks are excluded from the list and from the count', () {
      final tasks = [
        makeTask(id: 'now'),
        makeTask(id: 'future', dueDate: tomorrow),
      ];
      final dashboard = buildDashboardTasks(tasks, today);
      expect(ids(dashboard.items.map((i) => i.task)), ['now']);
      expect(dashboard.applicableOpenCount, 1);
      expect(dashboard.moreCount, 0);
    });

    test('an empty input gives an empty list', () {
      final dashboard = buildDashboardTasks(const [], today);
      expect(dashboard.items, isEmpty);
      expect(dashboard.applicableOpenCount, 0);
    });

    test('items carry the overdue flag for the shown day', () {
      final dashboard = buildDashboardTasks([
        makeTask(id: 'late', dueDate: yesterday),
        makeTask(id: 'ok', dueDate: today),
      ], today);
      expect(dashboard.items.map((i) => i.overdue).toList(), [true, false]);
    });

    test('a smaller limit can be requested', () {
      final tasks = [for (var i = 0; i < 5; i++) makeTask(id: 'id$i')];
      expect(buildDashboardTasks(tasks, today, limit: 1).items, hasLength(1));
      expect(buildDashboardTasks(tasks, today).items, hasLength(3));
    });
  });
}
