import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/gamification/presentation/progress_screen.dart';
import 'package:self_improvement/features/gamification/presentation/streak_screen.dart';
import 'package:self_improvement/features/gamification/presentation/widgets/xp_dashboard_card.dart';

/// The `gamification` module ("Fortschritt"): the streak page, the progress
/// page and the XP and level card of the dashboard. There is no plus menu
/// entry: XP are earned by the activities of the other modules.
///
/// Switching the module off hides these screens and the XP displays only; the
/// day ring, the streak calculation and the earned XP keep working.
final class GamificationModule extends SelfImprovementModule {
  const GamificationModule();

  /// Card id of the XP and level card (one of the stored dashboard cards).
  static const String xpCardId = 'xp';

  @override
  ModuleId get id => ModuleId.gamification;

  @override
  String get title => 'Gamification';

  @override
  String get description => 'XP, Level und Badges';

  @override
  IconData get icon => Icons.star_border_rounded;

  @override
  List<RouteBase> get routes => <RouteBase>[
    GoRoute(
      path: DashboardRoutes.streak,
      builder: (context, state) => const StreakScreen(),
    ),
    GoRoute(
      path: DashboardRoutes.progress,
      builder: (context, state) => const ProgressScreen(),
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => <DashboardCardDescriptor>[
    DashboardCardDescriptor(
      cardId: xpCardId,
      title: 'XP und Level',
      defaultRank: 7,
      fullWidth: true,
      builder: (context, ref) => const XpDashboardCard(),
    ),
  ];

  @override
  List<QuickAction> get quickActions => const <QuickAction>[];
}
