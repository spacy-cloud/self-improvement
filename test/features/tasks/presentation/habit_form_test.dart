import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);
  final nameField = find.byType(TextField);

  Future<GoRouter> openForm(
    WidgetTester tester,
    TasksUiEnv env, {
    String location = '/habits/new',
    Size size = const Size(393, 852),
    double textScale = 1.0,
  }) async {
    final router = await pumpTasksRouter(
      tester,
      env,
      size: size,
      textScale: textScale,
    );
    unawaited(router.push(location));
    await tester.pumpAndSettle();
    await pumpData(tester);
    return router;
  }

  Future<void> save(
    WidgetTester tester, [
    String label = 'Gewohnheit speichern',
  ]) async {
    await tester.pump();
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await tester.pumpAndSettle();
    await pumpData(tester);
  }

  group('create', () {
    testWidgets('saves a daily habit with the default symbol and no reminder '
        '(T02)', (tester) async {
      final env = await createTasksUiEnv(tester);
      final router = await openForm(tester, env);
      expect(find.text('Neue Gewohnheit'), findsOneWidget);
      expect(
        find.text('Neue Gewohnheiten zählen ab heute für deinen Tagesring.'),
        findsOneWidget,
      );
      await tester.enterText(nameField, '  10 Min. lesen ');

      await save(tester);
      await waitForFeedback(tester, env);

      final habit = (await env.allHabits(tester)).single;
      expect(habit.title, '10 Min. lesen');
      expect(habit.icon, HabitIcon.book);
      expect(habit.reminderTime, isNull);
      expect(habit.startedOn, today);
      expect(habit.archivedFrom, isNull);
      expect(env.feedback.last!.kind, 'saved');
      expect(env.feedback.last!.message, 'Gewohnheit gespeichert');
      expect(find.text('Neue Gewohnheit'), findsNothing);
      expect(router.canPop(), isFalse);

      await tester.runAsync(env.feedback.last!.undo!.perform);
      expect(await env.allHabits(tester), isEmpty);
    });

    testWidgets('every symbol can be chosen and is stored with its key', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      final router = await pumpTasksRouter(tester, env);

      for (final icon in HabitIcon.values) {
        unawaited(router.push('/habits/new'));
        await tester.pumpAndSettle();
        await pumpData(tester);
        await tester.enterText(nameField, 'Gewohnheit ${icon.label}');
        await tester.tap(find.bySemanticsLabel('Symbol: ${icon.label}'));
        await tester.pump();
        final before = env.feedback.events.length;
        await save(tester);
        await waitForFeedback(tester, env, before + 1);
      }

      final habits = await env.allHabits(tester);
      expect(habits.map((h) => h.icon), HabitIcon.values);
      expect(habits.map((h) => h.title), [
        for (final icon in HabitIcon.values) 'Gewohnheit ${icon.label}',
      ]);
      handle.dispose();
    });

    testWidgets('the selected symbol is marked by a check and the selected '
        'state, not by colour alone', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      SemanticsNode node(String label) =>
          tester.getSemantics(find.bySemanticsLabel(label));
      expect(node('Symbol: Buch'), isSemantics(isSelected: true));
      expect(node('Symbol: Mond'), isSemantics(isSelected: false));
      final tilesWithCheck = find.descendant(
        of: find.bySemanticsLabel('Symbol: Buch'),
        matching: find.byIcon(Icons.check_rounded),
      );
      expect(tilesWithCheck, findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Symbol: Flamme'));
      await tester.pump();
      expect(node('Symbol: Flamme'), isSemantics(isSelected: true));
      expect(node('Symbol: Buch'), isSemantics(isSelected: false));
      handle.dispose();
    });

    testWidgets('V1 habits are daily: no weekday and no time-of-day choice '
        '(T02)', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      expect(find.text('Täglich'), findsOneWidget);
      expect(find.text('Bestimmte Tage'), findsNothing);
      expect(find.text('Morgens'), findsNothing);
      expect(find.text('Mittags & abends'), findsNothing);
    });

    testWidgets('the reminder is off by default and saves its time when '
        'switched on (C08)', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      expect(find.text('Aus'), findsOneWidget);
      expect(find.text('Uhrzeit'), findsNothing);
      await tester.enterText(nameField, 'Lesen');

      await tester.tap(find.text('Tägliche Erinnerung'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Täglich um 20:00 Uhr'), findsOneWidget);
      expect(find.text('Uhrzeit'), findsOneWidget);

      await save(tester);
      await waitForFeedback(tester, env);
      expect(
        (await env.allHabits(tester)).single.reminderTime,
        const LocalTime(20, 0),
      );
    });

    testWidgets('switching the reminder off again saves no reminder', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(nameField, 'Lesen');
      await tester.tap(find.text('Tägliche Erinnerung'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Tägliche Erinnerung'));
      await tester.pump(const Duration(milliseconds: 300));

      await save(tester);
      await waitForFeedback(tester, env);
      expect((await env.allHabits(tester)).single.reminderTime, isNull);
    });

    testWidgets('the time row opens the time picker; cancelling keeps the '
        'time', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.tap(find.text('Tägliche Erinnerung'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Uhrzeit'));
      await tester.pumpAndSettle();
      expect(find.text('Uhrzeit der Erinnerung'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(find.text('Täglich um 20:00 Uhr'), findsOneWidget);
    });

    testWidgets('an empty name shows the hint and saves nothing (C05)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.tap(find.bySemanticsLabel('Symbol: Herz'));
      await tester.pump();

      await save(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await pumpData(tester);

      expect(find.text('Bitte gib einen Titel ein.'), findsOneWidget);
      expect(env.habits.commandIds, isEmpty);
      expect(env.feedback.events, isEmpty);
      expect(await env.allHabits(tester), isEmpty);
      await tester.enterText(nameField, 'Lesen');
      await tester.pump();
      expect(find.text('Bitte gib einen Titel ein.'), findsNothing);
    });

    testWidgets('the name stops at 80 characters', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.enterText(nameField, 'N' * 90);
      await tester.pump();

      expect(
        tester.widget<TextField>(nameField).controller!.text,
        hasLength(80),
      );
    });
  });

  group('safe saving', () {
    testWidgets('a double tap saves one habit (AT12, C05)', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(nameField, 'Lesen');
      final gate = Completer<void>();
      env.habits.gate = gate;

      await save(tester);
      expect(find.text('Wird gespeichert …'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await waitForFeedback(tester, env);

      expect(env.habits.commandIds, hasLength(1));
      expect(await env.allHabits(tester), hasLength(1));
    });

    testWidgets('a failed save keeps the input; the retry reuses the command '
        'id and saves once (AT27, AT12)', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(nameField, 'Lesen');
      await tester.tap(find.bySemanticsLabel('Symbol: Mond'));
      env.habits.failNext = 1;

      await save(tester);
      await waitForFeedback(tester, env);

      final error = env.feedback.last!;
      expect(error.kind, 'error');
      expect(error.onRetry, isNotNull);
      expect(tester.widget<TextField>(nameField).controller!.text, 'Lesen');
      expect(find.text('Neue Gewohnheit'), findsOneWidget);
      expect(await env.allHabits(tester), isEmpty);

      error.onRetry!();
      await waitForFeedback(tester, env, 2);

      expect(env.habits.commandIds[0], env.habits.commandIds[1]);
      final habit = (await env.allHabits(tester)).single;
      expect(habit.icon, HabitIcon.moon);
    });
  });

  group('leaving', () {
    testWidgets('a changed form asks first; Verwerfen leaves, Weiter '
        'bearbeiten stays', (tester) async {
      final env = await createTasksUiEnv(tester);
      final router = await openForm(tester, env);
      await tester.enterText(nameField, 'Halb fertig');
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Neue Gewohnheit'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();
      expect(find.text('Neue Gewohnheit'), findsNothing);
      expect(router.canPop(), isFalse);
      expect(await env.allHabits(tester), isEmpty);
    });

    testWidgets('choosing another symbol counts as a change', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.tap(find.bySemanticsLabel('Symbol: Tropfen'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an untouched form leaves without asking', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Neue Gewohnheit'), findsNothing);
    });
  });

  group('edit', () {
    testWidgets('is prefilled, renames the habit and keeps its history (T02)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addHabit(tester, 'Lesen', icon: HabitIcon.flame);
      await env.checkHabit(tester, id, today);
      await openForm(tester, env, location: '/habits/$id/edit');

      expect(find.text('Gewohnheit bearbeiten'), findsWidgets);
      expect(tester.widget<TextField>(nameField).controller!.text, 'Lesen');
      expect(
        find.text(
          'Der Verlauf bleibt erhalten, wenn du Name, Symbol oder '
          'Erinnerung änderst.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull,
      );

      await tester.enterText(nameField, 'Mehr lesen');
      await tester.tap(find.text('Tägliche Erinnerung'));
      await tester.pump(const Duration(milliseconds: 300));
      await save(tester, 'Änderungen speichern');
      await waitForFeedback(tester, env);

      final habit = (await env.readHabit(tester, id))!;
      expect(habit.title, 'Mehr lesen');
      expect(habit.icon, HabitIcon.flame);
      expect(habit.reminderTime, const LocalTime(20, 0));
      expect(habit.startedOn, today);
      expect(
        await tester.runAsync(() => env.habits.findCheck(id, today)),
        isNotNull,
        reason: 'the history is kept',
      );
      expect(env.feedback.last!.message, 'Gewohnheit aktualisiert');

      await tester.runAsync(env.feedback.last!.undo!.perform);
      expect((await env.readHabit(tester, id))!.title, 'Lesen');
    });

    testWidgets('delete asks first and goes back to the habits; undo restores '
        'the same habit with its history (T02, C05)', (tester) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addHabit(tester, 'Lesen');
      await env.checkHabit(tester, id, today);
      final router = await openForm(tester, env, location: '/habits/$id/edit');
      await tester.enterText(nameField, 'Geändert');
      await tester.pump();

      await tester.ensureVisible(find.text('Gewohnheit löschen'));
      await tester.tap(find.text('Gewohnheit löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Gewohnheit löschen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(await env.readHabit(tester, id), isNotNull);

      await tester.ensureVisible(find.text('Gewohnheit löschen'));
      await tester.tap(find.text('Gewohnheit löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Löschen'));
      await tester.pumpAndSettle();
      await waitForFeedback(tester, env);

      expect(env.feedback.last!.message, 'Gewohnheit gelöscht');
      expect(await env.readHabit(tester, id), isNull);
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(locationOf(router), '/habits');
      expect(find.text('Deine Habits'), findsOneWidget);
      expect(await tester.runAsync(env.harness.totalXp), 0);

      await tester.runAsync(env.feedback.last!.undo!.perform);
      await pumpData(tester);
      final restored = (await env.readHabit(tester, id))!;
      expect(restored.title, 'Lesen');
      expect(
        await tester.runAsync(() => env.habits.findCheck(id, today)),
        isNotNull,
      );
      expect(await tester.runAsync(env.harness.totalXp), 5);
      expect(find.text('Lesen'), findsOneWidget);
    });

    testWidgets('an unknown habit shows the not found state', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env, location: '/habits/gibt-es-nicht/edit');

      expect(find.text('Gewohnheit nicht gefunden'), findsOneWidget);
    });
  });

  testWidgets('works at 200 % text on a narrow phone (AT33)', (tester) async {
    final env = await createTasksUiEnv(tester);
    await openForm(tester, env, size: const Size(320, 640), textScale: 2.0);
    await tester.enterText(nameField, 'Lesen');
    await tester.pump();

    for (final label in [
      'Symbol',
      'Wann?',
      'Erinnerung',
      'Gewohnheit speichern',
    ]) {
      final finder = find.text(label).first;
      await tester.ensureVisible(finder);
      await tester.pump();
      expect(finder.hitTestable(), findsOneWidget, reason: label);
    }
    expect(tester.takeException(), isNull);
  });
}
