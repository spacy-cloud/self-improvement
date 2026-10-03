import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/tasks/presentation/habit_detail_screen.dart';
import 'package:self_improvement/features/tasks/presentation/habit_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/task_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_dashboard_card.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';

/// The `tasks` module: tasks and daily habits.
///
/// Routes: `/tasks/new`, `/tasks/:id` (edit), `/habits/new`, `/habits/:id`
/// (detail) and `/habits/:id/edit`; the static paths come first so `new` is
/// never read as an id. `/habits` itself (the tab with `?tab=tasks`) belongs to
/// the app shell, which builds `HabitsTabScreen`.
final class TasksModule extends SelfImprovementModule {
  const TasksModule();

  /// The dashboard card id.
  static const String cardId = 'tasks';

  @override
  ModuleId get id => ModuleId.tasks;

  @override
  String get title => 'Aufgaben';

  @override
  String get description => 'Aufgaben und tägliche Gewohnheiten';

  @override
  IconData get icon => Icons.task_alt_outlined;

  @override
  List<RouteBase> get routes => <RouteBase>[
    GoRoute(
      path: TaskRoutes.create,
      builder: (context, state) => const TaskFormScreen(),
    ),
    GoRoute(
      path: TaskRoutes.editPattern,
      builder: (context, state) =>
          TaskFormScreen(taskId: state.pathParameters['id']),
    ),
    GoRoute(
      path: HabitRoutes.create,
      builder: (context, state) => const HabitFormScreen(),
    ),
    GoRoute(
      path: HabitRoutes.detailPattern,
      builder: (context, state) =>
          HabitDetailScreen(habitId: state.pathParameters['id']!),
      routes: <RouteBase>[
        GoRoute(
          path: HabitRoutes.editSegment,
          builder: (context, state) =>
              HabitFormScreen(habitId: state.pathParameters['id']),
        ),
      ],
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => <DashboardCardDescriptor>[
    DashboardCardDescriptor(
      cardId: cardId,
      title: 'Aufgaben',
      defaultRank: SchemaKeys.defaultCardOrder.indexOf(cardId),
      fullWidth: true,
      builder: (context, ref) => const TasksDashboardCard(),
    ),
  ];

  @override
  List<QuickAction> get quickActions => <QuickAction>[
    QuickAction(
      id: 'task',
      label: 'Aufgabe',
      icon: AppIcon.task.data,
      route: TaskRoutes.create,
      plusOrder: 5,
    ),
    QuickAction(
      id: 'habit',
      label: 'Gewohnheit',
      icon: AppIcon.habit.data,
      route: HabitRoutes.create,
      plusOrder: 6,
    ),
  ];
}
