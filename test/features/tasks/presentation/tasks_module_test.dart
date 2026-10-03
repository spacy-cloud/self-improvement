import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/tasks/tasks_module.dart';

import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  const module = TasksModule();

  test('is the tasks module with German texts', () {
    expect(module.id, ModuleId.tasks);
    expect(module.title, 'Aufgaben');
    expect(module.description, 'Aufgaben und tägliche Gewohnheiten');
  });

  test('contributes the full width dashboard card "tasks" at its default '
      'place', () {
    final card = module.dashboardCards.single;
    expect(card.cardId, 'tasks');
    expect(SchemaKeys.dashboardCards, contains(card.cardId));
    expect(SchemaKeys.dashboardCardModule[card.cardId], ModuleId.tasks.key);
    expect(card.fullWidth, isTrue);
    expect(card.title, 'Aufgaben');
    expect(card.defaultRank, SchemaKeys.defaultCardOrder.indexOf('tasks'));
  });

  test('contributes the plus menu entries task (5) and habit (6)', () {
    final byId = {for (final action in module.quickActions) action.id: action};
    expect(byId.keys, unorderedEquals(['task', 'habit']));
    expect(byId['task']!.label, 'Aufgabe');
    expect(byId['task']!.route, '/tasks/new');
    expect(byId['task']!.plusOrder, 5);
    expect(byId['habit']!.label, 'Gewohnheit');
    expect(byId['habit']!.route, '/habits/new');
    expect(byId['habit']!.plusOrder, 6);
  });

  test('registers static paths before the parametric ones and leaves '
      '/habits to the shell', () {
    final paths = [
      for (final route in module.routes)
        if (route is GoRoute) route.path,
    ];
    expect(paths, ['/tasks/new', '/tasks/:id', '/habits/new', '/habits/:id']);
    expect(paths, isNot(contains('/habits')));
    final detail = module.routes.whereType<GoRoute>().last;
    expect(detail.routes.whereType<GoRoute>().single.path, 'edit');
  });

  testWidgets('/tasks/new opens the new task form, not the edit form of a '
      'task called "new"', (tester) async {
    final env = await createTasksUiEnv(tester);
    await pumpTasksRouter(tester, env, initialLocation: '/tasks/new');

    expect(find.text('Neue Aufgabe'), findsOneWidget);
    expect(find.text('Aufgabe bearbeiten'), findsNothing);
  });

  testWidgets('/habits/new opens the new habit form, not a habit detail', (
    tester,
  ) async {
    final env = await createTasksUiEnv(tester);
    await pumpTasksRouter(tester, env, initialLocation: '/habits/new');

    expect(find.text('Neue Gewohnheit'), findsOneWidget);
    expect(find.text('Gewohnheit nicht gefunden'), findsNothing);
  });

  testWidgets('/tasks/:id and /habits/:id/edit open the forms of the record', (
    tester,
  ) async {
    final env = await createTasksUiEnv(tester);
    final taskId = await env.addTask(tester, 'Steuer machen');
    final habitId = await env.addHabit(tester, 'Lesen');
    final router = await pumpTasksRouter(tester, env, initialLocation: '/');

    unawaited(router.push('/tasks/$taskId'));
    await tester.pumpAndSettle();
    expect(find.text('Aufgabe bearbeiten'), findsWidgets);
    router.pop();
    await tester.pumpAndSettle();

    unawaited(router.push('/habits/$habitId/edit'));
    await tester.pumpAndSettle();
    expect(find.text('Gewohnheit bearbeiten'), findsWidgets);
  });
}
