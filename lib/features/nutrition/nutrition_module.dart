import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The `nutrition` module. The owning feature fills routes, cards and quick actions.
final class NutritionModule extends SelfImprovementModule {
  const NutritionModule();

  @override
  ModuleId get id => ModuleId.nutrition;

  @override
  String get title => 'Ernährung';

  @override
  String get description => 'Wasser und Mahlzeiten';

  @override
  IconData get icon => Icons.water_drop_outlined;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
