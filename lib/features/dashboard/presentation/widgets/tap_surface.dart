import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// A tappable surface for the few small controls of the dashboard that the
/// shared components do not cover (the streak pill, the move buttons of the
/// card configuration): a transparent `Material` with an ink ripple, a focus
/// highlight and the given [shape].
///
/// It carries no semantics: callers wrap it in `Semantics` with a German label,
/// like the design system components do, and make sure the tap area is at
/// least 48 x 48.
class TapSurface extends StatelessWidget {
  /// Creates the surface.
  const TapSurface({
    required this.child,
    required this.onTap,
    super.key,
    this.shape = const RoundedRectangleBorder(),
  });

  /// Content.
  final Widget child;

  /// Tap callback; `null` disables the surface.
  final VoidCallback? onTap;

  /// Shape used for clipping, the ripple and the focus highlight.
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
