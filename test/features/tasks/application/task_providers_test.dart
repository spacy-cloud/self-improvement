import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/task_test_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  late DataHarness harness;
  late ProviderContainer container;
  late TaskRepository repository;

  // "now" is 2026-10-03 10:00 in Berlin.
  final today = LocalDate(2026, 10, 3);

  setUp(() async {
    harness = await DataHarness.create();
    container = harness.createContainer();
    repository = container.read(taskRepositoryProvider);
    container.listen(taskListProvider, (_, _) {});
    container.listen(dashboardTasksProvider, (_, _) {});
    container.listen(taskListControllerProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  Future<void> settle() async {
    await pumpEventQueue();
    await container.read(tasksProvider.future);
  }

  Future<TaskListView> list() async {
    await settle();
    return container.read(taskListProvider).requireValue;
  }

  Future<DashboardTasks> dashboard() async {
    await settle();
    return container.read(dashboardTasksProvider).requireValue;
  }

  Future<String> add(
    String title, {
    TaskPriority priority = TaskPriority.normal,
    LocalDate? due,
    String? description,
  }) async {
    harness.clock.advance(const Duration(seconds: 1));
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(
        title: title,
        priority: priority,
        dueDate: due,
        description: description,
      ),
    );
    return outcome.entityId!;
  }

  Future<void> complete(String id) async {
    await repository.setCompleted(
      commandId: harness.ids.newId(),
      id: id,
      completed: true,
    );
  }

  List<String> titles(TaskListView view) => [
    for (final item in view.items) item.task.title,
  ];

  TaskListController filter() =>
      container.read(taskListControllerProvider.notifier);

  group('task list view (T01)', () {
    test(
      'without any task the list is empty because there are no tasks',
      () async {
        final view = await list();
        expect(view.items, isEmpty);
        expect(view.totalCount, 0);
        expect(view.emptyReason, TaskListEmptyReason.noTasks);
        expect(view.filter, const TaskFilter());
      },
    );

    test(
      'opens on "Offen" and lists open tasks in default order with counts',
      () async {
        await add('niedrig', priority: TaskPriority.low);
        await add('später', due: LocalDate(2026, 11, 1));
        await add('hoch', priority: TaskPriority.high);
        await add('bald', due: LocalDate(2026, 10, 5));
        final done = await add('erledigt');
        await complete(done);
        final view = await list();
        expect(titles(view), ['hoch', 'bald', 'später', 'niedrig']);
        expect(view.totalCount, 5);
        expect(view.openCount, 4);
        expect(view.completedCount, 1);
        expect(view.emptyReason, isNull);
        expect(view.today, today);
      },
    );

    test('the status segments switch the list', () async {
      final done = await add('fertig');
      await add('offen');
      await complete(done);
      filter().setStatus(TaskStatusFilter.completed);
      expect(titles(await list()), ['fertig']);
      filter().setStatus(TaskStatusFilter.all);
      expect(titles(await list()), ['fertig', 'offen']);
      filter().setStatus(TaskStatusFilter.open);
      expect(titles(await list()), ['offen']);
    });

    test(
      'search and priority filter narrow the list; clearNarrowing resets them',
      () async {
        await add('Steuer machen', priority: TaskPriority.high);
        await add('Steuer ablegen', priority: TaskPriority.low);
        await add('Einkaufen', description: 'wegen STEUER-Tipp');
        filter().setQuery('  steuer ');
        expect(titles(await list()), [
          'Steuer machen',
          'Einkaufen',
          'Steuer ablegen',
        ]);
        filter().setPriority(TaskPriority.low);
        expect(titles(await list()), ['Steuer ablegen']);
        filter().setPriority(null);
        expect(await list(), isNotNull);
        expect(container.read(taskListControllerProvider).priority, isNull);
        filter().setPriority(TaskPriority.high);
        filter().clearNarrowing();
        final state = container.read(taskListControllerProvider);
        expect(state.query, isEmpty);
        expect(state.priority, isNull);
        expect(state.status, TaskStatusFilter.open, reason: 'segment stays');
      },
    );

    test('empty reasons: nothing open, or no matches for the search', () async {
      final only = await add('einzige');
      await complete(only);
      expect((await list()).emptyReason, TaskListEmptyReason.nothingOpen);
      filter().setStatus(TaskStatusFilter.completed);
      expect((await list()).emptyReason, isNull);
      filter().setQuery('gibtesnicht');
      expect((await list()).emptyReason, TaskListEmptyReason.noMatches);
    });

    test('nothing completed yet', () async {
      await add('offen');
      filter().setStatus(TaskStatusFilter.completed);
      expect((await list()).emptyReason, TaskListEmptyReason.nothingCompleted);
    });

    test('completing and reopening updates the list live', () async {
      final id = await add('Live');
      expect(titles(await list()), ['Live']);
      await complete(id);
      expect(titles(await list()), isEmpty);
      await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: false,
      );
      expect(titles(await list()), ['Live']);
    });

    test('overdue flag and text follow the day (todayProvider)', () async {
      await add('Fällig heute', due: today);
      final before = (await list()).items.single;
      expect(before.overdue, isFalse);
      expect(before.dueText, 'Heute fällig');

      harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      final after = (await list()).items.single;
      expect(after.overdue, isTrue);
      expect(after.dueText, 'Überfällig seit 03.10.2026');
      expect((await list()).today, LocalDate(2026, 10, 4));
    });

    test('a task moved to completed is not overdue any more', () async {
      final id = await add('Alt', due: LocalDate(2026, 10, 1));
      expect((await list()).items.single.overdue, isTrue);
      await complete(id);
      filter().setStatus(TaskStatusFilter.completed);
      expect((await list()).items.single.overdue, isFalse);
    });
  });

  group('dashboard list (T01)', () {
    test('shows at most three open tasks that apply today', () async {
      await add('A', priority: TaskPriority.low);
      await add('B');
      await add('C', priority: TaskPriority.high);
      await add('D', due: today);
      await add('E', due: LocalDate(2026, 10, 4));
      final view = await dashboard();
      expect([for (final i in view.items) i.task.title], ['C', 'D', 'B']);
      expect(view.applicableOpenCount, 4);
      expect(view.moreCount, 1);
    });

    test(
      'due today is on the dashboard, due tomorrow only in "Alle"',
      () async {
        await add('Heute', due: today);
        await add('Morgen', due: LocalDate(2026, 10, 4));
        expect(
          [for (final i in (await dashboard()).items) i.task.title],
          ['Heute'],
        );
        filter().setStatus(TaskStatusFilter.all);
        expect(titles(await list()), ['Heute', 'Morgen']);
      },
    );

    test(
      'a future task moves onto the dashboard when its day starts',
      () async {
        await add('Morgen', due: LocalDate(2026, 10, 4));
        expect((await dashboard()).items, isEmpty);
        harness.clock.advance(const Duration(days: 1));
        container.read(todayProvider.notifier).refresh();
        final view = await dashboard();
        expect(view.items.single.task.title, 'Morgen');
        expect(view.items.single.overdue, isFalse);
      },
    );

    test('completing a listed task lets the next one move up', () async {
      final ids = [
        for (final title in ['1', '2', '3', '4']) await add(title),
      ];
      expect(
        [for (final i in (await dashboard()).items) i.task.title],
        ['1', '2', '3'],
      );
      await complete(ids[0]);
      final view = await dashboard();
      expect([for (final i in view.items) i.task.title], ['2', '3', '4']);
      expect(view.moreCount, 0);
    });

    test('an empty dashboard has no items and no applicable tasks', () async {
      final view = await dashboard();
      expect(view.items, isEmpty);
      expect(view.applicableOpenCount, 0);
    });
  });

  group('single task provider', () {
    test('emits the task, then updates after an edit', () async {
      final id = await add('Alt');
      final values = <Task?>[];
      container.listen(
        taskProvider(id),
        (_, next) => values.add(next.value),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(values.last?.title, 'Alt');
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: const TaskDraft(title: 'Neu'),
        expectedRowVersion: 1,
      );
      await pumpEventQueue();
      expect(values.last?.title, 'Neu');
    });

    test('an unknown id emits null (not-found screen)', () async {
      container.listen(taskProvider('missing'), (_, _) {});
      final value = await container.read(taskProvider('missing').future);
      expect(value, isNull);
    });

    test('a deleted task becomes null', () async {
      final id = await add('Weg');
      container.listen(taskProvider(id), (_, _) {});
      expect((await container.read(taskProvider(id).future))?.title, 'Weg');
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await pumpEventQueue();
      expect(container.read(taskProvider(id)).value, isNull);
    });

    test('shows the completion of the task live', () async {
      final id = await add('Live');
      container.listen(taskProvider(id), (_, _) {});
      await container.read(taskProvider(id).future);
      await complete(id);
      await pumpEventQueue();
      final task = container.read(taskProvider(id)).requireValue!;
      expect(task.isCompleted, isTrue);
      expect(task.completedLocalDate, today);
    });
  });
}
