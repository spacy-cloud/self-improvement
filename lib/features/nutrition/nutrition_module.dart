import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_form_screen.dart';
import 'package:self_improvement/features/nutrition/presentation/meals_screen.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_dashboard_card.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_past_day_card.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/water_dashboard_card.dart';
import 'package:self_improvement/features/nutrition/presentation/water_edit_screen.dart';
import 'package:self_improvement/features/nutrition/presentation/water_past_day_card.dart';
import 'package:self_improvement/features/nutrition/presentation/water_screen.dart';

/// The `nutrition` module: water (one shared screen, quick add, history) and
/// meals (optional calories).
///
/// Routes list the static paths before the parametric ones so `/nutrition/new`
/// is never read as a meal id. The shell registers them once and guards them
/// while the module is off.
final class NutritionModule extends SelfImprovementModule {
  const NutritionModule();

  @override
  ModuleId get id => ModuleId.nutrition;

  @override
  String get title => 'Wasser & Ernährung';

  @override
  String get description => 'Trinkmenge und Mahlzeiten';

  @override
  IconData get icon => Icons.water_drop_outlined;

  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: WaterRoutes.screen,
      builder: (context, state) => const WaterScreen(),
    ),
    GoRoute(
      path: WaterRoutes.editPattern,
      builder: (context, state) =>
          WaterEditScreen(entryId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: NutritionRoutes.overview,
      builder: (context, state) => const MealsScreen(),
    ),
    GoRoute(
      path: NutritionRoutes.create,
      builder: (context, state) => const MealFormScreen(),
    ),
    GoRoute(
      path: NutritionRoutes.editPattern,
      builder: (context, state) =>
          MealFormScreen(entryId: state.pathParameters['id']!),
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => [
    DashboardCardDescriptor(
      cardId: 'water',
      title: 'Wasser',
      defaultRank: 1,
      builder: (context, ref) => const WaterDashboardCard(),
      dayBuilder: (context, ref, day) => WaterPastDayCard(day: day),
    ),
    DashboardCardDescriptor(
      cardId: 'nutrition',
      title: 'Ernährung',
      defaultRank: 6,
      builder: (context, ref) => const NutritionDashboardCard(),
      dayBuilder: (context, ref, day) => NutritionPastDayCard(day: day),
    ),
  ];

  @override
  List<QuickAction> get quickActions => [
    QuickAction(
      id: 'water',
      label: 'Wasser',
      icon: AppIcon.water.data,
      route: WaterRoutes.screen,
      plusOrder: 2,
    ),
    QuickAction(
      id: 'meal',
      label: 'Mahlzeit',
      icon: AppIcon.meal.data,
      route: NutritionRoutes.create,
      plusOrder: 7,
    ),
  ];
}
