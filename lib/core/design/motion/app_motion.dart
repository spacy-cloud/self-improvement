import 'package:flutter/widgets.dart';

/// Motion constants of the design system: short transitions of 150 to 250 ms,
/// no infinite and no decorative loops. With reduced motion (system setting
/// or the app setting) every change is immediate.
abstract final class AppMotion {
  /// Small state changes (toggle knob, selection fade).
  static const Duration fast = Duration(milliseconds: 150);

  /// Default transition (progress fill, expand, rotate).
  static const Duration standard = Duration(milliseconds: 200);

  /// Largest transition (sheet content, bigger layout changes).
  static const Duration slow = Duration(milliseconds: 250);

  /// Default curve for transitions.
  static const Curve curve = Curves.easeOutCubic;

  /// Motion settings for [context]: reduced when the platform requests it
  /// (`MediaQuery.disableAnimations`) or when a [ReducedMotionScope] above
  /// [context] says so.
  static AppMotionData of(BuildContext context) {
    final explicit = ReducedMotionScope.maybeOf(context) ?? false;
    final system = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AppMotionData(reduced: explicit || system);
  }
}

/// Resolved motion settings: durations are zero when [reduced] is true.
@immutable
class AppMotionData {
  /// Creates motion data.
  const AppMotionData({required this.reduced});

  /// Whether motion is reduced (state changes are immediate).
  final bool reduced;

  /// [AppMotion.fast], or zero when reduced.
  Duration get fast => resolve(AppMotion.fast);

  /// [AppMotion.standard], or zero when reduced.
  Duration get standard => resolve(AppMotion.standard);

  /// [AppMotion.slow], or zero when reduced.
  Duration get slow => resolve(AppMotion.slow);

  /// Curve for transitions.
  Curve get curve => AppMotion.curve;

  /// [duration], or zero when reduced.
  Duration resolve(Duration duration) => reduced ? Duration.zero : duration;
}

/// Provides the app's reduced-motion setting to the widget tree.
///
/// The app shell places it above the `MaterialApp` content with the value of
/// the user setting "Reduzierte Bewegung". The system flag is honoured
/// independently, so the effective value is the logical OR of both.
class ReducedMotionScope extends InheritedWidget {
  /// Creates a scope.
  const ReducedMotionScope({
    required this.reduce,
    required super.child,
    super.key,
  });

  /// Whether the user asked the app to reduce motion.
  final bool reduce;

  /// The setting of the closest scope, or `null` without a scope.
  static bool? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ReducedMotionScope>()
        ?.reduce;
  }

  @override
  bool updateShouldNotify(ReducedMotionScope oldWidget) {
    return reduce != oldWidget.reduce;
  }
}
