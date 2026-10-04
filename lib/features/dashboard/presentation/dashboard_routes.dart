import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes the dashboard, the streak page and the progress page open or are
/// opened by (design handoff routes table).
abstract final class DashboardRoutes {
  /// The dashboard (Home tab).
  static const String home = '/';

  /// Daily goals editor ("Ziele festlegen").
  static const String goals = '/goals';

  /// Module management ("Module auswählen").
  static const String modules = '/settings/modules';

  /// Streak page.
  static const String streak = '/streak';

  /// Progress page (XP, level, badges).
  static const String progress = '/progress';
}

/// Leaves a page of the dashboard area: back when something lies below it,
/// otherwise (deep link, notification) to the dashboard, so the back button is
/// never a dead end.
void leaveToHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(DashboardRoutes.home);
  }
}
