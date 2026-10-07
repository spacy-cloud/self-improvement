import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/goals_today_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/data/habit_repository.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import 'dashboard_test_kit.dart';

// Shared set-up of the tests of the day browser (BS-93): Home with the bundled
// modules over a real database, and the records of earlier days.

/// The day of the host tests: 3 October 2026, a Saturday (the clock of the
/// harness reads 10:00 in Europe/Berlin).
final LocalDate hostToday = LocalDate(2026, 10, 3);

/// The profile of the host tests starts well before the days they page back
/// to, so every day of the window can be reached.
final LocalDate hostProfileStart = LocalDate(2026, 9, 1);

/// Home over the real modules and the real database.
final class RealHome {
  const RealHome({
    required this.harness,
    required this.container,
    required this.router,
    required this.feedback,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final GoRouter router;
  final RecordingFeedbackService feedback;

  /// The choice of the day, for tests that page without the page.
  SelectedDayController get days =>
      container.read(selectedDayProvider.notifier);
}

/// Pumps Home (`/`) with the bundled modules, "Ziele heute" and plain pages for
/// the places a goal or "Ziele festlegen" leads to. [seed] runs against the
/// harness before the first frame (records of earlier days).
Future<RealHome> pumpRealHome(
  WidgetTester tester, {
  LocalDate? startedOn,
  String nowIso = '2026-10-03T08:00:00Z',
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  bool reducedMotion = false,
  Set<String>? enabledModules,
  bool workoutDailyGoal = false,
  List<Override> overrides = const <Override>[],
  Future<void> Function(DataHarness harness)? seed,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(nowIso: nowIso, realProjection: true),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(
    () => harness.seedOnboarded(
      enabledModules: enabledModules,
      startedOn: startedOn ?? hostProfileStart,
      workoutDailyGoal: workoutDailyGoal,
    ),
  );
  if (seed != null) {
    await tester.runAsync(() => seed(harness));
  }
  final feedback = RecordingFeedbackService();
  final container = harness.createContainer(
    overrides: <Override>[
      feedbackServiceProvider.overrideWithValue(feedback),
      ...overrides,
    ],
  );
  final router = await pumpRouterApp(
    tester,
    container: container,
    size: size,
    textScale: textScale,
    theme: theme,
    reducedMotion: reducedMotion,
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: DashboardRoutes.goalsToday,
        builder: (context, state) => const GoalsTodayScreen(),
      ),
      for (final path in <String>[
        DashboardRoutes.goals,
        DashboardRoutes.modules,
      ])
        GoRoute(
          path: path,
          builder: (context, state) =>
              Scaffold(body: Center(child: Text('Seite $path'))),
        ),
      for (final module in bundledModules) ...module.routes,
    ],
  );
  await settle(tester);
  return RealHome(
    harness: harness,
    container: container,
    router: router,
    feedback: feedback,
  );
}

/// Pages Home to [day] and lets the cards read it.
Future<void> showDay(WidgetTester tester, RealHome home, LocalDate day) async {
  home.days.select(day);
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

/// 09:00 UTC of [day]: 11:00 or 10:00 in Europe/Berlin, the same calendar day.
DateTime atMorning(LocalDate day, {int hour = 9}) =>
    DateTime.utc(day.year, day.month, day.day, hour);

String _id(RealHome home) => home.harness.ids.newId();

/// Water of [ml] on [day] (in entries of at most 2000 ml).
Future<void> seedWater(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  int ml,
) async {
  var left = ml;
  var hour = 1;
  while (left > 0) {
    final part = left > 2000 ? 2000 : left;
    await tester.runCommand(
      () => home.container
          .read(waterRepositoryProvider)
          .create(
            commandId: _id(home),
            draft: WaterDraft(
              amountMl: part,
              occurredAtUtc: atMorning(day, hour: hour++),
            ),
          ),
    );
    left -= part;
  }
}

/// A step total of [steps] for [day].
Future<void> seedSteps(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  int steps,
) => tester.runCommand(
  () => home.container
      .read(stepsRepositoryProvider)
      .setSteps(commandId: _id(home), date: day, steps: steps),
);

/// A weight measurement of [grams] on [day] at [hour] (UTC).
Future<void> seedWeight(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  int grams, {
  int hour = 6,
}) => tester.runCommand(
  () => home.container
      .read(weightRepositoryProvider)
      .create(
        commandId: _id(home),
        draft: WeightDraft(
          weightGrams: grams,
          occurredAtUtc: atMorning(day, hour: hour),
        ),
      ),
);

/// A meal on [day].
Future<void> seedMeal(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  String name, {
  int? kcal,
  int hour = 5,
}) => tester.runCommand(
  () => home.container
      .read(mealRepositoryProvider)
      .create(
        commandId: _id(home),
        draft: MealDraft(
          name: name,
          kcal: kcal,
          occurredAtUtc: atMorning(day, hour: hour),
        ),
      ),
);

/// A workout on [day].
Future<void> seedWorkout(
  WidgetTester tester,
  RealHome home,
  LocalDate day, {
  String title = 'Oberkörper',
  int minutes = 45,
  List<MuscleGroup> groups = const <MuscleGroup>[],
  int hour = 4,
}) => tester.runCommand(
  () => home.container
      .read(workoutRepositoryProvider)
      .create(
        commandId: _id(home),
        draft: WorkoutDraft(
          category: TrainingCategory.strength,
          durationMinutes: minutes,
          occurredAtUtc: atMorning(day, hour: hour),
          title: title,
          muscleGroups: groups,
        ),
      ),
);

/// A rest day or a skipped day for [day] (the goal "Workout heute" must be on
/// for it to count).
Future<void> seedWorkoutMark(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  WorkoutDayMarkKind kind,
) => tester.runCommand(
  () => home.container
      .read(workoutDayMarkRepositoryProvider)
      .mark(commandId: _id(home), kind: kind, date: day),
);

/// A focus session of [minutes] minutes, started on [day] and saved after
/// them (the real commands: the clock is put to the day while it runs).
Future<void> seedFocus(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  int minutes,
) async {
  final focus = home.container.read(focusRepositoryProvider);
  final started = await atInstant(
    tester,
    home,
    atMorning(day, hour: 10),
    () => focus.start(
      commandId: _id(home),
      category: FocusCategory.reading,
      plannedSeconds: minutes * 60,
    ),
  );
  await atInstant(
    tester,
    home,
    atMorning(day, hour: 10).add(Duration(minutes: minutes)),
    () => focus.save(commandId: _id(home), id: started.entityId!),
  );
}

/// Runs [action] with the clock set to [at] and puts it back after (a task is
/// completed "now", a habit starts "today": to have them on an earlier day the
/// clock has to be there).
Future<T> atInstant<T>(
  WidgetTester tester,
  RealHome home,
  DateTime at,
  Future<T> Function() action,
) async {
  final before = home.harness.clock.nowUtc();
  home.harness.clock.setNow(at);
  try {
    return await tester.runCommand(action);
  } finally {
    home.harness.clock.setNow(before);
  }
}

/// A task completed on [day].
Future<void> seedCompletedTask(
  WidgetTester tester,
  RealHome home,
  LocalDate day,
  String title,
) async {
  final tasks = home.container.read(taskRepositoryProvider);
  final created = await atInstant(
    tester,
    home,
    atMorning(day, hour: 7),
    () => tasks.create(
      commandId: _id(home),
      draft: TaskDraft(title: title),
    ),
  );
  await atInstant(
    tester,
    home,
    atMorning(day, hour: 8),
    () => tasks.setCompleted(
      commandId: _id(home),
      id: created.entityId!,
      completed: true,
    ),
  );
}

/// A habit that existed from [startedOn] on, checked on [checked], written
/// BEFORE Home is pumped (give it to `pumpRealHome` as `seed`): the snapshots of
/// the days since [startedOn] are built from the habits that exist when they are
/// first read, so a habit that was there on those days has to be there before.
/// (In the app a habit always starts today, so it never joins a day before.)
Future<String> seedHabitBeforeHome(
  DataHarness harness,
  String title, {
  required LocalDate startedOn,
  List<LocalDate> checked = const <LocalDate>[],
}) async {
  final habits = HabitRepository(
    database: harness.database,
    runner: harness.runner,
  );
  final now = harness.clock.nowUtc();
  harness.clock.setNow(atMorning(startedOn, hour: 6));
  final created = await habits.create(
    commandId: harness.ids.newId(),
    draft: HabitDraft(title: title),
  );
  harness.clock.setNow(now);
  for (final day in checked) {
    await habits.setChecked(
      commandId: harness.ids.newId(),
      habitId: created.entityId!,
      date: day,
      checked: true,
    );
  }
  return created.entityId!;
}

/// A habit that started on [startedOn], checked on [checked]. Returns its id.
Future<String> seedHabit(
  WidgetTester tester,
  RealHome home,
  String title, {
  required LocalDate startedOn,
  List<LocalDate> checked = const <LocalDate>[],
}) async {
  final habits = home.container.read(habitRepositoryProvider);
  final created = await atInstant(
    tester,
    home,
    atMorning(startedOn, hour: 6),
    () => habits.create(
      commandId: _id(home),
      draft: HabitDraft(title: title),
    ),
  );
  final id = created.entityId!;
  for (final day in checked) {
    await tester.runCommand(
      () => habits.setChecked(
        commandId: _id(home),
        habitId: id,
        date: day,
        checked: true,
      ),
    );
  }
  return id;
}

/// The text of every `MetricCard`-like title that is on screen (for order
/// checks): finds the texts among [titles] in the order they appear on the
/// page, top to bottom.
List<String> cardsInOrder(WidgetTester tester, List<String> titles) {
  final found = <(String, double)>[
    for (final title in titles)
      if (find.text(title).evaluate().isNotEmpty)
        (title, tester.getTopLeft(find.text(title).first).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return <String>[for (final entry in found) entry.$1];
}
