import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);

  Future<TasksUiEnv> envWithHabits(
    WidgetTester tester, {
    List<String> titles = const ['Lesen', 'Dehnen', 'Wasser trinken'],
  }) async {
    final env = await createTasksUiEnv(tester);
    env.moveTo(LocalDate(2026, 9, 28));
    for (final title in titles) {
      await env.addHabit(tester, title);
    }
    env.moveTo(today);
    return env;
  }

  Future<void> pumpTab(
    WidgetTester tester,
    TasksUiEnv env, {
    bool showTasks = false,
  }) async {
    await pumpApp(
      tester,
      HabitsTabScreen(showTasks: showTasks),
      container: env.container,
    );
    await pumpData(tester);
  }

  testWidgets('shows the progress of today, the series and the state (T02)', (
    tester,
  ) async {
    final env = await envWithHabits(tester);
    final habits = await env.allHabits(tester);
    final read = habits!.first.id;
    for (var d = 28; d <= 30; d++) {
      env.moveTo(LocalDate(2026, 9, d));
      await env.checkHabit(tester, read, LocalDate(2026, 9, d));
    }
    env.moveTo(today);
    await env.checkHabit(tester, read, today);
    await pumpTab(tester, env);

    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Deine Habits'), findsOneWidget);
    expect(find.text('1 von 3 erledigt', findRichText: true), findsOneWidget);
    expect(find.text('Lesen'), findsOneWidget);
    expect(find.text('Dehnen'), findsOneWidget);
    expect(find.text('Wasser trinken'), findsOneWidget);
    // Series of "Lesen": 28, 29, 30 September and today (1 and 2 October are
    // open, so only today counts).
    expect(find.text('1 Tag in Folge'), findsOneWidget);
    expect(find.text('Noch keine Serie'), findsNWidgets(2));
    expect(find.text('Täglich'), findsNWidgets(3));
    final boxes = tester
        .widgetList<RoundCheckbox>(find.byType(RoundCheckbox))
        .map((box) => box.value);
    expect(boxes, [true, false, false]);
  });

  testWidgets('one tap checks a habit, offers undo and undo restores it '
      '(AT21, T02, G01)', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    await pumpTab(tester, env);

    await tester.tap(find.byType(RoundCheckbox));
    await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
    await pumpData(tester);

    final saved = env.feedback.last!;
    expect(saved.kind, 'saved');
    expect(saved.message, 'Abgehakt');
    expect(saved.undo, isNotNull);
    final id = (await env.allHabits(tester)).single.id;
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, today)),
      isNotNull,
    );
    expect(find.text('1 von 1 erledigt', findRichText: true), findsOneWidget);
    expect(find.text('Alles geschafft!'), findsOneWidget);
    expect(await tester.runAsync(env.harness.totalXp), 5);

    final result = await tester.runAsync(saved.undo!.perform);
    expect(result, isNotNull);
    await pumpData(tester);
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, today)),
      isNull,
    );
    expect(find.text('0 von 1 erledigt', findRichText: true), findsOneWidget);
    expect(find.text('Alles geschafft!'), findsNothing);
    expect(await tester.runAsync(env.harness.totalXp), 0);
  });

  testWidgets('removing a check sets the desired state and can be undone '
      '(AT21)', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final id = (await env.allHabits(tester)).single.id;
    await env.checkHabit(tester, id, today);
    await pumpTab(tester, env);
    expect(
      tester.widget<RoundCheckbox>(find.byType(RoundCheckbox)).value,
      isTrue,
    );

    await tester.tap(find.byType(RoundCheckbox));
    await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
    await pumpData(tester);

    expect(env.feedback.last!.message, 'Haken entfernt');
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, today)),
      isNull,
    );
    expect(
      tester.widget<RoundCheckbox>(find.byType(RoundCheckbox)).value,
      isFalse,
    );

    await tester.runAsync(env.feedback.last!.undo!.perform);
    await pumpData(tester);
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, today)),
      isNotNull,
    );
  });

  testWidgets('a double tap runs one command with one id (AT12, C05)', (
    tester,
  ) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    await pumpTab(tester, env);
    final gate = Completer<void>();
    env.habits.gate = gate;

    await tester.tap(find.byType(RoundCheckbox));
    await tester.pump();
    await tester.tap(find.byType(RoundCheckbox), warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
    await pumpData(tester);

    expect(env.habits.commandIds, hasLength(1));
    expect(env.feedback.events, hasLength(1));
    final id = (await env.allHabits(tester)).single.id;
    expect(await tester.runAsync(env.harness.totalXp), 5);
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, today)),
      isNotNull,
    );
  });

  testWidgets('a failed check keeps the day open; the retry reuses the command '
      'id and checks once (AT27, AT12)', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    await pumpTab(tester, env);
    env.habits.failNext = 1;

    await tester.tap(find.byType(RoundCheckbox));
    await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
    await pumpData(tester);

    final error = env.feedback.last!;
    expect(error.kind, 'error');
    expect(error.message, contains('Speichern fehlgeschlagen'));
    expect(error.onRetry, isNotNull);
    expect(
      tester.widget<RoundCheckbox>(find.byType(RoundCheckbox)).value,
      isFalse,
    );
    expect(await tester.runAsync(env.harness.totalXp), 0);

    error.onRetry!();
    await tester.pumpUntil(() => env.feedback.events.length == 2);
    await pumpData(tester);

    expect(env.habits.commandIds, hasLength(2));
    expect(env.habits.commandIds[0], env.habits.commandIds[1]);
    expect(env.feedback.last!.message, 'Abgehakt');
    expect(await tester.runAsync(env.harness.totalXp), 5);
  });

  testWidgets('without habits the empty state offers the first one', (
    tester,
  ) async {
    final env = await createTasksUiEnv(tester);
    final router = await pumpTasksRouter(tester, env);

    expect(find.text('Noch keine Gewohnheit'), findsOneWidget);
    expect(find.text('0 von 0 erledigt', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Gewohnheit anlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Gewohnheit'), findsOneWidget);
  });

  testWidgets('with only archived habits the empty state says so', (
    tester,
  ) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final id = (await env.allHabits(tester)).single.id;
    await tester.runAsync(
      () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
    );
    env.moveTo(today.addDays(1));
    await pumpTab(tester, env);

    expect(find.text('Keine aktive Gewohnheit'), findsOneWidget);
    expect(find.text('Lesen'), findsNothing);
  });

  testWidgets('a load error shows the error state and retry loads again', (
    tester,
  ) async {
    var calls = 0;
    final env = await createTasksUiEnv(
      tester,
      extraOverrides: [
        habitsProvider.overrideWith((ref) {
          calls++;
          return calls == 1
              ? Stream.error(StateError('disk'))
              : ref.watch(habitRepositoryProvider).watchAll();
        }),
      ],
    );
    env.moveTo(LocalDate(2026, 9, 28));
    await env.addHabit(tester, 'Lesen');
    env.moveTo(today);
    await pumpTab(tester, env);

    expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
    expect(find.text('Lesen'), findsNothing);
    await tester.tap(find.text('Erneut versuchen'));
    await pumpData(tester);
    await pumpData(tester);
    expect(find.text('Lesen'), findsOneWidget);
    expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
  });

  testWidgets('the week strip shows seven days with completion text', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
    final habits = (await env.allHabits(tester));
    env.moveTo(yesterday);
    await env.checkHabit(tester, habits.first.id, yesterday);
    await env.checkHabit(tester, habits.last.id, yesterday);
    env.moveTo(today);
    await env.checkHabit(tester, habits.first.id, today);
    await pumpTab(tester, env);

    expect(
      find.bySemanticsLabel('Heute, Sa., 03.10.: 1 von 2 erledigt'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Fr., 02.10.: 2 von 2 erledigt'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('So., 27.09.: Keine Gewohnheit'),
      findsOneWidget,
    );
    expect(find.text('Mo'), findsWidgets);
    handle.dispose();
  });

  testWidgets('a past day of the strip corrects a forgotten day (AT23, G01)', (
    tester,
  ) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final id = (await env.allHabits(tester)).single.id;
    await pumpTab(tester, env);
    final handle = tester.ensureSemantics();

    await tester.tap(find.bySemanticsLabel('Fr., 02.10.: 0 von 1 erledigt'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gestern'), findsOneWidget);
    expect(find.text('Habits am Fr., 02.10.'), findsOneWidget);
    expect(find.text('Zurück zu heute'), findsOneWidget);
    // The series belongs to today and is not shown for a past day.
    expect(find.text('Noch keine Serie'), findsNothing);

    await tester.tap(find.byType(RoundCheckbox));
    await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
    await pumpData(tester);

    expect(env.feedback.last!.message, 'Abgehakt');
    expect(
      await tester.runAsync(() => env.habits.findCheck(id, yesterday)),
      isNotNull,
    );
    expect(await tester.runAsync(env.harness.totalXp), 5);
    expect(find.text('1 von 1 erledigt', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Zurück zu heute'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Deine Habits'), findsOneWidget);
    expect(find.text('0 von 1 erledigt', findRichText: true), findsOneWidget);
    // Yesterday counts for the series now (an open today does not break it).
    expect(find.text('1 Tag in Folge'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a day before the habit existed shows nothing to correct', (
    tester,
  ) async {
    final env = await createTasksUiEnv(tester);
    await env.addHabit(tester, 'Lesen');
    await pumpTab(tester, env);
    final handle = tester.ensureSemantics();

    await tester.tap(find.bySemanticsLabel('Fr., 02.10.: Keine Gewohnheit'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Keine Gewohnheit an diesem Tag'), findsOneWidget);
    expect(find.byType(RoundCheckbox), findsNothing);
    handle.dispose();
  });

  testWidgets('archiving shows the hint today and the habit is gone tomorrow '
      '(AT21, AT24)', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final id = (await env.allHabits(tester)).single.id;
    await tester.runAsync(
      () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
    );
    await pumpTab(tester, env);
    expect(find.text('Ab morgen archiviert'), findsOneWidget);
    expect(find.text('Lesen'), findsOneWidget);

    env.moveTo(today.addDays(1));
    await pumpData(tester);
    expect(find.text('Lesen'), findsNothing);
    expect(find.text('Keine aktive Gewohnheit'), findsOneWidget);
  });

  testWidgets('a new day shows the habits unchecked without a restart '
      '(AT25, C08)', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
    final habits = (await env.allHabits(tester));
    await env.checkHabit(tester, habits.first.id, today);
    await env.checkHabit(tester, habits.last.id, today);
    await pumpTab(tester, env);
    expect(find.text('2 von 2 erledigt', findRichText: true), findsOneWidget);

    env.moveTo(today.addDays(1));
    await pumpData(tester);

    expect(find.text('0 von 2 erledigt', findRichText: true), findsOneWidget);
    expect(
      tester
          .widgetList<RoundCheckbox>(find.byType(RoundCheckbox))
          .map((box) => box.value),
      [false, false],
    );
    expect(find.text('Noch keine Serie'), findsNothing);
    expect(find.text('1 Tag in Folge'), findsNWidgets(2));
  });

  testWidgets('the segments switch the view and write it to the route', (
    tester,
  ) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    await env.addTask(tester, 'Steuer machen');
    final router = await pumpTasksRouter(tester, env);
    expect(find.text('Deine Habits'), findsOneWidget);

    await tester.tap(find.text('Aufgaben'));
    await pumpData(tester);
    expect(locationOf(router), '/habits?tab=tasks');
    expect(find.text('Steuer machen'), findsOneWidget);
    expect(find.text('Deine Habits'), findsNothing);

    await tester.tap(find.text('Gewohnheiten'));
    await pumpData(tester);
    expect(locationOf(router), '/habits');
    expect(find.text('Deine Habits'), findsOneWidget);
  });

  testWidgets('the deep link tab=tasks opens the task list', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    await env.addTask(tester, 'Steuer machen');
    await pumpTasksRouter(tester, env, initialLocation: '/habits?tab=tasks');

    expect(find.text('Steuer machen'), findsOneWidget);
    expect(find.text('Deine Habits'), findsNothing);
  });

  testWidgets('the badges show the open tasks and the habit progress', (
    tester,
  ) async {
    final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
    final habits = (await env.allHabits(tester));
    await env.checkHabit(tester, habits.first.id, today);
    await env.addTask(tester, 'Steuer machen');
    await env.addTask(tester, 'Einkaufen');
    await pumpTab(tester, env);

    expect(find.text('2 offen'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('the plus button opens the form of the selected view', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final router = await pumpTasksRouter(tester, env);

    await tester.tap(find.bySemanticsLabel('Gewohnheit hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Gewohnheit'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aufgaben'));
    await pumpData(tester);
    await tester.tap(find.bySemanticsLabel('Aufgabe hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('Neue Aufgabe'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('tapping a habit opens its detail', (tester) async {
    final env = await envWithHabits(tester, titles: ['Lesen']);
    final router = await pumpTasksRouter(tester, env);

    await tester.tap(find.text('Lesen'));
    await tester.pumpAndSettle();
    expect(find.text('Letzte 30 Tage'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('every symbol keeps its own accent in the list', (tester) async {
    final env = await createTasksUiEnv(tester);
    env.moveTo(LocalDate(2026, 9, 28));
    for (final icon in HabitIcon.values) {
      await env.addHabit(tester, icon.label, icon: icon);
    }
    env.moveTo(today);
    await pumpTab(tester, env);

    for (final icon in HabitIcon.values) {
      expect(find.text(icon.label), findsOneWidget);
    }
    expect(find.byType(AppIconTile), findsNWidgets(HabitIcon.values.length));
  });
}
