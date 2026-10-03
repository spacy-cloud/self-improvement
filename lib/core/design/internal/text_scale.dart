import 'package:flutter/widgets.dart';

/// Helpers for the system font scale. They only read the scale, nothing in the
/// design system clamps it globally.
extension TextScaleContext on BuildContext {
  /// Effective text scale factor (also correct for non-linear scalers).
  double get textScaleFactor {
    return MediaQuery.textScalerOf(this).scale(14) / 14;
  }
}
