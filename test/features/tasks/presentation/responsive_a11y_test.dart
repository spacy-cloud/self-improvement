import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/application/habit_day_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/task_list.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/presentation/habit_detail_screen.dart';
import 'package:self_improvement/features/tasks/presentation/habit_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';
import 'package:self_improvement/features/tasks/presentation/task_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// One screen state of the module with the data it needs.
class _Screen {
  const _Screen(this.name, this.build);

  final String name;

  /// Seeds the data and returns the widget to pump.
  final Future<Widget> Function(WidgetTester tester, TasksUiEnv env) build;
}

final _today = LocalDate(2026, 10, 3);

Future<void> _seedHabits(WidgetTester tester, TasksUiEnv env) async {
  env.moveTo(LocalDate(2026, 9, 20));
  final lesen = await env.addHabit(tester, 'Zehn Minuten lesen');
  final lange = await env.addHabit(
    tester,
    'Ein sehr langer Name einer Gewohnheit der über mehrere Zeilen läuft',
    icon: HabitIcon.flame,
  );
  await env.addHabit(tester, 'Meditation', icon: HabitIcon.moon);
  for (final date in [
    LocalDate(2026, 9, 22),
    LocalDate(2026, 9, 23),
    LocalDate(2026, 10, 2),
    _today,
  ]) {
    env.moveTo(date);
    await env.checkHabit(tester, lesen, date);
  }
  await env.checkHabit(tester, lange, LocalDate(2026, 10, 2));
  env.moveTo(_today);
}

Future<void> _seedTasks(WidgetTester tester, TasksUiEnv env) async {
  await env.addTask(
    tester,
    'Präsentation Lernfeld zehn vorbereiten und abgeben',
    priority: TaskPriority.high,
    dueDate: LocalDate(2026, 10, 1),
    tags: ['Schule', 'Abgabe'],
    description: 'Folien und Handout',
  );
  await env.addTask(tester, 'Einkaufen', dueDate: _today, tags: ['Privat']);
  await env.addTask(tester, 'Fahrrad reparieren', priority: TaskPriority.low);
  final done = await env.addTask(tester, 'Steuer machen');
  await tester.runAsync(
    () => env.tasks.setCompleted(
      commandId: env.harness.ids.newId(),
      id: done,
      completed: true,
    ),
  );
}

final List<_Screen> _screens = <_Screen>[
  _Screen('habits tab', (tester, env) async {
    await _seedHabits(tester, env);
    return const HabitsTabScreen();
  }),
  _Screen('habits tab, past day', (tester, env) async {
    await _seedHabits(tester, env);
    env.container
        .read(selectedHabitDayProvider.notifier)
        .select(_today.addDays(-1));
    return const HabitsTabScreen();
  }),
  _Screen('habits tab, no habits', (tester, env) async {
    return const HabitsTabScreen();
  }),
  _Screen('tasks tab', (tester, env) async {
    await _seedTasks(tester, env);
    return const HabitsTabScreen(showTasks: true);
  }),
  _Screen('tasks tab, completed and filtered', (tester, env) async {
    await _seedTasks(tester, env);
    env.container.read(taskListControllerProvider.notifier)
      ..setStatus(TaskStatusFilter.all)
      ..setPriority(TaskPriority.high)
      ..setQuery('Präsentation');
    return const HabitsTabScreen(showTasks: true);
  }),
  _Screen('tasks tab, no tasks', (tester, env) async {
    return const HabitsTabScreen(showTasks: true);
  }),
  _Screen('new task form', (tester, env) async {
    await _seedTasks(tester, env);
    return const TaskFormScreen();
  }),
  _Screen('edit task form', (tester, env) async {
    await _seedTasks(tester, env);
    final task = (await env.allTasks(tester)).first;
    return TaskFormScreen(taskId: task.id);
  }),
  _Screen('new habit form', (tester, env) async => const HabitFormScreen()),
  _Screen('edit habit form with reminder', (tester, env) async {
    final id = await env.addHabit(
      tester,
      'Lesen',
      reminder: const LocalTime(7, 30),
    );
    return HabitFormScreen(habitId: id);
  }),
  _Screen('habit detail', (tester, env) async {
    await _seedHabits(tester, env);
    final habit = (await env.allHabits(tester)).first;
    return HabitDetailScreen(habitId: habit.id);
  }),
  _Screen('dashboard card', (tester, env) async {
    await _seedTasks(tester, env);
    return cardHost();
  }),
  _Screen('dashboard card, empty', (tester, env) async => cardHost()),
];

void main() {
  setUpAll(allowMultipleDatabases);

  group('responsive layout (AT33)', () {
    for (final scale in [1.0, 2.0]) {
      for (final screen in _screens) {
        testWidgets(
          '${screen.name} fits 320, 360, 393 and 430 px at ${scale}x text',
          (tester) async {
            final env = await createTasksUiEnv(tester);
            final widget = await screen.build(tester, env);
            for (final size in responsiveSizes) {
              await pumpApp(
                tester,
                widget,
                container: env.container,
                size: size,
                textScale: scale,
              );
              await pumpData(tester);
              await tester.pump(const Duration(milliseconds: 300));
              // An overflow would be thrown as an exception by the framework.
              expect(
                tester.takeException(),
                isNull,
                reason: '${screen.name} at ${size.width}x${size.height}',
              );
            }
          },
        );
      }
    }
  });

  group('tap targets and labels', () {
    for (final scale in [1.0, 2.0]) {
      for (final screen in _screens) {
        testWidgets(
          '${screen.name} has 48 px targets with labels at ${scale}x text',
          (tester) async {
            final handle = tester.ensureSemantics();
            final env = await createTasksUiEnv(tester);
            final widget = await screen.build(tester, env);
            for (final size in [responsiveSizes.first, responsiveSizes.last]) {
              await pumpApp(
                tester,
                widget,
                container: env.container,
                size: size,
                textScale: scale,
              );
              await pumpData(tester);
              await tester.pump(const Duration(milliseconds: 300));
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
            }
            handle.dispose();
          },
        );
      }
    }
  });

  group('themes', () {
    for (final theme in AppThemeVariant.values) {
      for (final screen in _screens) {
        testWidgets('${screen.name} works in the ${theme.name} theme', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final env = await createTasksUiEnv(tester);
          final widget = await screen.build(tester, env);
          await pumpApp(tester, widget, container: env.container, theme: theme);
          await pumpData(tester);
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          handle.dispose();
        });
      }
    }
  });

  group('screen reader', () {
    testWidgets('icon buttons of the tab have German labels', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedTasks(tester, env);
      await pumpApp(
        tester,
        const HabitsTabScreen(showTasks: true),
        container: env.container,
      );
      await pumpData(tester);

      expect(find.bySemanticsLabel('Aufgabe hinzufügen'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Suche und Filter einblenden'),
        findsOneWidget,
      );
      expect(
        find.byTooltip(
          'Weitere Aktionen: Präsentation Lernfeld zehn vorbereiten und '
          'abgeben',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a checkbox says what it is and whether it is done', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      await pumpApp(tester, const HabitsTabScreen(), container: env.container);
      await pumpData(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Zehn Minuten lesen').first),
        isSemantics(
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          value: 'erledigt',
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Meditation').first),
        isSemantics(hasCheckedState: true, isChecked: false, value: 'offen'),
      );
      handle.dispose();
    });

    testWidgets('a habit row is spoken with its state and series', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      await pumpApp(tester, const HabitsTabScreen(), container: env.container);
      await pumpData(tester);

      expect(
        find.bySemanticsLabel('Zehn Minuten lesen, erledigt, 2 Tage in Folge'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Meditation, offen, Noch keine Serie'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the day progress is announced as one text with its '
        'percentage', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      await pumpApp(tester, const HabitsTabScreen(), container: env.container);
      await pumpData(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.bySemanticsLabel(RegExp(r'Heute\s+1 von 3 erledigt')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Fortschritt')),
        isSemantics(value: '33 %'),
      );
      handle.dispose();
    });

    testWidgets('the view switch is a mutually exclusive group with the '
        'selected state', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      await _seedTasks(tester, env);
      await pumpApp(tester, const HabitsTabScreen(), container: env.container);
      await pumpData(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Aufgaben, 3 offen')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Gewohnheiten, 1 von 3 erledigt'),
        ),
        isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true),
      );
      handle.dispose();
    });

    testWidgets('a form error is read together with its field', (tester) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await pumpTasksRouter(tester, env, initialLocation: '/tasks/new');

      await tester.tap(find.text('Aufgabe speichern'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.bySemanticsLabel(
          RegExp('Titel.*Bitte gib einen Titel ein', dotAll: true),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the field message is a live region with icon and text', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        const Scaffold(body: FieldMessage(text: 'Das geht nicht.')),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Das geht nicht.')),
        isSemantics(isLiveRegion: true),
      );
      expect(find.byIcon(AppIcon.error.data), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a past day cell says why it cannot be changed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      final habit = (await env.allHabits(tester)).first;
      await pumpApp(
        tester,
        HabitDetailScreen(habitId: habit.id),
        container: env.container,
      );
      await pumpData(tester);

      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Fr., 18.09.: noch nicht begonnen'),
        ),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Heute, Sa., 03.10.: erledigt, zum Ändern tippen',
          ),
        ),
        isSemantics(
          isButton: true,
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('motion', () {
    testWidgets('the screens work with reduced motion', (tester) async {
      final env = await createTasksUiEnv(tester);
      await _seedHabits(tester, env);
      await pumpApp(
        tester,
        const HabitsTabScreen(),
        container: env.container,
        reducedMotion: true,
      );
      await pumpData(tester);

      await tester.tap(find.byType(RoundCheckbox).first);
      await tester.pumpUntil(() => env.feedback.events.isNotEmpty);
      await pumpData(tester);

      expect(env.feedback.last!.kind, 'saved');
      expect(tester.takeException(), isNull);
    });
  });
}
