import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The `body` module. The owning feature fills routes, cards and quick actions.
final class BodyModule extends SelfImprovementModule {
  const BodyModule();

  @override
  ModuleId get id => ModuleId.body;

  @override
  String get title => 'Körper';

  @override
  String get description => 'Gewicht und manuelle Schritte';

  @override
  IconData get icon => Icons.monitor_weight_outlined;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
