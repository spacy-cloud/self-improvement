import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/body/presentation/weight_dashboard_card.dart';
import 'package:self_improvement/features/body/presentation/weight_form_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_history_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_overview_screen.dart';
import 'package:self_improvement/features/body/presentation/weight_routes.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_dashboard_card.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_form_screen.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_overview_screen.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_routes.dart';

/// The `body` module: weight and manual steps.
final class BodyModule extends SelfImprovementModule {
  const BodyModule();

  @override
  ModuleId get id => ModuleId.body;

  @override
  String get title => 'Gewicht & Körper';

  @override
  String get description => 'Gewicht, Zielgewicht, Schritte';

  @override
  IconData get icon => Icons.monitor_weight_outlined;

  /// Static paths come before the `:id` pattern so that `/weight/new` and
  /// `/weight/all` are never read as measurement ids.
  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: WeightRoutes.overview,
      builder: (context, state) => const WeightOverviewScreen(),
    ),
    GoRoute(
      path: WeightRoutes.create,
      builder: (context, state) => const WeightFormScreen(),
    ),
    GoRoute(
      path: WeightRoutes.all,
      builder: (context, state) => const WeightHistoryScreen(),
    ),
    GoRoute(
      path: WeightRoutes.editPattern,
      builder: (context, state) =>
          WeightFormScreen(entryId: state.pathParameters['id']),
    ),
    GoRoute(
      path: StepsRoutes.overview,
      builder: (context, state) => const StepsOverviewScreen(),
    ),
    GoRoute(
      path: StepsRoutes.create,
      builder: (context, state) =>
          StepsFormScreen(date: StepsRoutes.dateOf(state)),
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => [
    DashboardCardDescriptor(
      cardId: 'steps',
      title: 'Schritte',
      defaultRank: 0,
      builder: (context, ref) => const StepsDashboardCard(),
    ),
    DashboardCardDescriptor(
      cardId: 'weight',
      title: 'Gewicht',
      defaultRank: 2,
      builder: (context, ref) => const WeightDashboardCard(),
    ),
  ];

  @override
  List<QuickAction> get quickActions => [
    QuickAction(
      id: 'weight',
      label: 'Gewicht',
      icon: AppIcon.weight.data,
      route: WeightRoutes.create,
      plusOrder: 0,
    ),
    QuickAction(
      id: 'steps',
      label: 'Schritte',
      icon: AppIcon.steps.data,
      route: StepsRoutes.create,
      plusOrder: 3,
    ),
  ];
}
