import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/route_guard.dart';

/// The system back button, with the last step of the back order added.
///
/// Order: an open modal (plus menu, dialog, sheet) or a dirty form's discard
/// question first, then the pushed sub page, then a tab other than Home goes
/// to Home (done by the shell), and only from Home the system takes over and
/// leaves the app. The navigators handle everything up to there; this adds the
/// one case none of them can: a screen that has nothing below it (it was
/// reached by `go`, not `push`) goes to Home instead of closing the app.
final class AppBackButtonDispatcher extends RootBackButtonDispatcher {
  AppBackButtonDispatcher({required this._router, required this._guard});

  final GoRouter Function() _router;
  final RouteGuardState Function() _guard;

  @override
  Future<bool> didPopRoute() async {
    if (await super.didPopRoute()) {
      return true;
    }
    return handleUnhandledBack(_router(), _guard());
  }
}

/// Called when no navigator could handle the back press. Returns `true` when
/// the app navigated itself (to Home), `false` to let the system close the
/// app: from Home, and during onboarding (its first step is the start of the
/// app, so back leaves it).
bool handleUnhandledBack(GoRouter router, RouteGuardState guard) {
  if (!guard.ready || !guard.onboardingCompleted) {
    return false;
  }
  final path = router.routerDelegate.currentConfiguration.uri.path;
  if (path == AppRoutes.home) {
    return false;
  }
  router.go(AppRoutes.home);
  return true;
}
