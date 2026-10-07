import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/goals_today_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import 'dashboard_test_kit.dart';

export 'package:self_improvement/core/goals/domain/day_status.dart'
    show DayStatus, GoalProgress;

// Shared set-up of the "Ziele heute" tests (BS-100): the day status the ring
// counts, in the states of the design, and the page in a small router app.

/// The day of the host tests (the clock of the harness: 3 October 2026).
final LocalDate goalsTestDay = LocalDate(2026, 10, 3);

/// The goal [type] on the day, with its stand [current] (steps: `null` is "no
/// record") and the default target unless [target] says otherwise.
GoalProgress goalOf(
  GoalType type, {
  int? current = 0,
  bool reached = false,
  bool applicable = true,
  int? target,
}) => GoalProgress(
  goalKey: type.key,
  module: type.module,
  target: target ?? type.resolveTarget(null),
  applicable: applicable,
  fulfilled: applicable && reached,
  current: current,
);

/// A habit goal.
GoalProgress habitGoalOf(String id, {bool checked = false}) => GoalProgress(
  goalKey: habitGoalKey(id),
  module: ModuleId.tasks,
  target: null,
  applicable: true,
  fulfilled: checked,
  current: checked ? 1 : 0,
);

/// The status of a day with [goals].
DayStatus statusOf(List<GoalProgress> goals, {LocalDate? date}) =>
    DayStatus(date: date ?? goalsTestDay, goals: goals);

/// Replaces the live status of today (the numbers are what the test is about,
/// not how they arise).
Override todayStatusOverride(DayStatus status) =>
    todayStatusProvider.overrideWith((ref) => Stream<DayStatus?>.value(status));

/// The states of the design: nothing reached, some reached (2 of 5), all
/// reached (5 of 5) and a single goal. The numbers are the ones of the frames.
final Map<String, List<GoalProgress>> goalStates = <String, List<GoalProgress>>{
  'nothing': <GoalProgress>[
    goalOf(GoalType.water, current: 500),
    goalOf(GoalType.steps, current: 1250),
    goalOf(GoalType.focusMinutes, target: 60),
    goalOf(GoalType.weightEntry),
    goalOf(GoalType.taskCompletion),
  ],
  'some': <GoalProgress>[
    goalOf(GoalType.water, current: 1500),
    goalOf(GoalType.steps, current: 7450),
    goalOf(GoalType.focusMinutes, current: 45, target: 60),
    goalOf(GoalType.weightEntry, current: 1, reached: true),
    goalOf(GoalType.taskCompletion, current: 2, reached: true),
  ],
  'all': <GoalProgress>[
    goalOf(GoalType.water, current: 2500, reached: true),
    goalOf(GoalType.steps, current: 10240, reached: true),
    goalOf(GoalType.focusMinutes, current: 60, target: 60, reached: true),
    goalOf(GoalType.weightEntry, current: 1, reached: true),
    goalOf(GoalType.taskCompletion, current: 3, reached: true),
  ],
  'one': <GoalProgress>[goalOf(GoalType.water, current: 2500, reached: true)],
};

/// The pages a goal row or the editor action can open, as plain texts.
const List<String> goalProbePaths = <String>[
  '/goals',
  '/water',
  '/steps',
  '/weight',
  '/focus',
  '/workouts',
  '/habits',
];

/// Pumps "Ziele heute" in a router app: Home is a plain text, every page a goal
/// can lead to is a plain text too, so a test sees where a tap led.
Future<GoRouter> pumpGoalsToday(
  WidgetTester tester,
  DataHarness harness, {
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  String initialLocation = DashboardRoutes.goalsToday,
}) async {
  final container = harness.createContainer(overrides: overrides);
  final router = await pumpRouterApp(
    tester,
    container: container,
    size: size,
    textScale: textScale,
    theme: theme,
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('Seite Home'))),
      ),
      GoRoute(
        path: DashboardRoutes.goalsToday,
        builder: (context, state) => const GoalsTodayScreen(),
      ),
      for (final path in goalProbePaths)
        GoRoute(
          path: path,
          builder: (context, state) =>
              Scaffold(body: Center(child: Text('Seite $path'))),
        ),
    ],
  );
  await settle(tester);
  return router;
}
