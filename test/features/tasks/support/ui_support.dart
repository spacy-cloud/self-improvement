import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/presentation/habits_tab_screen.dart';
import 'package:self_improvement/features/tasks/tasks_module.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../../support/pump_app.dart';
import 'habit_test_support.dart';
import 'task_test_support.dart';

/// Everything a task or habit screen test needs: the in-memory database with
/// the REAL projection (XP and day facts), scripted repositories that can fail
/// or hold a command, a recording feedback service and the container.
class TasksUiEnv {
  TasksUiEnv({
    required this.harness,
    required this.container,
    required this.feedback,
    required this.tasks,
    required this.habits,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final RecordingFeedbackService feedback;
  final ScriptedTaskRepository tasks;
  final ScriptedHabitRepository habits;

  /// Creates a task directly through the repository (not through the UI).
  Future<String> addTask(
    WidgetTester tester,
    String title, {
    TaskPriority priority = TaskPriority.normal,
    LocalDate? dueDate,
    String? description,
    List<String> tags = const [],
  }) async {
    final outcome = (await tester.runAsync(
      () => tasks.create(
        commandId: harness.ids.newId(),
        draft: TaskDraft(
          title: title,
          priority: priority,
          dueDate: dueDate,
          description: description,
          tags: tags,
        ),
      ),
    ))!;
    tasks.commandIds.clear();
    return outcome.entityId!;
  }

  /// Creates a habit directly through the repository; it starts on the day of
  /// the harness clock.
  Future<String> addHabit(
    WidgetTester tester,
    String title, {
    HabitIcon icon = HabitIcon.book,
    LocalTime? reminder,
  }) async {
    final outcome = (await tester.runAsync(
      () => habits.create(
        commandId: harness.ids.newId(),
        draft: HabitDraft.withIcon(
          title: title,
          icon: icon,
          reminderTime: reminder,
        ),
      ),
    ))!;
    habits.commandIds.clear();
    return outcome.entityId!;
  }

  /// Checks a habit day directly through the repository.
  Future<void> checkHabit(
    WidgetTester tester,
    String habitId,
    LocalDate date, {
    bool checked = true,
  }) async {
    await tester.runAsync(
      () => habits.setChecked(
        commandId: harness.ids.newId(),
        habitId: habitId,
        date: date,
        checked: checked,
      ),
    );
    habits.commandIds.clear();
  }

  /// Moves the fake clock to [date] (10:00 Berlin) and refreshes "today".
  void moveTo(LocalDate date) {
    setLocalNow(harness, date);
    container.read(todayProvider.notifier).refresh();
  }

  /// All habits of the database, oldest first.
  Future<List<Habit>> allHabits(WidgetTester tester) async =>
      (await tester.runAsync<List<Habit>>(() => habits.watchAll().first))!;

  /// All active tasks of the database, oldest first.
  Future<List<Task>> allTasks(WidgetTester tester) async =>
      (await tester.runAsync<List<Task>>(() => tasks.watchActive().first))!;

  /// Reads a task from the database (null when it does not exist).
  Future<Task?> readTask(WidgetTester tester, String id) async =>
      tester.runAsync<Task?>(() => tasks.findById(id));

  /// Reads a habit from the database (null when it does not exist).
  Future<Habit?> readHabit(WidgetTester tester, String id) async =>
      tester.runAsync<Habit?>(() => habits.findById(id));
}

/// Creates the environment. The clock starts at 2026-10-03 10:00 Berlin.
Future<TasksUiEnv> createTasksUiEnv(
  WidgetTester tester, {
  String nowIso = '2026-10-03T08:00:00Z',
  bool realProjection = true,
  List<Override> extraOverrides = const [],
}) async {
  final harness = await createTestHarness(
    tester,
    nowIso: nowIso,
    realProjection: realProjection,
    onboarded: false,
  );
  // The profile started long before the days the tests touch, so every day
  // counts for XP and goals.
  await tester.runAsync(
    () => harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1)),
  );
  final feedback = RecordingFeedbackService();
  final tasks = ScriptedTaskRepository(
    database: harness.database,
    runner: harness.runner,
  );
  final habits = ScriptedHabitRepository(
    database: harness.database,
    runner: harness.runner,
  );
  final container = harness.createContainer(
    overrides: [
      feedbackServiceProvider.overrideWithValue(feedback),
      taskRepositoryProvider.overrideWithValue(tasks),
      habitRepositoryProvider.overrideWithValue(habits),
      ...extraOverrides,
    ],
  );
  return TasksUiEnv(
    harness: harness,
    container: container,
    feedback: feedback,
    tasks: tasks,
    habits: habits,
  );
}

/// The routes of the module plus what the app shell provides: the dashboard
/// as `/` and the habits tab as `/habits` (with `?tab=tasks`).
List<RouteBase> tasksUiRoutes() => <RouteBase>[
  GoRoute(
    path: '/',
    builder: (context, state) => const Scaffold(body: Text('Dashboard')),
  ),
  GoRoute(
    path: '/habits',
    builder: (context, state) =>
        HabitsTabScreen(showTasks: state.uri.queryParameters['tab'] == 'tasks'),
  ),
  ...const TasksModule().routes,
];

/// Lets the first reads of the providers arrive (two rounds: the database
/// stream and the derived providers).
Future<void> pumpData(WidgetTester tester) async {
  for (var round = 0; round < 2; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps the module routes like the app shell does and returns the router.
Future<GoRouter> pumpTasksRouter(
  WidgetTester tester,
  TasksUiEnv env, {
  String initialLocation = '/habits',
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  final router = await pumpRouterApp(
    tester,
    routes: tasksUiRoutes(),
    initialLocation: initialLocation,
    container: env.container,
    size: size,
    textScale: textScale,
    viewInsets: viewInsets,
  );
  await pumpData(tester);
  return router;
}

/// The current location of [router], e.g. `/habits?tab=tasks`.
String locationOf(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();
