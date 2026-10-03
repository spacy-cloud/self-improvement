import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes of the water screens (design handoff routes table).
///
/// There is ONE water screen for the day total, the quick add and the history;
/// `/water/:id` edits one record. The "Eigene Menge" form is a sheet on top of
/// `/water`, not a route of its own.
abstract final class WaterRoutes {
  static const String screen = '/water';
  static const String editPattern = '/water/:id';

  static String edit(String id) => '/water/$id';
}

/// Routes of the meal screens.
///
/// `create` must be registered before the `:id` pattern so that
/// `/nutrition/new` is never read as a meal id.
abstract final class NutritionRoutes {
  static const String overview = '/nutrition';
  static const String create = '/nutrition/new';
  static const String editPattern = '/nutrition/:id';

  static String edit(String id) => '/nutrition/$id';
}

/// Leaves a nutrition screen: back when something is below it, otherwise (deep
/// link, notification) to the dashboard.
void leaveNutritionScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// The back button of the header: lets the screen veto first (unsaved input
/// asks "Änderungen verwerfen?"), and goes to the dashboard when the screen
/// was opened directly and nothing can be popped.
Future<void> nutritionBackOrHome(BuildContext context) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  final handled = await navigator.maybePop();
  if (!handled) {
    router.go('/');
  }
}
