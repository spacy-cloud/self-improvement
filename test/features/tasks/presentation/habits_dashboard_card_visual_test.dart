import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// Writes a PNG of the Home card "Heute abhaken" in its states below
/// `build/habits_dashboard_card/` for the visual comparison with the Figma
/// frames `4116:421` (Hell), `4116:822` (Dunkel) and `4116:1223` (OLED). Only
/// runs when the environment variable CHECKLIST_PNG is set, so the normal test
/// run stays fast:
///
///     CHECKLIST_PNG=1 flutter test test/features/tasks/presentation/habits_dashboard_card_visual_test.dart
void main() {
  if (!Platform.environment.containsKey('CHECKLIST_PNG')) {
    return;
  }
  setUpAll(allowMultipleDatabases);
  const dir = 'build/habits_dashboard_card';
  final today = LocalDate(2026, 10, 3);

  Future<void> shot(
    WidgetTester tester,
    TasksUiEnv env,
    String name, {
    bool readOnly = false,
  }) async {
    for (final (suffix, theme, size, scale) in [
      ('', AppThemeVariant.light, const Size(393, 852), 1.0),
      ('-dark', AppThemeVariant.dark, const Size(393, 852), 1.0),
      ('-oled', AppThemeVariant.oled, const Size(393, 852), 1.0),
      ('-320-x2', AppThemeVariant.light, const Size(320, 1400), 2.0),
    ]) {
      await pumpRouterApp(
        tester,
        routes: tasksUiRoutes(home: cardHost(readOnly: readOnly)),
        initialLocation: '/',
        container: env.container,
        theme: theme,
        textScale: scale,
        size: size,
      );
      await pumpData(tester);
      // A change of the theme fades over 200 ms: wait for the end of it.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await savePng(tester, '$dir/$name$suffix.png');
    }
  }

  Future<TasksUiEnv> seeded(
    WidgetTester tester, {
    bool withTasks = true,
    List<String> habits = const [],
    Set<String> checked = const {},
    Set<String> doneTasks = const {},
    bool lesenIsOpen = true,
  }) async {
    final env = await createTasksUiEnv(tester);
    env.moveTo(LocalDate(2026, 9, 28));
    final ids = <String, String>{};
    for (final title in habits) {
      ids[title] = await env.addHabit(tester, title);
    }
    env.moveTo(today);
    final tasks = <String, String>{};
    if (withTasks) {
      tasks['Figma-Prototyp verlinken'] = await env.addTask(
        tester,
        'Figma-Prototyp verlinken',
        dueDate: today,
      );
      tasks['Mathe-Hausaufgabe'] = await env.addTask(
        tester,
        'Mathe-Hausaufgabe',
        dueDate: today,
        priority: TaskPriority.low,
      );
    }
    for (final title in doneTasks) {
      setLocalNow(env.harness, today, const LocalTime(8, 15));
      await tester.runAsync(
        () => env.tasks.setCompleted(
          commandId: env.harness.ids.newId(),
          id: tasks[title]!,
          completed: true,
        ),
      );
    }
    setLocalNow(env.harness, today);
    for (final title in checked) {
      // "10 Minuten lesen" is the open habit with a series of five days; the
      // others are checked today.
      final open = lesenIsOpen && title == '10 Minuten lesen';
      for (var back = 1; back <= (open ? 5 : 4); back++) {
        await env.checkHabit(tester, ids[title]!, today.addDays(-back));
      }
      if (!open) {
        await env.checkHabit(tester, ids[title]!, today);
      }
    }
    return env;
  }

  const figmaHabits = ['10 Minuten lesen', 'Vitamine nehmen', 'Dehnen'];

  testWidgets('like the design: two tasks and three habits', (tester) async {
    final env = await seeded(
      tester,
      habits: figmaHabits,
      checked: {'10 Minuten lesen', 'Vitamine nehmen'},
      doneTasks: {'Mathe-Hausaufgabe'},
    );
    await shot(tester, env, 'mixed');
  });

  testWidgets('everything done', (tester) async {
    final env = await seeded(
      tester,
      habits: figmaHabits,
      checked: {...figmaHabits},
      doneTasks: {'Figma-Prototyp verlinken', 'Mathe-Hausaufgabe'},
      lesenIsOpen: false,
    );
    await shot(tester, env, 'all-done');
  });

  testWidgets('many habits', (tester) async {
    final env = await seeded(
      tester,
      habits: [for (var i = 1; i <= 8; i++) 'Gewohnheit $i'],
      checked: {'Gewohnheit 2', 'Gewohnheit 7'},
    );
    await shot(tester, env, 'many');
  });

  testWidgets('tasks without a habit', (tester) async {
    final env = await seeded(tester);
    await shot(tester, env, 'no-habit');
  });

  testWidgets('nothing at all', (tester) async {
    final env = await seeded(tester, withTasks: false);
    await shot(tester, env, 'empty');
  });

  testWidgets('read only', (tester) async {
    final env = await seeded(
      tester,
      habits: figmaHabits,
      checked: {'Vitamine nehmen'},
    );
    await shot(tester, env, 'read-only', readOnly: true);
  });
}
