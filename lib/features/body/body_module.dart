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

/// The `body` module: weight (and, once built, manual steps).
///
/// The shell registers [routes] once and guards them by the module status, so
/// the screens contain no guard logic of their own.
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

  /// The order matters: `/weight/new` and `/weight/all` must come before the
  /// `:id` pattern so they are never read as measurement ids.
  @override
  List<RouteBase> get routes => <RouteBase>[
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
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => <DashboardCardDescriptor>[
    DashboardCardDescriptor(
      cardId: 'weight',
      title: 'Gewicht',
      defaultRank: 2,
      builder: (context, ref) => const WeightDashboardCard(),
    ),
  ];

  @override
  List<QuickAction> get quickActions => <QuickAction>[
    QuickAction(
      id: 'weight',
      label: 'Gewicht',
      icon: AppIcon.weight.data,
      route: WeightRoutes.create,
      plusOrder: 0,
    ),
  ];
}
