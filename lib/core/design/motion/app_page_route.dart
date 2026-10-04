import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';

/// A page route that follows the app's motion setting: the platform's Material
/// transition, or no transition when motion is reduced (the system flag or the
/// app setting "Reduzierte Bewegung", see [AppMotion.of]).
///
/// For pages that are pushed imperatively with `Navigator.push`; routes of the
/// router get the same behaviour from the app's page builder.
Route<T> appPageRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  RouteSettings? settings,
}) {
  if (AppMotion.of(context).reduced) {
    return PageRouteBuilder<T>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    );
  }
  return MaterialPageRoute<T>(settings: settings, builder: builder);
}
