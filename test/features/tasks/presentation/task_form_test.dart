import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);

  final titleField = find.byType(TextField).at(0);
  final tagField = find.byType(TextField).at(1);
  final descriptionField = find.byType(TextField).at(2);

  Future<GoRouter> openForm(
    WidgetTester tester,
    TasksUiEnv env, {
    String location = '/tasks/new',
    Size size = const Size(393, 852),
    double textScale = 1.0,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) async {
    final router = await pumpTasksRouter(
      tester,
      env,
      size: size,
      textScale: textScale,
      viewInsets: viewInsets,
    );
    unawaited(router.push(location));
    await tester.pumpAndSettle();
    await pumpData(tester);
    return router;
  }

  Future<void> save(
    WidgetTester tester, [
    String label = 'Aufgabe speichern',
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

  String textOf(WidgetTester tester, Finder finder) =>
      tester.widget<TextField>(finder).controller!.text;

  group('create', () {
    testWidgets(
      'saves every field, tells the user after the commit and offers undo (T01)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final router = await openForm(tester, env);
        expect(find.text('Neue Aufgabe'), findsOneWidget);

        await tester.enterText(titleField, '  Steuer machen ');
        await tester.tap(find.text('Hoch'));
        await tester.pump();
        await tester.tap(find.text('Morgen'));
        await tester.pump();
        await tester.enterText(tagField, ' Schule ');
        await tester.tap(find.text('Hinzufügen'));
        await tester.pump();
        expect(find.text('#Schule'), findsOneWidget);
        expect(
          textOf(tester, tagField),
          isEmpty,
          reason: 'the input is cleared',
        );
        await tester.enterText(descriptionField, 'Belege sammeln');
        expect(env.feedback.events, isEmpty);

        await save(tester);
        await waitForFeedback(tester, env);

        final tasks = await env.allTasks(tester);
        expect(tasks, hasLength(1));
        final task = tasks.single;
        expect(task.title, 'Steuer machen');
        expect(task.priority, TaskPriority.high);
        expect(task.dueDate, today.addDays(1));
        expect(task.tags, ['Schule']);
        expect(task.description, 'Belege sammeln');
        expect(env.feedback.last!.kind, 'saved');
        expect(env.feedback.last!.message, 'Aufgabe gespeichert');
        expect(find.text('Neue Aufgabe'), findsNothing);
        expect(router.canPop(), isFalse);

        await tester.runAsync(env.feedback.last!.undo!.perform);
        expect(await env.allTasks(tester), isEmpty);
      },
    );

    testWidgets('defaults: normal priority, no date, no tags', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(titleField, 'Einkaufen');

      await save(tester);
      await waitForFeedback(tester, env);

      final task = (await env.allTasks(tester)).single;
      expect(task.priority, TaskPriority.normal);
      expect(task.dueDate, isNull);
      expect(task.tags, isEmpty);
      expect(task.description, isNull);
    });

    testWidgets(
      'Heute, Morgen and Kein Datum set the due day and the field shows it',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(tester, env);
        bool selected(String label) => tester
            .widget<AppChoiceChip>(find.widgetWithText(AppChoiceChip, label))
            .selected;

        expect(selected('Kein Datum'), isTrue);
        expect(find.text('Kein Datum gewählt'), findsOneWidget);

        await tester.tap(find.text('Heute'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(selected('Heute'), isTrue);
        expect(selected('Kein Datum'), isFalse);
        expect(find.text('Samstag, 3. Oktober'), findsOneWidget);

        await tester.tap(find.text('Morgen'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(selected('Morgen'), isTrue);
        expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);

        await tester.tap(find.text('Kein Datum'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Kein Datum gewählt'), findsOneWidget);
      },
    );

    testWidgets('the date picker sets a custom due day, also in the past', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(titleField, 'Steuer machen');

      await tester.tap(find.text('Kein Datum gewählt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Donnerstag, 15. Oktober'), findsOneWidget);
      // The chips of the due day (the block "Erinnerung" has its own, and its
      // "Aus" is selected as long as there is no reminder).
      final dueChips = tester.widgetList<AppChoiceChip>(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppChoiceChip &&
              <String>['Heute', 'Morgen', 'Kein Datum'].contains(widget.label),
        ),
      );
      expect(dueChips, hasLength(3));
      expect(dueChips.where((chip) => chip.selected), isEmpty);

      await save(tester);
      await waitForFeedback(tester, env);
      expect(
        (await env.allTasks(tester)).single.dueDate,
        LocalDate(2026, 10, 15),
      );
    });

    testWidgets(
      'an empty title shows the hint, keeps the rest and saves nothing (C05)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(tester, env);
        // The block "Erinnerung" made the form taller: bring the field into
        // view first, as a user does before typing into it.
        await tester.ensureVisible(descriptionField);
        await tester.enterText(descriptionField, 'Nur eine Beschreibung');

        await save(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await pumpData(tester);

        expect(find.text('Bitte gib einen Titel ein.'), findsOneWidget);
        expect(textOf(tester, descriptionField), 'Nur eine Beschreibung');
        expect(env.tasks.commandIds, isEmpty);
        expect(env.feedback.events, isEmpty);
        expect(await env.allTasks(tester), isEmpty);

        await tester.enterText(titleField, 'Jetzt mit Titel');
        await tester.pump();
        expect(find.text('Bitte gib einen Titel ein.'), findsNothing);
      },
    );

    testWidgets('title and description stop at 120 and 1.000 characters', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.enterText(titleField, 'T' * 130);
      await tester.enterText(descriptionField, 'D' * 1010);
      await tester.pump();

      expect(textOf(tester, titleField), hasLength(120));
      expect(textOf(tester, descriptionField), hasLength(1000));
    });

    testWidgets(
      'tags: duplicates, a sixth tag and a long tag are refused with a hint and tags can be removed',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(tester, env);
        Future<void> addTag(String text) async {
          await tester.ensureVisible(tagField);
          await tester.enterText(tagField, text);
          await tester.ensureVisible(find.text('Hinzufügen'));
          await tester.tap(find.text('Hinzufügen'));
          await tester.pump();
        }

        await addTag('Büro');
        await addTag('büro');
        expect(find.text('Dieses Tag gibt es schon.'), findsOneWidget);
        expect(find.text('#Büro'), findsOneWidget);
        expect(textOf(tester, tagField), 'büro', reason: 'the input stays');

        await tester.enterText(tagField, 'Haus');
        await tester.pump();
        expect(find.text('Dieses Tag gibt es schon.'), findsNothing);

        await tester.enterText(tagField, '');
        await addTag('');
        expect(find.text('Bitte gib ein Tag ein.'), findsOneWidget);

        await addTag('t' * 21);
        expect(
          find.text('Ein Tag darf höchstens 20 Zeichen lang sein.'),
          findsOneWidget,
        );
        await addTag('t' * 20);
        for (final tag in ['a', 'b', 'c']) {
          await addTag(tag);
        }
        expect(find.byType(AppFilterChip), findsNothing);
        await addTag('sechstes');
        expect(
          find.text('Du kannst höchstens 5 Tags vergeben.'),
          findsOneWidget,
        );
        expect(find.text('#sechstes'), findsNothing);

        await tester.tap(find.text('#Büro'));
        await tester.pump();
        expect(find.text('#Büro'), findsNothing);
        await addTag('sechstes');
        expect(find.text('#sechstes'), findsOneWidget);
      },
    );

    testWidgets('the Enter key of the keyboard adds the tag as well', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.enterText(tagField, 'Schule');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('#Schule'), findsOneWidget);
    });

    testWidgets('the Enter key on an empty tag field adds nothing and shows '
        'no hint', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.tap(tagField);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('Bitte gib ein Tag ein.'), findsNothing);
    });

    testWidgets('tags of other tasks are offered and added with one tap', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await env.addTask(tester, 'A', tags: ['Schule', 'Privat']);
      await env.addTask(tester, 'B', tags: ['Schule']);
      await openForm(tester, env);

      expect(find.text('#Schule'), findsOneWidget);
      expect(find.text('#Privat'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Tag Schule hinzufügen'));
      await tester.pump();

      expect(find.bySemanticsLabel('Tag Schule entfernen'), findsOneWidget);
      expect(find.bySemanticsLabel('Tag Schule hinzufügen'), findsNothing);
      expect(find.bySemanticsLabel('Tag Privat hinzufügen'), findsOneWidget);
      handle.dispose();
    });
  });

  group('safe saving', () {
    testWidgets('a double tap on save saves one task (AT12, C05)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(titleField, 'Steuer machen');
      final gate = Completer<void>();
      env.tasks.gate = gate;

      await save(tester);
      expect(find.text('Wird gespeichert …'), findsOneWidget);
      await tester.tap(find.byType(PrimaryButton), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await waitForFeedback(tester, env);

      expect(env.tasks.commandIds, hasLength(1));
      expect(await env.allTasks(tester), hasLength(1));
      expect(env.feedback.events, hasLength(1));
    });

    testWidgets(
      'a failed save keeps the input; the retry reuses the command id and saves once (AT27, AT12, C05)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(tester, env);
        await tester.enterText(titleField, 'Steuer machen');
        await tester.enterText(descriptionField, 'Belege');
        env.tasks.failNext = 1;

        await save(tester);
        await waitForFeedback(tester, env);

        final error = env.feedback.last!;
        expect(error.kind, 'error');
        expect(
          error.message,
          'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
        );
        expect(error.onRetry, isNotNull);
        expect(textOf(tester, titleField), 'Steuer machen');
        expect(textOf(tester, descriptionField), 'Belege');
        expect(find.text('Neue Aufgabe'), findsOneWidget);
        expect(await env.allTasks(tester), isEmpty);
        expect(await tester.runAsync(env.harness.totalXp), 0);

        error.onRetry!();
        await waitForFeedback(tester, env, 2);

        expect(env.tasks.commandIds, hasLength(2));
        expect(env.tasks.commandIds[0], env.tasks.commandIds[1]);
        expect(await env.allTasks(tester), hasLength(1));
        expect(env.feedback.last!.message, 'Aufgabe gespeichert');
      },
    );

    testWidgets(
      'changed input after a failure is a new save with a new id (AT12)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(tester, env);
        await tester.enterText(titleField, 'Steuer machen');
        env.tasks.failNext = 1;
        await save(tester);
        await waitForFeedback(tester, env);

        await tester.enterText(titleField, 'Steuer erklären');
        await save(tester);
        await waitForFeedback(tester, env, 2);

        expect(env.tasks.commandIds, hasLength(2));
        expect(env.tasks.commandIds[0], isNot(env.tasks.commandIds[1]));
        expect((await env.allTasks(tester)).single.title, 'Steuer erklären');
      },
    );
  });

  group('leaving', () {
    testWidgets(
      'a changed form asks before it is left; Weiter bearbeiten keeps the input, Verwerfen leaves',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final router = await openForm(tester, env);
        await tester.enterText(titleField, 'Halb fertig');
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);
        await tester.tap(find.text('Weiter bearbeiten'));
        await tester.pumpAndSettle();
        expect(find.text('Neue Aufgabe'), findsOneWidget);
        expect(textOf(tester, titleField), 'Halb fertig');

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.tap(find.text('Verwerfen'));
        await tester.pumpAndSettle();
        expect(find.text('Neue Aufgabe'), findsNothing);
        expect(router.canPop(), isFalse);
        expect(await env.allTasks(tester), isEmpty);
      },
    );

    testWidgets('the back button of the header asks as well', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);
      await tester.enterText(titleField, 'Halb fertig');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Zurück'));
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
      expect(find.text('Neue Aufgabe'), findsNothing);
    });

    testWidgets('typing and deleting the same text is not a change', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env);

      await tester.enterText(titleField, 'x');
      await tester.pump();
      await tester.enterText(titleField, '');
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Änderungen verwerfen?'), findsNothing);
    });
  });

  group('edit', () {
    testWidgets(
      'is prefilled, saves only a change and offers an exact undo (T01)',
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
        await openForm(tester, env, location: '/tasks/$id');

        expect(find.text('Aufgabe bearbeiten'), findsWidgets);
        expect(textOf(tester, titleField), 'Steuer machen');
        expect(textOf(tester, descriptionField), 'Belege');
        expect(find.text('#Büro'), findsOneWidget);
        expect(find.text('Freitag, 9. Oktober'), findsOneWidget);
        expect(
          tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
          isNull,
          reason: 'nothing changed yet',
        );

        await tester.enterText(titleField, 'Steuer erklären');
        await tester.pump();
        expect(
          tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
          isNotNull,
        );
        await save(tester, 'Änderungen speichern');
        await waitForFeedback(tester, env);

        final saved = (await env.readTask(tester, id))!;
        expect(saved.title, 'Steuer erklären');
        expect(saved.priority, TaskPriority.high);
        expect(saved.tags, ['Büro']);
        expect(env.feedback.last!.message, 'Aufgabe aktualisiert');

        await tester.runAsync(env.feedback.last!.undo!.perform);
        expect((await env.readTask(tester, id))!.title, 'Steuer machen');
      },
    );

    testWidgets('editing keeps the completion of a completed task (T01)', (
      tester,
    ) async {
      final env = await createTasksUiEnv(tester);
      final id = await env.addTask(tester, 'Steuer machen');
      await tester.runAsync(
        () => env.tasks.setCompleted(
          commandId: env.harness.ids.newId(),
          id: id,
          completed: true,
        ),
      );
      final before = (await env.readTask(tester, id))!;
      await openForm(tester, env, location: '/tasks/$id');

      await tester.enterText(titleField, 'Steuer erklären');
      await save(tester, 'Änderungen speichern');
      await waitForFeedback(tester, env);

      final after = (await env.readTask(tester, id))!;
      expect(after.title, 'Steuer erklären');
      expect(after.completedAtUtc, before.completedAtUtc);
      expect(after.completionEligibility, before.completionEligibility);
      expect(await tester.runAsync(env.harness.totalXp), 10);
    });

    testWidgets(
      'delete asks first and can be undone, also from a changed form without a discard dialog (T01, C05)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen', tags: ['Büro']);
        final router = await openForm(tester, env, location: '/tasks/$id');
        await tester.enterText(titleField, 'Geändert, aber gelöscht');
        await tester.pump();

        await tester.ensureVisible(find.text('Aufgabe löschen'));
        await tester.tap(find.text('Aufgabe löschen'));
        await tester.pumpAndSettle();
        expect(find.text('Aufgabe löschen?'), findsOneWidget);
        await tester.tap(find.text('Abbrechen'));
        await tester.pumpAndSettle();
        expect(await env.readTask(tester, id), isNotNull);

        await tester.ensureVisible(find.text('Aufgabe löschen'));
        await tester.tap(find.text('Aufgabe löschen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Löschen'));
        await tester.pumpAndSettle();
        await waitForFeedback(tester, env);

        expect(env.feedback.last!.message, 'Aufgabe gelöscht');
        expect(await env.readTask(tester, id), isNull);
        expect(find.text('Änderungen verwerfen?'), findsNothing);
        expect(find.text('Aufgabe bearbeiten'), findsNothing);
        expect(router.canPop(), isFalse);

        await tester.runAsync(env.feedback.last!.undo!.perform);
        final restored = (await env.readTask(tester, id))!;
        expect(restored.title, 'Steuer machen');
        expect(restored.tags, ['Büro']);
      },
    );

    testWidgets('an unknown task shows the not found state', (tester) async {
      final env = await createTasksUiEnv(tester);
      await openForm(tester, env, location: '/tasks/gibt-es-nicht');

      expect(find.text('Aufgabe nicht gefunden'), findsOneWidget);
      expect(find.text('Zu den Aufgaben'), findsOneWidget);
    });

    testWidgets(
      'a task changed meanwhile is a conflict: message, no retry, input kept',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await openForm(tester, env, location: '/tasks/$id');
        await tester.runAsync(
          () => env.tasks.setCompleted(
            commandId: env.harness.ids.newId(),
            id: id,
            completed: true,
          ),
        );
        await tester.enterText(titleField, 'Steuer erklären');

        await save(tester, 'Änderungen speichern');
        await waitForFeedback(tester, env);

        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Der Eintrag wurde inzwischen geändert.',
        );
        expect(env.feedback.last!.onRetry, isNull);
        expect(textOf(tester, titleField), 'Steuer erklären');
        expect((await env.readTask(tester, id))!.title, 'Steuer machen');
      },
    );
  });

  group('keyboard and large text', () {
    testWidgets(
      'the save button stays reachable with the keyboard open at 200 % text (AT33)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await openForm(
          tester,
          env,
          size: const Size(360, 640),
          textScale: 2.0,
          viewInsets: const EdgeInsets.only(bottom: 280),
        );
        await tester.enterText(titleField, 'Steuer machen');
        await tester.pump();

        expect(find.byType(PrimaryButton).hitTestable(), findsOneWidget);
        await tester.tap(find.byType(PrimaryButton));
        await tester.pump();
        await waitForFeedback(tester, env);

        expect((await env.allTasks(tester)).single.title, 'Steuer machen');
      },
    );

    testWidgets(
      'every field and action can be scrolled to at 200 % text (AT33)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final id = await env.addTask(tester, 'Steuer machen');
        await openForm(
          tester,
          env,
          location: '/tasks/$id',
          size: const Size(320, 640),
          textScale: 2.0,
        );

        for (final label in [
          'Priorität',
          'Fällig am',
          'Tags',
          'Beschreibung',
          'Aufgabe löschen',
        ]) {
          final finder = find.text(label).first;
          await tester.ensureVisible(finder);
          await tester.pump();
          expect(finder.hitTestable(), findsOneWidget, reason: label);
        }
        expect(tester.takeException(), isNull);
      },
    );
  });
}
