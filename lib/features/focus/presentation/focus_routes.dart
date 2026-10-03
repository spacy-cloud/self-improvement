import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes of the focus screens (design handoff routes table).
///
/// The static paths are registered before the parametric `historyDetail`
/// pattern, so `/focus/history` is never read as a session id.
abstract final class FocusRoutes {
  /// Start screen: choose a category and a duration, or resume.
  static const String start = '/focus';

  /// The open session: running, paused or awaiting confirmation.
  static const String session = '/focus/session';

  /// All completed sessions.
  static const String history = '/focus/history';

  /// Detail of one completed session (note, delete).
  static const String historyDetailPattern = '/focus/history/:id';

  static String historyDetail(String id) => '/focus/history/$id';
}

/// Routes of the workout screens. `all` and `create` must be registered before
/// the `:id` pattern so that `/workouts/new` and `/workouts/all` are never read
/// as workout ids.
abstract final class WorkoutRoutes {
  static const String overview = '/workouts';
  static const String create = '/workouts/new';
  static const String all = '/workouts/all';
  static const String editPattern = '/workouts/:id';

  static String edit(String id) => '/workouts/$id';
}

/// Route a module management screen opens when the user wants to resolve an
/// open focus session before switching the module off (save or discard it
/// there).
const String focusDeactivationResolveRoute = FocusRoutes.session;

/// Leaves a screen: back when something is below it, otherwise (deep link,
/// notification) to the dashboard.
void leaveFocusScreen(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}

/// The back button of the header: lets the screen veto first (unsaved input
/// asks "Änderungen verwerfen?") and goes to the dashboard when the screen was
/// opened directly and nothing can be popped.
Future<void> backOrHome(BuildContext context) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  final handled = await navigator.maybePop();
  if (!handled) {
    router.go('/');
  }
}
