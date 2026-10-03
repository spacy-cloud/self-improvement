import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// A [Material] surface with an [InkWell]: the base of every tappable widget
/// of the design system. Without [onTap] it neither reacts nor takes focus.
///
/// Internal helper: callers add their own `Semantics`.
class InkSurface extends StatelessWidget {
  /// Creates an ink surface.
  const InkSurface({
    required this.child,
    super.key,
    this.onTap,
    this.color,
    this.shape = const RoundedRectangleBorder(),
    this.autofocus = false,
    this.focusNode,
    this.splashColor,
    this.highlightColor,
  });

  /// Content.
  final Widget child;

  /// Tap callback; `null` disables the surface.
  final VoidCallback? onTap;

  /// Fill colour; transparent by default.
  final Color? color;

  /// Shape used for clipping, the ripple and the focus highlight.
  final ShapeBorder shape;

  /// Whether the surface takes the initial focus.
  final bool autofocus;

  /// Optional focus node.
  final FocusNode? focusNode;

  /// Ripple colour override.
  final Color? splashColor;

  /// Pressed highlight override.
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Material(
      color: color ?? Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: shape,
        autofocus: autofocus,
        focusNode: focusNode,
        focusColor: colors.focus.withValues(alpha: 0.2),
        splashColor: splashColor,
        highlightColor: highlightColor,
        child: child,
      ),
    );
  }
}
