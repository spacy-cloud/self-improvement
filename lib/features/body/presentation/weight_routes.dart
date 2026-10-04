import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes of the weight screens (design handoff routes table).
///
/// `all` and `create` must be registered before the `:id` pattern so that
/// `/weight/new` and `/weight/all` are never read as measurement ids.
abstract final class WeightRoutes {
  static const String overview = '/weight';
  static const String create = '/weight/new';
  static const String all = '/weight/all';
  static const String editPattern = '/weight/:id';

  static String edit(String id) => '/weight/$id';
}

/// Leaves a weight screen: back when something is below it, otherwise (deep
/// link, notification) to the dashboard.
void leaveWeightScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// The back button of the header: lets the screen veto first (unsaved input
/// asks "Änderungen verwerfen?"), and goes to the dashboard when the screen
/// was opened directly and nothing can be popped.
Future<void> backOrHome(BuildContext context) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  final handled = await navigator.maybePop();
  if (!handled) {
    router.go('/');
  }
}
