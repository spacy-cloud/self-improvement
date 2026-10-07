import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/goal_destinations.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';

import '../support/goals_today_kit.dart';

// BS-105: a tap on a goal of "Ziele heute" opens the page of its module. The
// assignment goal -> route is made in ONE place (`goalDestination`); these tests
// pin it, as the ticket lists it, and prove that every destination is a route of
// the app that belongs to the module of the goal.

GoalsDayRow _rowOf(GoalType type) => buildGoalsDay(
  status: statusOf(<GoalProgress>[goalOf(type)]),
  today: goalsTestDay,
).rows.single;

GoalsDayRow _habitRow() => buildGoalsDay(
  status: statusOf(<GoalProgress>[habitGoalOf('h')]),
  today: goalsTestDay,
).rows.single;

GoalsDayRow _weeklyRow() => buildGoalsDay(
  status: statusOf(<GoalProgress>[goalOf(GoalType.water)]),
  today: goalsTestDay,
  week: WorkoutWeekSummary(
    weekStart: goalsTestDay.startOfWeek,
    entryCount: 1,
    totalMinutes: 30,
    weeklyTarget: 3,
  ),
).weekly!;

/// Every path of [routes], as the router knows it.
Set<String> _pathsOf(List<RouteBase> routes) => allRoutePaths(routes).toSet();

void main() {
  // The assignment of the ticket (BS-105): water /water, steps /steps, weight
  // /weight, focus /focus, task /habits?tab=tasks, habits /habits, plus the
  // workout area for the two workout goals.
  final expected = <GoalType, GoalDestination>{
    GoalType.water: const GoalDestination('/water'),
    GoalType.steps: const GoalDestination('/steps'),
    GoalType.weightEntry: const GoalDestination('/weight'),
    GoalType.focusMinutes: const GoalDestination('/focus'),
    GoalType.taskCompletion: const GoalDestination(
      '/habits?tab=tasks',
      isTab: true,
    ),
    GoalType.workoutDaily: const GoalDestination('/workouts'),
    GoalType.workoutWeekly: const GoalDestination('/workouts'),
  };

  group('the assignment of goal to page (BS-105)', () {
    test('(C02) every goal type has a destination, as the ticket lists it', () {
      // A new goal type must get a destination: the table is complete.
      expect(expected.keys.toSet(), GoalType.values.toSet());
      for (final type in GoalType.dailyTypes) {
        expect(goalDestination(_rowOf(type)), expected[type], reason: type.key);
      }
      expect(goalDestination(_weeklyRow()), expected[GoalType.workoutWeekly]);
    });

    test('(C02) a habit leads to the habit list, a tab', () {
      expect(
        goalDestination(_habitRow()),
        const GoalDestination('/habits', isTab: true),
      );
    });

    test('(C02) only the two tab destinations are switched to, every other '
        'page is pushed', () {
      final tabs = <String>{
        for (final entry in expected.entries)
          if (entry.value.isTab) entry.key.key,
      };
      expect(tabs, <String>{GoalType.taskCompletion.key});
      expect(goalDestination(_habitRow()).isTab, isTrue);
    });
  });

  group('every destination is a route of the app (BS-105, C02, C03)', () {
    final table = _pathsOf(buildAppRoutes(modules: bundledModules));
    // The real rows, so the destination is the one the page uses.
    final rows = <String, GoalsDayRow>{
      for (final type in GoalType.dailyTypes) type.key: _rowOf(type),
      GoalType.workoutWeekly.key: _weeklyRow(),
      'habit': _habitRow(),
    };

    for (final entry in rows.entries) {
      test('(C02) ${entry.key}: the page is registered', () {
        final destination = goalDestination(entry.value);
        expect(table, contains(Uri.parse(destination.route).path));
      });

      test(
        '(C03) ${entry.key}: the page belongs to the module of the goal',
        () {
          final row = entry.value;
          final destination = goalDestination(row);
          final path = Uri.parse(destination.route).path;
          if (destination.isTab) {
            // The Habits tab is a core destination; its content is the one of
            // the tasks module and the tab gate follows that module.
            expect(path, AppRoutes.habits);
            expect(row.module, ModuleId.tasks);
            return;
          }
          final owner = bundledModules.singleWhere(
            (module) => module.id == row.module,
          );
          expect(
            _pathsOf(owner.routes),
            contains(path),
            reason:
                'a goal of ${row.module.key} must lead to a route that the '
                'module guards (switched off: "Modul ausgeschaltet")',
          );
        },
      );
    }
  });
}
