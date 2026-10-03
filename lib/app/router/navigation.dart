import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';

/// The path of the page on top: the last match of the router, which includes
/// pages pushed with `push` (the router's own `uri` is only the base location).
String currentPath(GoRouter router) {
  final matches = router.routerDelegate.currentConfiguration;
  return matches.isEmpty ? AppRoutes.home : matches.last.matchedLocation;
}

/// Leaves a screen: back when something is below it, otherwise to the
/// dashboard (the screen was opened directly and has no history).
void leaveOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.home);
  }
}
