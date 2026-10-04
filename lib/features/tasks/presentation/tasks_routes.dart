import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes of the task screens (design handoff routes table).
///
/// `create` must be registered before the `:id` pattern so that `/tasks/new`
/// is never read as a task id. The task list itself is the "Aufgaben" tab of
/// the habits screen, owned by the app shell (`/habits?tab=tasks`).
abstract final class TaskRoutes {
  static const String create = '/tasks/new';
  static const String editPattern = '/tasks/:id';

  /// The "Aufgaben" tab of the habits screen.
  static const String list = '/habits?tab=tasks';

  static String edit(String id) => '/tasks/$id';
}

/// Routes of the habit screens. `/habits` itself (the tab) belongs to the
/// shell; `create` is registered before the `:id` pattern.
abstract final class HabitRoutes {
  static const String tab = '/habits';
  static const String create = '/habits/new';
  static const String detailPattern = '/habits/:id';

  /// Path segment of the edit form below a habit detail.
  static const String editSegment = 'edit';

  static String detail(String id) => '/habits/$id';

  static String edit(String id) => '/habits/$id/edit';
}

/// The back button of a header: lets the screen veto first (unsaved input asks
/// "Änderungen verwerfen?") and goes to the dashboard when the screen was
/// opened directly and nothing can be popped.
Future<void> backOrHome(BuildContext context) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  final handled = await navigator.maybePop();
  if (!handled) {
    router.go('/');
  }
}

/// Leaves a screen after a successful action: back when something is below it,
/// otherwise (deep link, notification) to [fallback].
void leaveTo(BuildContext context, {String fallback = '/'}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}
