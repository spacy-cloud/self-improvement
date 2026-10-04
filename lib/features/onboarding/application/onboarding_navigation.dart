import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Leaves the onboarding after the completion command committed.
typedef OnboardingExit = void Function(BuildContext context);

/// Where the flow goes once it is finished or skipped: the dashboard at `/`.
///
/// The default uses go_router. Tests (and hosts without the real router)
/// override this provider with their own callback, so the flow runs without
/// a router.
final onboardingExitProvider = Provider<OnboardingExit>(
  (ref) =>
      (BuildContext context) => GoRouter.of(context).go('/'),
);
