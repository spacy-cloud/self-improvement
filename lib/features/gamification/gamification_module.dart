import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/gamification/presentation/progress_screen.dart';
import 'package:self_improvement/features/gamification/presentation/streak_screen.dart';

/// The `gamification` module: XP, level, badges and the streak view.
///
/// The streak and progress screens belong to this module, so the shell guards
/// them by the module status (switched off: "Modul aktivieren" instead of the
/// screen). The owning feature fills the dashboard card.
final class GamificationModule extends SelfImprovementModule {
  const GamificationModule();

  /// Streak view.
  static const String streakRoute = '/streak';

  /// Progress (level, XP, badges).
  static const String progressRoute = '/progress';

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
      path: streakRoute,
      builder: (context, state) => const StreakScreen(),
    ),
    GoRoute(
      path: progressRoute,
      builder: (context, state) => const ProgressScreen(),
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
