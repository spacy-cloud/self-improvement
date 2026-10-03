import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';
import 'package:self_improvement/features/tasks/presentation/task_row.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);

  Future<void> pumpTasks(WidgetTester tester, TasksUiEnv env) async {
    await pumpApp(
      tester,
      const HabitsTabScreen(showTasks: true),
      container: env.container,
    );
    await pumpData(tester);
  }

  List<String> titlesInOrder(WidgetTester tester) => tester
      .widgetList<TaskRow>(find.byType(TaskRow))
      .map((row) => row.item.task.title)
      .toList();

  Future<void> openMenu(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip('Weitere Aktionen: $title'));
    await tester.pumpAndSettle();
  }

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await pumpData(tester);
  }

  group('list and order', () {
    testWidgets(
      'shows open tasks in the defined order with due text and tags (T01)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await env.addTask(
          tester,
          'A niedrig ohne Datum',
          priority: TaskPriority.low,
        );
        await env.addTask(
          tester,
          'B hoch spät',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 20),
        );
        await env.addTask(
          tester,
          'C hoch früh',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 5),
          tags: ['Schule', 'Büro'],
        );
        await env.addTask(
          tester,
          'D normal überfällig',
          dueDate: LocalDate(2026, 10, 1),
        );
        await env.addTask(tester, 'E normal ohne Datum');
        await env.addTask(
          tester,
          'F normal morgen',
          dueDate: LocalDate(2026, 10, 4),
        );
        await env.addTask(
          tester,
          'G normal heute',
          dueDate: LocalDate(2026, 10, 3),
        );
        await pumpTasks(tester, env);

        expect(titlesInOrder(tester), [
          'C hoch früh',
          'B hoch spät',
          'D normal überfällig',
          'G normal heute',
          'F normal morgen',
          'E normal ohne Datum',
          'A niedrig ohne Datum',
        ]);
        expect(find.text('Überfällig seit 01.10.2026'), findsOneWidget);
        expect(find.text('Heute fällig'), findsOneWidget);
        expect(find.text('Morgen fällig'), findsOneWidget);
        expect(find.text('Fällig am 20.10.2026'), findsOneWidget);
        expect(find.text('#Schule'), findsOneWidget);
        expect(find.text('#Büro'), findsOneWidget);
        expect(find.text('Hoch'), findsNWidgets(2));
        expect(find.text('Niedrig'), findsOneWidget);
        expect(find.text('Normal'), findsNWidgets(4));
      },
    );

    testWidgets('an overdue task is marked by text, not only by colour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(
        tester,
        'Steuer machen',
        priority: TaskPriority.high,
        dueDate: LocalDate(2026, 10, 2),
        tags: ['Büro'],
      );
      await pumpTasks(tester, env);

      expect(find.text('Überfällig seit 02.10.2026'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Steuer machen, Priorität Hoch, Überfällig seit 02.10.2026, offen, '
          'Tags: Büro',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('Erledigt and Alle show the completed tasks', (tester) async {
      final env = await createTasksUiEnv(tester);
      final done = await env.addTask(tester, 'Erledigte Aufgabe');
      await env.addTask(tester, 'Offene Aufgabe');
      await tester.runAsync(
        () => env.tasks.setCompleted(
          commandId: env.harness.ids.newId(),
          id: done,
          completed: true,
        ),
      );
      await pumpTasks(tester, env);
      expect(titlesInOrder(tester), ['Offene Aufgabe']);

      await tester.tap(find.text('Erledigt'));
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Erledigte Aufgabe']);
      expect(find.text('Erledigt am 03.10.2026'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Erledigte Aufgabe'));
      expect(title.style!.decoration, TextDecoration.lineThrough);
      expect(
        tester.widget<RoundCheckbox>(find.byType(RoundCheckbox)).value,
        isTrue,
      );

      await tester.tap(find.text('Alle'));
      await pumpData(tester);
      expect(titlesInOrder(tester), hasLength(2));
    });

    testWidgets('the search finds title and description and offers a reset', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(
        tester,
        'Steuererklärung',
        description: 'Belege sammeln',
      );
      await env.addTask(tester, 'Einkaufen');
      await pumpTasks(tester, env);

      await tester.tap(find.bySemanticsLabel('Suche und Filter einblenden'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '  BELEG ');
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Steuererklärung']);

      await tester.enterText(find.byType(TextField), 'steuer');
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Steuererklärung']);

      await tester.enterText(find.byType(TextField), 'zzz');
      await pumpData(tester);
      expect(find.text('Keine Treffer'), findsOneWidget);
      expect(titlesInOrder(tester), isEmpty);

      await tester.tap(find.text('Suche zurücksetzen'));
      await pumpData(tester);
      expect(titlesInOrder(tester), hasLength(2));
      expect(find.byType(TextField), findsNothing);
      handle.dispose();
    });

    testWidgets('the priority filter shows one priority and can be cleared', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Dringend', priority: TaskPriority.high);
      await env.addTask(tester, 'Normal');
      await env.addTask(tester, 'Irgendwann', priority: TaskPriority.low);
      await pumpTasks(tester, env);

      await tester.tap(find.bySemanticsLabel('Suche und Filter einblenden'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Priorität Hoch'));
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Dringend']);

      await tester.tap(find.bySemanticsLabel('Priorität Niedrig'));
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Irgendwann']);

      await tester.tap(find.text('Alle Prioritäten'));
      await pumpData(tester);
      expect(titlesInOrder(tester), hasLength(3));
      handle.dispose();
    });

    testWidgets('the filter survives leaving the tab and coming back', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Dringend', priority: TaskPriority.high);
      await env.addTask(tester, 'Normal');
      await pumpTasks(tester, env);
      await tester.tap(find.bySemanticsLabel('Suche und Filter einblenden'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.bySemanticsLabel('Priorität Hoch'));
      await pumpData(tester);

      await pumpApp(
        tester,
        const SizedBox(),
        container: env.container,
        wrapInScaffold: true,
      );
      await pumpTasks(tester, env);

      expect(titlesInOrder(tester), ['Dringend']);
      expect(
        find.bySemanticsLabel('Suche und Filter zurücksetzen'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('completion', () {
    testWidgets(
      'completes with undo, reopens and completes again without piling up XP (AT13, T01, G01)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await pumpTasks(tester, env);

        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env);
        expect(env.feedback.last!.message, 'Aufgabe erledigt');
        expect(env.feedback.last!.undo, isNotNull);
        var task = (await env.readTask(tester, id))!;
        expect(task.isCompleted, isTrue);
        expect(task.completionEligibility, isTrue);
        expect(await tester.runAsync(env.harness.totalXp), 10);
        // The open list no longer shows it.
        expect(titlesInOrder(tester), isEmpty);
        expect(find.text('Alles erledigt'), findsOneWidget);

        await tester.tap(find.text('Erledigt'));
        await pumpData(tester);
        expect(titlesInOrder(tester), ['Steuer machen']);

        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env, 2);
        expect(env.feedback.last!.message, 'Aufgabe wieder geöffnet');
        task = (await env.readTask(tester, id))!;
        expect(task.isOpen, isTrue);
        expect(task.completedAtUtc, isNull);
        expect(task.completionEligibility, isNull);
        expect(await tester.runAsync(env.harness.totalXp), 0);

        await tester.tap(find.text('Offen'));
        await pumpData(tester);
        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env, 3);
        expect(await tester.runAsync(env.harness.totalXp), 10);
        task = (await env.readTask(tester, id))!;
        expect(task.isCompleted, isTrue);
      },
    );

    testWidgets(
      'undo of a completion restores the exact open state (AT13, C05)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await pumpTasks(tester, env);
        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env);

        final result = await tester.runAsync(env.feedback.last!.undo!.perform);
        expect(result, isNotNull);
        await pumpData(tester);

        final task = (await env.readTask(tester, id))!;
        expect(task.isOpen, isTrue);
        expect(task.completedAtUtc, isNull);
        expect(task.completedLocalDate, isNull);
        expect(task.completionEligibility, isNull);
        expect(await tester.runAsync(env.harness.totalXp), 0);
        expect(titlesInOrder(tester), ['Steuer machen']);
      },
    );

    testWidgets('a double tap completes once with one command (AT12, C05)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Steuer machen');
      await pumpTasks(tester, env);
      final gate = Completer<void>();
      env.tasks.gate = gate;

      await tester.tap(find.byType(RoundCheckbox));
      await tester.pump();
      await tester.tap(find.byType(RoundCheckbox), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await waitForFeedback(tester, env);

      expect(env.tasks.commandIds, hasLength(1));
      expect(env.feedback.events, hasLength(1));
      expect(await tester.runAsync(env.harness.totalXp), 10);
    });

    testWidgets(
      'a failed completion changes nothing; the retry reuses the command id (AT27, AT12)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await pumpTasks(tester, env);
        env.tasks.failNext = 1;

        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env);
        final error = env.feedback.last!;
        expect(error.kind, 'error');
        expect(error.onRetry, isNotNull);
        expect((await env.readTask(tester, id))!.isOpen, isTrue);
        expect(await tester.runAsync(env.harness.totalXp), 0);
        expect(titlesInOrder(tester), ['Steuer machen']);

        error.onRetry!();
        await waitForFeedback(tester, env, 2);

        expect(env.tasks.commandIds, hasLength(2));
        expect(env.tasks.commandIds[0], env.tasks.commandIds[1]);
        expect(env.feedback.last!.message, 'Aufgabe erledigt');
        expect(await tester.runAsync(env.harness.totalXp), 10);
      },
    );
  });

  group('menu', () {
    testWidgets('offers edit, complete and delete without a gesture', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addTask(tester, 'Steuer machen');
      await pumpTasks(tester, env);

      await openMenu(tester, 'Steuer machen');
      expect(find.text('Bearbeiten'), findsOneWidget);
      expect(find.text('Als erledigt markieren'), findsOneWidget);
      expect(find.text('Löschen'), findsOneWidget);

      await tester.tap(find.text('Als erledigt markieren'));
      await tester.pumpAndSettle();
      await waitForFeedback(tester, env);
      expect((await env.readTask(tester, id))!.isCompleted, isTrue);

      await tester.tap(find.text('Alle'));
      await pumpData(tester);
      await openMenu(tester, 'Steuer machen');
      expect(find.text('Wieder öffnen'), findsOneWidget);
      await tester.tap(find.text('Wieder öffnen'));
      await tester.pumpAndSettle();
      await waitForFeedback(tester, env, 2);
      expect(env.feedback.last!.message, 'Aufgabe wieder geöffnet');
      expect((await env.readTask(tester, id))!.isOpen, isTrue);
    });

    testWidgets(
      'delete asks first: cancel keeps the task, confirm deletes with an exact undo (T01, C05)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(
          tester,
          'Steuer machen',
          priority: TaskPriority.high,
          dueDate: LocalDate(2026, 10, 9),
          tags: ['Büro'],
          description: 'Belege',
        );
        await tester.runAsync(
          () => env.tasks.setCompleted(
            commandId: env.harness.ids.newId(),
            id: id,
            completed: true,
          ),
        );
        final before = (await env.readTask(tester, id))!;
        await pumpTasks(tester, env);
        await tester.tap(find.text('Erledigt'));
        await pumpData(tester);

        await openMenu(tester, 'Steuer machen');
        await tester.tap(find.text('Löschen'));
        await tester.pumpAndSettle();
        expect(find.text('Aufgabe löschen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(env.feedback.events, isEmpty);
        expect((await env.readTask(tester, id)), isNotNull);

        await openMenu(tester, 'Steuer machen');
        await tester.tap(find.text('Löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen').last);
        await tester.pumpAndSettle();
        await waitForFeedback(tester, env);
        expect(env.feedback.last!.message, 'Aufgabe gelöscht');
        expect(await env.readTask(tester, id), isNull);
        expect(titlesInOrder(tester), isEmpty);
        expect(await tester.runAsync(env.harness.totalXp), 0);

        await tester.runAsync(env.feedback.last!.undo!.perform);
        await pumpData(tester);
        final after = (await env.readTask(tester, id))!;
        expect(after.title, before.title);
        expect(after.description, before.description);
        expect(after.priority, before.priority);
        expect(after.dueDate, before.dueDate);
        expect(after.tags, before.tags);
        expect(after.completedAtUtc, before.completedAtUtc);
        expect(after.completedLocalDate, before.completedLocalDate);
        expect(after.completionEligibility, before.completionEligibility);
        expect(await tester.runAsync(env.harness.totalXp), 10);
        expect(titlesInOrder(tester), ['Steuer machen']);
      },
    );

    testWidgets('a failed delete keeps the task and offers a retry (AT27)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addTask(tester, 'Steuer machen');
      await pumpTasks(tester, env);
      env.tasks.failNext = 1;

      await openMenu(tester, 'Steuer machen');
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen').last);
      await tester.pumpAndSettle();
      await waitForFeedback(tester, env);

      final error = env.feedback.last!;
      expect(error.kind, 'error');
      expect(
        error.message,
        'Löschen fehlgeschlagen. Die Aufgabe ist unverändert.',
      );
      expect(await env.readTask(tester, id), isNotNull);

      error.onRetry!();
      await waitForFeedback(tester, env, 2);
      expect(env.tasks.commandIds[0], env.tasks.commandIds[1]);
      expect(await env.readTask(tester, id), isNull);
    });
  });

  group('states and navigation', () {
    testWidgets('without tasks the empty state offers the first one', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await pumpTasksRouter(tester, env, initialLocation: '/habits?tab=tasks');

      expect(find.text('Noch keine Aufgaben'), findsOneWidget);
      await tester.tap(find.text('Aufgabe anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Neue Aufgabe'), findsOneWidget);
    });

    testWidgets(
      'Erledigt without completed tasks says so, Offen with all done celebrates',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await pumpTasks(tester, env);

        await tester.tap(find.text('Erledigt'));
        await pumpData(tester);
        expect(find.text('Noch nichts erledigt'), findsOneWidget);

        await tester.runAsync(
          () => env.tasks.setCompleted(
            commandId: env.harness.ids.newId(),
            id: id,
            completed: true,
          ),
        );
        await tester.tap(find.text('Offen'));
        await pumpData(tester);
        expect(find.text('Alles erledigt'), findsOneWidget);
      },
    );

    testWidgets('a load error shows the error state and retry loads again', (
      tester,
    ) async {
      var calls = 0;
      final env = await createTasksUiEnv(
        tester,
        extraOverrides: [
          tasksProvider.overrideWith((ref) {
            calls++;
            return calls == 1
                ? Stream.error(StateError('disk'))
                : ref.watch(taskRepositoryProvider).watchActive();
          }),
        ],
      );
      await env.addTask(tester, 'Steuer machen');
      await pumpTasks(tester, env);

      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await pumpData(tester);
      await pumpData(tester);
      expect(titlesInOrder(tester), ['Steuer machen']);
    });

    testWidgets('tapping a task opens it for editing', (tester) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Steuer machen');
      final router = await pumpTasksRouter(
        tester,
        env,
        initialLocation: '/habits?tab=tasks',
      );

      await tester.tap(find.text('Steuer machen'));
      await tester.pumpAndSettle();

      expect(find.text('Aufgabe bearbeiten'), findsOneWidget);
      expect(router.canPop(), isTrue);
    });

    testWidgets(
      'a day change moves a due task from "morgen" to "heute" (AT25)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await env.addTask(tester, 'Steuer machen', dueDate: today.addDays(1));
        await pumpTasks(tester, env);
        expect(find.text('Morgen fällig'), findsOneWidget);

        env.moveTo(today.addDays(1));
        await pumpData(tester);
        expect(find.text('Heute fällig'), findsOneWidget);

        env.moveTo(today.addDays(2));
        await pumpData(tester);
        expect(find.text('Überfällig seit 04.10.2026'), findsOneWidget);
      },
    );
  });
}
