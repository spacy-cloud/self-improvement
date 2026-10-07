import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';

import '../support/db_fixtures.dart';
import '../support/pump_app.dart';
import 'support/app_harness.dart';

/// What a tap on the notification of a task reminder opens in the running app
/// (BS-111, AT29): the form "Aufgabe bearbeiten" of the task, on top of what
/// is open; the task list when the task is gone; the dashboard when the module
/// is off or during the onboarding. With the app started by the tap (cold
/// start), running in the foreground, or in the background and brought back.
/// The real modules, the real router and the real forms are on screen; only
/// the operating system is a fake.
void main() {
  // "now" is 2026-10-03 10:00 in Berlin.
  late String taskId;

  /// Creates a task with a reminder through the real command.
  Future<String> seedTask(
    DataHarness harness, {
    String title = 'Steuer machen',
    bool completed = false,
    bool deleted = false,
    bool reminder = true,
  }) async {
    final repository = TaskRepository(
      database: harness.database,
      runner: harness.runner,
    );
    final created = await repository.create(
      commandId: harness.ids.newId(),
      draft: TaskDraft(
        title: title,
        reminderAtUtc: reminder
            ? harness.clock.nowUtc().add(const Duration(hours: 6))
            : null,
      ),
    );
    final id = created.entityId!;
    if (completed) {
      await repository.setCompleted(
        commandId: harness.ids.newId(),
        id: id,
        completed: true,
      );
    }
    if (deleted) {
      await repository.delete(commandId: harness.ids.newId(), id: id);
    }
    return id;
  }

  group('a cold start from the notification (AT29)', () {
    testWidgets('opens the form of the task above the dashboard; back returns '
        'to the dashboard (BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
        preparePlatform: (platform) =>
            platform.launchPayloadValue = '/tasks/$taskId',
      );
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();

      expect(find.text('Aufgabe bearbeiten'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Steuer machen',
        reason: 'the form of exactly this task',
      );
      // Back returns to the dashboard: there is a history below.
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });

    testWidgets('a completed task still opens its form (BS-111)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async =>
            taskId = await seedTask(harness, completed: true),
        preparePlatform: (platform) =>
            platform.launchPayloadValue = '/tasks/$taskId',
      );
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();
      expect(find.text('Aufgabe bearbeiten'), findsWidgets);
    });

    testWidgets('a task that does not exist (any more) opens the task list '
        'with the tasks view selected (BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async =>
            taskId = await seedTask(harness, deleted: true),
        preparePlatform: (platform) =>
            platform.launchPayloadValue = '/tasks/$taskId',
      );
      await tester.pumpUntil(() => app.location == '/habits');
      await app.settle();

      expect(find.text('Aufgabe nicht gefunden'), findsNothing);
      expect(find.text('Aufgabe bearbeiten'), findsNothing);
      // The tasks view of the habits tab: its empty state is on screen.
      expect(find.text('Noch keine Aufgaben'), findsOneWidget);
    });

    testWidgets('the module tasks off opens the dashboard (BS-111)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        enabledModules: <String>{'body', 'nutrition', 'focus', 'gamification'},
        seed: (harness) async => taskId = await seedTask(harness),
        preparePlatform: (platform) =>
            platform.launchPayloadValue = '/tasks/$taskId',
      );
      await app.settle();
      expect(app.location, '/');
      expect(find.text('Aufgabe bearbeiten'), findsNothing);
    });

    testWidgets('during the onboarding the payload is ignored (BS-111)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        onboarded: false,
        preparePlatform: (platform) => platform.launchPayloadValue =
            '/tasks/00000000-0000-4000-8000-0000000000aa',
      );
      await app.settle();
      expect(app.location, '/onboarding');
    });
  });

  group('a tap while the app runs (AT29)', () {
    testWidgets('opens the form on top of what is open and back returns '
        '(BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      app.platform.emitTap('/tasks/$taskId');
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();

      expect(find.text('Aufgabe bearbeiten'), findsWidgets);
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });

    testWidgets('from the task list: back returns to the list (BS-111)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      app.router.go('/habits?tab=tasks');
      await app.settle();
      expect(app.fullLocation, '/habits?tab=tasks');

      app.platform.emitTap('/tasks/$taskId');
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/habits');
    });

    testWidgets('a task deleted after the notification was shown opens the '
        'task list (BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      final repository = app.container.read(taskRepositoryProvider);
      await app.runLive(
        () => repository.delete(commandId: app.harness.ids.newId(), id: taskId),
      );
      app.platform.emitTap('/tasks/$taskId');
      await tester.pumpUntil(() => app.location == '/habits');
      await app.settle();
      expect(find.text('Aufgabe bearbeiten'), findsNothing);
      expect(find.text('Noch keine Aufgaben'), findsOneWidget);
      // The list opens on top of the dashboard: back returns to it.
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });

    testWidgets('a tap never takes an open form away: its input survives '
        '(BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      unawaited(app.router.push<void>('/tasks/new'));
      await app.settle();
      await tester.enterText(find.byType(TextField).first, 'Halb getippt');
      await tester.pump();

      app.platform.emitTap('/tasks/$taskId');
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/tasks/new');
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Halb getippt',
      );
    });

    testWidgets('a tap on the task whose form is already open opens no second '
        'copy (BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      unawaited(app.router.push<void>('/tasks/$taskId'));
      await app.settle();
      expect(app.location, '/tasks/$taskId');

      app.platform.emitTap('/tasks/$taskId');
      await app.settle();
      // One back leaves the form: there was never a second copy.
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });

    testWidgets('a tap on another task opens its form on top of the open one '
        '(BS-111)', (tester) async {
      late String otherId;
      final app = await pumpFullApp(
        tester,
        seed: (harness) async {
          taskId = await seedTask(harness);
          otherId = await seedTask(harness, title: 'Andere Aufgabe');
        },
      );
      unawaited(app.router.push<void>('/tasks/$taskId'));
      await app.settle();

      app.platform.emitTap('/tasks/$otherId');
      await tester.pumpUntil(() => app.location == '/tasks/$otherId');
      await app.settle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Andere Aufgabe',
      );
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/tasks/$taskId');
    });

    testWidgets('the same holds for the detail of a habit (regression of the '
        'guard against a second copy)', (tester) async {
      const habitId = '123e4567-e89b-42d3-a456-426614174000';
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => harness.database
            .into(harness.database.habits)
            .insert(habitRow(id: habitId)),
      );
      app.platform.emitTap('/habits/$habitId');
      await tester.pumpUntil(() => app.location == '/habits/$habitId');
      await app.settle();
      app.platform.emitTap('/habits/$habitId');
      await app.settle();
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });

    testWidgets('a damaged payload opens the dashboard (BS-111)', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      for (final payload in <String>[
        '/tasks/not-an-id',
        '/tasks/',
        '/tasks/00000000-0000-4000-8000-0000000000AA',
        '/tasks/00000000-0000-4000-8000-0000000000aa/edit',
      ]) {
        app.platform.emitTap(payload);
        await app.settle();
        expect(app.location, '/', reason: payload);
      }
    });
  });

  group('the app in the background (AT29)', () {
    testWidgets('a tap that arrives while the app is paused is shown when it '
        'comes back (BS-111)', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async => taskId = await seedTask(harness),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      app.platform.emitTap('/tasks/$taskId');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();

      expect(find.text('Aufgabe bearbeiten'), findsWidgets);
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/');
    });
  });

  group('the notification the engine planned (BS-111, AT29)', () {
    testWidgets('carries a route the router opens: the form of that task '
        'with its title', (tester) async {
      final app = await pumpFullApp(
        tester,
        seed: (harness) async =>
            taskId = await seedTask(harness, title: 'Geheimer Titel'),
      );
      await app.runLive(
        () => app.container
            .read(reminderPreferencesRepositoryProvider)
            .setNotificationsEnabled(
              commandId: app.harness.ids.newId(),
              enabled: true,
            ),
      );
      await tester.pumpUntil(() => app.platform.alarms.isNotEmpty);

      final alarm = app.platform.alarms.values.single;
      expect('${alarm.title}${alarm.payload}', isNot(contains('Geheimer')));
      app.platform.emitTap(alarm.payload);
      await tester.pumpUntil(() => app.location == '/tasks/$taskId');
      await app.settle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Geheimer Titel',
      );
    });
  });
}
