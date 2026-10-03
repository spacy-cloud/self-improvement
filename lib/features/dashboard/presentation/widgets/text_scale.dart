import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/design/design.dart';

/// The effective system text scale, for layouts that stack their content when
/// the text is large (the same rule the design system components follow: above
/// [AppSizes.stackTextScale]).
extension DashboardTextScale on BuildContext {
  /// Effective text scale factor (also correct for non-linear scalers).
  double get fontScale => MediaQuery.textScalerOf(this).scale(14) / 14;

  /// Whether the text is large enough that two-column layouts must stack.
  bool get isLargeText => fontScale > AppSizes.stackTextScale;
}
