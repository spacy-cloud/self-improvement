import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/data/task_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../app/support/app_harness.dart';
import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';

/// The card "Heute abhaken" on the REAL Home of the running app (BS-110): real
/// modules, real router, real bottom navigation, the habits tab behind it.
void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);

  /// Seeds the profile (started long before today, so Home is not the welcome
  /// state), [habits] daily habits and [tasks] open tasks for today.
  Future<void> seed(
    DataHarness h, {
    List<String> habits = const [],
    List<String> tasks = const [],
  }) async {
    await h.seedOnboarded(startedOn: LocalDate(2026, 9, 28));
    final habitRepository = HabitRepository(
      database: h.database,
      runner: h.runner,
    );
    final taskRepository = TaskRepository(
      database: h.database,
      runner: h.runner,
    );
    for (final title in habits) {
      await habitRepository.create(
        commandId: h.ids.newId(),
        draft: HabitDraft(title: title),
      );
    }
    for (final title in tasks) {
      await taskRepository.create(
        commandId: h.ids.newId(),
        draft: TaskDraft(
          title: title,
          priority: TaskPriority.high,
          dueDate: today,
        ),
      );
    }
  }

  Future<AppFixture> pumpHome(
    WidgetTester tester, {
    List<String> habits = const [],
    List<String> tasks = const [],
    Size size = const Size(393, 3200),
    double textScale = 1.0,
  }) async {
    final harness = await createTestHarness(
      tester,
      onboarded: false,
      realProjection: true,
    );
    return pumpFullApp(
      tester,
      reuse: harness,
      onboarded: false,
      size: size,
      textScale: textScale,
      seed: (h) => seed(h, habits: habits, tasks: tasks),
    );
  }

  Finder boxOf(String label) => find.byWidgetPredicate(
    (widget) => widget is RoundCheckbox && widget.semanticLabel == label,
    description: 'the box "$label"',
  );

  bool isChecked(WidgetTester tester, String label) =>
      tester.widget<RoundCheckbox>(boxOf(label)).value;

  Future<void> tick(WidgetTester tester, AppFixture app, String label) async {
    await tester.ensureVisible(boxOf(label));
    await tester.tap(boxOf(label));
    await app.settle();
  }

  group('on the real Home', () {
    testWidgets(
      'the card sits where the tasks card sat, between Fokus and Ernährung (BS-110, C04)',
      (tester) async {
        await pumpHome(
          tester,
          habits: ['Lesen', 'Dehnen'],
          tasks: ['Steuer machen'],
        );

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(find.text('0 von 3 erledigt'), findsOneWidget);
        final fokus = tester.getTopLeft(find.text('Fokus').first).dy;
        final card = tester.getTopLeft(find.text('Heute abhaken')).dy;
        final food = tester.getTopLeft(find.text('Ernährung').first).dy;
        expect(fokus, lessThan(card));
        expect(card, lessThan(food));
        expect(find.byType(RoundCheckbox), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a habit is ticked on Home, is ticked in the real habits tab, and a tick in the tab is there when Home opens again (BS-110, AT21, C04)',
      (tester) async {
        final app = await pumpHome(tester, habits: ['Lesen', 'Dehnen']);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);

        await tick(tester, app, 'Gewohnheit Lesen');
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(find.text('1 von 2 erledigt'), findsOneWidget);

        await tester.tap(navTab('Habits'));
        await app.settle();
        expect(app.location, '/habits');
        expect(
          find.text('1 von 2 erledigt', findRichText: true),
          findsOneWidget,
        );
        expect(isChecked(tester, 'Lesen'), isTrue, reason: 'the tab');
        expect(isChecked(tester, 'Dehnen'), isFalse);

        await tester.tap(boxOf('Dehnen'));
        await app.settle();
        await tester.tap(navTab('Home'));
        await app.settle();

        expect(app.location, '/');
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isTrue);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(find.text('2 von 2 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'the tick of a task and of a habit on Home are real: XP and the day follow (BS-110, T01, T02, G01)',
      (tester) async {
        final app = await pumpHome(
          tester,
          habits: ['Lesen'],
          tasks: ['Steuer machen'],
        );
        final before = (await tester.runAsync(app.harness.totalXp))!;

        await tick(tester, app, 'Aufgabe Steuer machen');
        await tick(tester, app, 'Gewohnheit Lesen');

        expect(
          await tester.runAsync(app.harness.totalXp),
          before + 15,
          reason: 'a task is worth 10 XP, a habit check 5',
        );
        expect(find.text('2 von 2 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'the way to the first habit: "Gewohnheit anlegen" opens the form and the new habit shows on the card (BS-110, T02)',
      (tester) async {
        final app = await pumpHome(tester, tasks: ['Steuer machen']);
        expect(find.text('Noch keine Gewohnheit'), findsOneWidget);

        await tester.ensureVisible(find.text('Gewohnheit anlegen'));
        await tester.tap(find.text('Gewohnheit anlegen'));
        await app.settle();
        await tester.pumpAndSettle();
        expect(find.text('Neue Gewohnheit'), findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'Lesen');
        await tester.pump();
        await tester.ensureVisible(find.text('Gewohnheit speichern'));
        await tester.tap(find.text('Gewohnheit speichern'));
        await app.settle();
        await tester.pumpAndSettle();
        await app.settle();

        expect(app.location, '/');
        expect(find.text('Noch keine Gewohnheit'), findsNothing);
        expect(find.text('Lesen'), findsOneWidget);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
        expect(find.text('0 von 2 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'a user without tasks and habits sees the empty card with both ways to add (BS-110)',
      (tester) async {
        await pumpHome(tester);

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(find.byType(RoundCheckbox), findsNothing);
        expect(find.text('Aufgabe anlegen'), findsOneWidget);
        expect(find.text('Gewohnheit anlegen'), findsOneWidget);
      },
    );
  });

  group('the tasks module as a gate (BS-110, AT03)', () {
    testWidgets(
      'switched off, the card and its habits are gone from Home; switched on again, the data is back as it was',
      (tester) async {
        final app = await pumpHome(
          tester,
          habits: ['Lesen', 'Dehnen'],
          tasks: ['Steuer machen'],
        );
        await tick(tester, app, 'Gewohnheit Lesen');
        expect(find.text('1 von 3 erledigt'), findsOneWidget);

        await app.run(
          () => app.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: 'tasks-off',
                module: ModuleId.tasks,
                enabled: false,
              ),
        );
        await app.settle();

        expect(find.text('Heute abhaken'), findsNothing);
        expect(find.byType(RoundCheckbox), findsNothing);
        expect(find.text('Lesen'), findsNothing);
        expect(find.text('Steuer machen'), findsNothing);
        expect(find.text('Gewohnheit'), findsNothing);
        expect(find.text('Gewohnheit anlegen'), findsNothing);
        expect(tester.takeException(), isNull);

        await app.run(
          () => app.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: 'tasks-on',
                module: ModuleId.tasks,
                enabled: true,
              ),
        );
        await app.settle();

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isFalse);
        expect(find.text('1 von 3 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'the other modules off, the card stays and still ticks (BS-110)',
      (tester) async {
        final harness = await createTestHarness(
          tester,
          onboarded: false,
          realProjection: true,
        );
        final app = await pumpFullApp(
          tester,
          reuse: harness,
          onboarded: false,
          size: const Size(393, 3200),
          seed: (h) => seed(h, habits: ['Lesen']),
        );
        for (final module in [
          ModuleId.body,
          ModuleId.nutrition,
          ModuleId.focus,
          ModuleId.gamification,
        ]) {
          await app.run(
            () => app.container
                .read(moduleManagerProvider)
                .setEnabled(
                  commandId: 'off-${module.key}',
                  module: module,
                  enabled: false,
                ),
          );
        }
        await app.settle();

        expect(find.text('Heute abhaken'), findsOneWidget);
        await tick(tester, app, 'Gewohnheit Lesen');
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
      },
    );
  });

  group('layout on the real Home (AT33, AT35, Q02)', () {
    Future<void> expectOperable(WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      expect(tester.takeException(), isNull, reason: 'no overflow');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    }

    for (final (name, size, scale) in [
      ('320 px at 200 % text', const Size(320, 700), 2.0),
      ('360 px at 100 % text', const Size(360, 800), 1.0),
      ('393 px at 100 % text', const Size(393, 852), 1.0),
      ('430 px at 100 % text', const Size(430, 932), 1.0),
    ]) {
      testWidgets(
        'tasks, many habits and the rest line lay out and are operable at $name (BS-110, AT33)',
        (tester) async {
          final app = await pumpHome(
            tester,
            habits: [for (var i = 1; i <= 7; i++) 'Gewohnheit $i'],
            tasks: ['Steuer machen', 'Einkaufen'],
            size: size,
            textScale: scale,
          );
          await tester.ensureVisible(find.text('Heute abhaken'));
          await app.settle();
          expect(find.text('Heute abhaken'), findsOneWidget);
          await expectOperable(tester);
        },
      );
    }

    for (final theme in ['dark', 'oled']) {
      testWidgets(
        'the card with a done row and a hint lays out and is operable in the $theme theme (BS-110, AT35)',
        (tester) async {
          final app = await pumpHome(
            tester,
            habits: ['Lesen'],
            tasks: ['Steuer machen'],
            size: const Size(393, 852),
          );
          await app.run(
            () => app.container
                .read(settingsCommandsProvider)
                .setThemeMode(
                  commandId: app.harness.ids.newId(),
                  themeModeKey: theme,
                ),
          );
          await app.settle();
          await tester.ensureVisible(find.text('Heute abhaken'));
          await app.settle();
          await tick(tester, app, 'Gewohnheit Lesen');

          expect(find.text('Heute abhaken'), findsOneWidget);
          await expectOperable(tester);
        },
      );
    }
  });
}
