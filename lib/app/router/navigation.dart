import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';

/// Leaves a screen: back when something is below it, otherwise to the
/// dashboard (the screen was opened directly and has no history).
void leaveOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.home);
  }
}
