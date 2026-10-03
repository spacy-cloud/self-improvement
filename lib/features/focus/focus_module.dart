import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The `focus` module. The owning feature fills routes, cards and quick actions.
final class FocusModule extends SelfImprovementModule {
  const FocusModule();

  @override
  ModuleId get id => ModuleId.focus;

  @override
  String get title => 'Fokus';

  @override
  String get description => 'Fokus-Timer und Workouts';

  @override
  IconData get icon => Icons.timer_outlined;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
