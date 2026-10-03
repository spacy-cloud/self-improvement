import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/profile/user_profile.dart';

/// What the router needs to decide where the user may be: whether the start
/// state is known and whether onboarding is done.
@immutable
final class RouteGuardState {
  const RouteGuardState({
    required this.ready,
    required this.onboardingCompleted,
  });

  /// Not known yet (the profile has not been read).
  static const RouteGuardState starting = RouteGuardState(
    ready: false,
    onboardingCompleted: false,
  );

  /// The profile is known; [onboardingCompleted] is meaningful.
  final bool ready;
  final bool onboardingCompleted;

  /// From the profile stream: a profile that is not there yet (or missing)
  /// counts as "onboarding not completed".
  factory RouteGuardState.fromProfile(AsyncValue<UserProfile?> profile) {
    if (!profile.hasValue) {
      return starting;
    }
    return RouteGuardState(
      ready: true,
      onboardingCompleted: profile.value?.onboardingCompleted ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RouteGuardState &&
      other.ready == ready &&
      other.onboardingCompleted == onboardingCompleted;

  @override
  int get hashCode => Object.hash(ready, onboardingCompleted);
}

/// The redirect of the start flow:
///
/// - while the start state is unknown nothing is decided (the app shows its
///   neutral loading screen before the router exists, so this is a safety net);
/// - without completed onboarding every location leads to `/onboarding`;
/// - with completed onboarding `/onboarding` leads to the dashboard.
///
/// Returns `null` when the location is fine.
String? guardRedirect(RouteGuardState guard, String path) {
  if (!guard.ready) {
    return null;
  }
  final inOnboarding = AppRoutes.isOnboarding(path);
  if (!guard.onboardingCompleted) {
    return inOnboarding ? null : AppRoutes.onboarding;
  }
  return inOnboarding ? AppRoutes.home : null;
}

/// Whether a path parameter holds a record id: `id` and every name ending in
/// `Id`.
bool isIdParameter(String name) => name == 'id' || name.endsWith('Id');

/// True when any id parameter is not a canonical local id (UUID). Such a
/// location never reaches a screen: it shows the not-found screen.
bool hasMalformedId(Map<String, String> pathParameters) {
  for (final entry in pathParameters.entries) {
    if (isIdParameter(entry.key) &&
        !NotificationRoutes.isLocalId(entry.value)) {
      return true;
    }
  }
  return false;
}
