import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// The `tasks` module. The owning feature fills routes, cards and quick actions.
final class TasksModule extends SelfImprovementModule {
  const TasksModule();

  @override
  ModuleId get id => ModuleId.tasks;

  @override
  String get title => 'Aufgaben & Gewohnheiten';

  @override
  String get description => 'To-dos und tägliche Habits';

  @override
  IconData get icon => Icons.checklist_rounded;

  @override
  List<RouteBase> get routes => const [];

  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];

  @override
  List<QuickAction> get quickActions => const [];
}
