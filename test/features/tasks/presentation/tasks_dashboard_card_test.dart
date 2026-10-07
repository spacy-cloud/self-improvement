import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// The tasks on the Home card "Heute abhaken". The habits on the card, the
/// synchronisation with the habits tab and the types are in
/// `habits_dashboard_card_test.dart`.
void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);

  Future<GoRouter> pumpCard(
    WidgetTester tester,
    TasksUiEnv env, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
  }) => pumpTasksRouter(
    tester,
    env,
    initialLocation: '/',
    home: cardHost(),
    size: size,
    textScale: textScale,
  );

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await pumpData(tester);
  }

  Future<TasksUiEnv> envWithFiveTasks(WidgetTester tester) async {
    final env = await createTasksUiEnv(tester);
    await env.addTask(tester, 'Z ohne Datum', priority: TaskPriority.low);
    await env.addTask(
      tester,
      'A überfällig hoch',
      priority: TaskPriority.high,
      dueDate: LocalDate(2026, 10, 1),
    );
    await env.addTask(tester, 'B heute', dueDate: today);
    await env.addTask(tester, 'C ohne Datum');
    await env.addTask(tester, 'D heute spät', dueDate: today);
    await env.addTask(tester, 'Später', dueDate: today.addDays(5));
    return env;
  }

  List<String> titles(WidgetTester tester) => [
    for (final title in [
      'A überfällig hoch',
      'B heute',
      'C ohne Datum',
      'D heute spät',
      'Z ohne Datum',
      'Später',
    ])
      if (find.text(title).evaluate().isNotEmpty) title,
  ];

  List<bool> boxes(WidgetTester tester) => [
    for (final box in tester.widgetList<RoundCheckbox>(
      find.byType(RoundCheckbox),
    ))
      box.value,
  ];

  testWidgets(
    'lists up to three applicable open tasks in the defined order and counts the rest (T01, BS-110)',
    (tester) async {
      final env = await envWithFiveTasks(tester);
      await pumpCard(tester, env);

      expect(find.text('Heute abhaken'), findsOneWidget);
      expect(find.text('0 von 5 erledigt'), findsOneWidget);
      // High priority first, then normal by due day (a task without a date is
      // last), the low priority task comes after: only three fit.
      expect(titles(tester), ['A überfällig hoch', 'B heute', 'D heute spät']);
      expect(find.text('und 2 weitere Aufgaben'), findsOneWidget);
      expect(find.text('Später'), findsNothing, reason: 'a future task');
      expect(find.byType(RoundCheckbox), findsNWidgets(3));
      expect(
        tester
            .widgetList<RoundCheckbox>(find.byType(RoundCheckbox))
            .every((box) => box.squared),
        isTrue,
        reason: 'a task has a square box',
      );
    },
  );

  testWidgets('an overdue task says so in words (T01, BS-110)', (tester) async {
    final handle = tester.ensureSemantics();
    final env = await envWithFiveTasks(tester);
    await pumpCard(tester, env);

    expect(find.text('Überfällig seit 01.10.2026'), findsOneWidget);
    expect(find.byIcon(AppIcon.error.data), findsOneWidget);
    expect(find.text('Heute fällig'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel(
        'Aufgabe A überfällig hoch, Priorität Hoch, '
        'Überfällig seit 01.10.2026, offen',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets(
    'completes a task with ONE tap and without opening it; it stays on the card, done (AT13, T01, BS-110)',
    (tester) async {
      final env = await envWithFiveTasks(tester);
      final router = await pumpCard(tester, env);

      await tester.tap(find.byType(RoundCheckbox).first);
      await waitForFeedback(tester, env);

      expect(env.feedback.last!.message, 'Aufgabe erledigt');
      expect(env.feedback.last!.undo, isNotNull);
      expect(locationOf(router), '/', reason: 'the detail was not opened');
      final done = (await env.allTasks(tester))
          .firstWhere((task) => task.title == 'A überfällig hoch');
      expect(done.isCompleted, isTrue);
      expect(await tester.runAsync(env.harness.totalXp), 10);
      // The task stays, checked and struck through, with the time of the
      // completion (10:00 Berlin); the next open task moves up.
      expect(find.text('A überfällig hoch'), findsOneWidget);
      expect(boxes(tester), [true, false, false, false]);
      expect(find.text('Erledigt um 10:00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('A überfällig hoch')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(titles(tester), [
        'A überfällig hoch',
        'B heute',
        'C ohne Datum',
        'D heute spät',
      ]);
      expect(find.text('1 von 5 erledigt'), findsOneWidget);
      expect(find.text('und 1 weitere Aufgabe'), findsOneWidget);
    },
  );

  testWidgets(
    'a completed task shows the time it was completed at, in its own words (T01, BS-110)',
    (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Mathe-Hausaufgabe', dueDate: today);
      setLocalNow(env.harness, today, const LocalTime(8, 15));
      await pumpCard(tester, env);

      await tester.tap(find.byType(RoundCheckbox));
      await waitForFeedback(tester, env);

      expect(find.text('Erledigt um 08:15'), findsOneWidget);
      expect(find.text('Heute fällig'), findsNothing);
      expect(
        find.bySemanticsLabel('Aufgabe Mathe-Hausaufgabe, erledigt um 08:15'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Aufgabe Mathe-Hausaufgabe').first,
        ),
        isSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          value: 'erledigt',
        ),
      );
      handle.dispose();
    },
  );

  testWidgets(
    'the box of a completed task reopens it, with undo (AT13, T01, BS-110)',
    (tester) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Steuer machen');
      await pumpCard(tester, env);
      await tester.tap(find.byType(RoundCheckbox));
      await waitForFeedback(tester, env);
      expect(boxes(tester), [true]);

      await tester.tap(find.byType(RoundCheckbox));
      await waitForFeedback(tester, env, 2);

      expect(env.feedback.last!.message, 'Aufgabe wieder geöffnet');
      expect(env.feedback.last!.undo, isNotNull);
      expect(boxes(tester), [false]);
      expect(find.text('0 von 1 erledigt'), findsOneWidget);
      final task = (await env.allTasks(tester)).single;
      expect(task.isOpen, isTrue);
      expect(await tester.runAsync(env.harness.totalXp), 0);

      await tester.runAsync(env.feedback.last!.undo!.perform);
      await pumpData(tester);
      expect(boxes(tester), [true]);
      expect(await tester.runAsync(env.harness.totalXp), 10);
    },
  );

  testWidgets(
    'a task completed on an earlier day is not on the card (T01, BS-110)',
    (tester) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addTask(tester, 'Gestern erledigt');
      env.moveTo(today.addDays(-1));
      await tester.runAsync(
        () => env.tasks.setCompleted(
          commandId: env.harness.ids.newId(),
          id: id,
          completed: true,
        ),
      );
      env.moveTo(today);
      await env.addTask(tester, 'Heute offen');
      await pumpCard(tester, env);

      expect(find.text('Gestern erledigt'), findsNothing);
      expect(find.text('Heute offen'), findsOneWidget);
      expect(find.text('0 von 1 erledigt'), findsOneWidget);
    },
  );

  testWidgets('the undo of the card brings the task back (AT13, BS-110)', (
    tester,
  ) async {
    final env = await envWithFiveTasks(tester);
    await pumpCard(tester, env);
    await tester.tap(find.byType(RoundCheckbox).first);
    await waitForFeedback(tester, env);

    await tester.runAsync(env.feedback.last!.undo!.perform);
    await pumpData(tester);

    expect(find.text('A überfällig hoch'), findsOneWidget);
    expect(boxes(tester), [false, false, false]);
    expect(await tester.runAsync(env.harness.totalXp), 0);
    expect(find.text('0 von 5 erledigt'), findsOneWidget);
    expect(find.text('und 2 weitere Aufgaben'), findsOneWidget);
  });

  testWidgets('a double tap completes once (AT12, C05, BS-110)', (
    tester,
  ) async {
    final env = await envWithFiveTasks(tester);
    await pumpCard(tester, env);
    final gate = Completer<void>();
    env.tasks.gate = gate;

    await tester.tap(find.byType(RoundCheckbox).first);
    await tester.pump();
    await tester.tap(find.byType(RoundCheckbox).first, warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await waitForFeedback(tester, env);

    expect(env.tasks.commandIds, hasLength(1));
    expect(await tester.runAsync(env.harness.totalXp), 10);
    expect(env.feedback.events, hasLength(1));
  });

  testWidgets(
    'a failed completion keeps the task open on the card; the retry reuses the command id (AT27, AT12, BS-110)',
    (tester) async {
      final env = await envWithFiveTasks(tester);
      await pumpCard(tester, env);
      env.tasks.failNext = 1;

      await tester.tap(find.byType(RoundCheckbox).first);
      await waitForFeedback(tester, env);
      final error = env.feedback.last!;
      expect(error.kind, 'error');
      expect(find.text('A überfällig hoch'), findsOneWidget);
      expect(boxes(tester).first, isFalse);
      expect(find.text('0 von 5 erledigt'), findsOneWidget);
      expect(await tester.runAsync(env.harness.totalXp), 0);

      error.onRetry!();
      await waitForFeedback(tester, env, 2);

      expect(env.tasks.commandIds[0], env.tasks.commandIds[1]);
      expect(boxes(tester).first, isTrue);
      expect(find.text('1 von 5 erledigt'), findsOneWidget);
      expect(await tester.runAsync(env.harness.totalXp), 10);
    },
  );

  testWidgets(
    'without a task or habit for today it says so and offers both ways to add one (BS-110)',
    (tester) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Später', dueDate: today.addDays(5));
      await pumpTasksRouter(
        tester,
        env,
        initialLocation: '/',
        home: cardHost(),
      );

      expect(find.text('Heute abhaken'), findsOneWidget);
      expect(
        find.text(
          'Für heute ist nichts offen. Neue Aufgaben und Gewohnheiten '
          'erscheinen hier.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('erledigt'),
        findsNothing,
        reason: 'no 0 of 0',
      );
      expect(find.text('Später'), findsNothing);
      expect(find.text('Gewohnheit anlegen'), findsOneWidget);
      await tester.tap(find.text('Aufgabe anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Neue Aufgabe'), findsOneWidget);
    },
  );

  testWidgets(
    'a task due later moves onto the card when its day comes (AT25, BS-110)',
    (tester) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Morgen dran', dueDate: today.addDays(1));
      await pumpCard(tester, env);
      expect(find.text('Morgen dran'), findsNothing);

      env.moveTo(today.addDays(1));
      await pumpData(tester);

      expect(find.text('Morgen dran'), findsOneWidget);
      expect(find.text('Heute fällig'), findsOneWidget);
      expect(find.text('0 von 1 erledigt'), findsOneWidget);
    },
  );

  testWidgets(
    'a task completed today leaves the card at midnight (AT25, BS-110)',
    (tester) async {
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'Heute fertig');
      await pumpCard(tester, env);
      await tester.tap(find.byType(RoundCheckbox));
      await waitForFeedback(tester, env);
      expect(find.text('Heute fertig'), findsOneWidget);

      env.moveTo(today.addDays(1));
      await pumpData(tester);

      expect(find.text('Heute fertig'), findsNothing);
      expect(find.text('Heute abhaken'), findsOneWidget);
    },
  );

  testWidgets('the rest line opens the task list (BS-110)', (tester) async {
    final env = await envWithFiveTasks(tester);
    final router = await pumpCard(tester, env);

    await tester.tap(find.text('und 2 weitere Aufgaben'));
    await tester.pumpAndSettle();
    await pumpData(tester);

    expect(locationOf(router), '/habits?tab=tasks');
    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('Z ohne Datum'), findsOneWidget);
  });

  testWidgets('tapping a title opens the task', (tester) async {
    final env = await envWithFiveTasks(tester);
    final router = await pumpCard(tester, env);

    await tester.tap(find.text('B heute'));
    await tester.pumpAndSettle();

    expect(find.text('Aufgabe bearbeiten'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('a load error shows the error state with a retry', (
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
    await env.addTask(tester, 'B heute', dueDate: today);
    await pumpCard(tester, env);

    expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
    await tester.tap(find.text('Erneut versuchen'));
    await pumpData(tester);
    await pumpData(tester);
    expect(find.text('B heute'), findsOneWidget);
  });

  testWidgets('stacks the box above the title at 200 % text (AT33)', (
    tester,
  ) async {
    final env = await envWithFiveTasks(tester);
    await pumpCard(tester, env, size: const Size(320, 640), textScale: 2.0);

    expect(tester.takeException(), isNull);
    final checkbox = tester.getTopLeft(find.byType(RoundCheckbox).first);
    final title = tester.getTopLeft(find.text('A überfällig hoch'));
    expect(title.dy, greaterThan(checkbox.dy + 40), reason: 'title below');
    await tester.tap(find.byType(RoundCheckbox).first);
    await waitForFeedback(tester, env);
    expect(env.feedback.last!.message, 'Aufgabe erledigt');
  });

  testWidgets('uses the full width of the dashboard', (tester) async {
    final env = await envWithFiveTasks(tester);
    await pumpCard(tester, env, size: const Size(430, 932));

    final card = tester.getSize(find.byType(AppCard).first);
    expect(card.width, 430 - 32);
  });
}
