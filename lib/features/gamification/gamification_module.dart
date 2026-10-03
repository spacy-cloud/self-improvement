import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The `gamification` module. The owning feature fills routes, cards and quick actions.
final class GamificationModule extends SelfImprovementModule {
  const GamificationModule();

  @override
  ModuleId get id => ModuleId.gamification;

  @override
  String get title => 'Fortschritt';

  @override
  String get description => 'XP, Level, Abzeichen und Streak';

  @override
  IconData get icon => Icons.local_fire_department_outlined;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
