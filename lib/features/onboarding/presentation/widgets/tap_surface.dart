import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// A transparent [Material] with an [InkWell]: ripple, focus highlight and the
/// tap area of the onboarding cards and text buttons.
///
/// Feature-local twin of the design system's internal ink surface (which is
/// not part of the public barrel). Callers add their own `Semantics`.
class TapSurface extends StatelessWidget {
  const TapSurface({
    required this.child,
    required this.onTap,
    super.key,
    this.shape = const RoundedRectangleBorder(),
  });

  final Widget child;

  /// Tap callback; `null` disables the surface.
  final VoidCallback? onTap;

  /// Shape used for the clip, the ripple and the focus highlight.
  final ShapeBorder shape;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        focusColor: colors.focus.withValues(alpha: 0.2),
        child: child,
      ),
    );
  }
}
