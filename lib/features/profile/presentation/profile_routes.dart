import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Routes the profile screens open or return to (design handoff routes table).
abstract final class ProfileRoutes {
  static const String profile = '/profile';
  static const String edit = '/profile/edit';
  static const String goals = '/goals';
  static const String streak = '/streak';
  static const String progress = '/progress';
}

/// Routes of the settings screens.
abstract final class SettingsRoutes {
  static const String settings = '/settings';
  static const String modules = '/settings/modules';
  static const String data = '/settings/data';
  static const String licenses = '/settings/licenses';
  static const String about = '/settings/about';
}

/// The back button of a header: lets the screen veto first (unsaved input asks
/// "Änderungen verwerfen?"), and goes to [fallback] when the screen was opened
/// directly and nothing can be popped (deep link, notification).
Future<void> leaveScreen(
  BuildContext context, {
  required String fallback,
}) async {
  final navigator = Navigator.of(context);
  final router = GoRouter.of(context);
  final handled = await navigator.maybePop();
  if (!handled) {
    router.go(fallback);
  }
}

/// Leaves a screen after its work is done (saved, nothing to save): pops
/// without asking and goes to [fallback] when nothing is below the screen.
void closeScreen(BuildContext context, {required String fallback}) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go(fallback);
  }
}

/// Runs [action] without awaiting it, for callbacks that cannot be async.
void fireAndForget(Future<void> Function() action) {
  unawaited(action());
}
