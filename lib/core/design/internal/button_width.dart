import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Gives a button the full available width when [expand] is true and the
/// parent bounds its width; otherwise the button keeps its natural width (at
/// least [minWidth]). This avoids the "infinite width" error when a button is
/// placed in a `Row`.
///
/// It is a render object and not a `LayoutBuilder` on purpose: a
/// `LayoutBuilder` throws when something asks for intrinsic sizes, and the
/// card rows of `AdaptiveGrid` do exactly that (`IntrinsicHeight`). The button
/// content centres itself, so it looks the same filled or natural.
class ButtonWidth extends SingleChildRenderObjectWidget {
  /// Creates the wrapper.
  const ButtonWidth({
    required this.expand,
    required this.minWidth,
    required Widget super.child,
    super.key,
  });

  /// Whether to fill the available width.
  final bool expand;

  /// Minimum width when the button does not fill the width.
  final double minWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderButtonWidth(expand: expand, minWidth: minWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderButtonWidth renderObject,
  ) {
    renderObject
      ..expand = expand
      ..minWidth = minWidth;
  }
}

/// Render object of [ButtonWidth].
class RenderButtonWidth extends RenderProxyBox {
  /// Creates the render object.
  RenderButtonWidth({required this._expand, required this._minWidth});

  bool _expand;
  double _minWidth;

  set expand(bool value) {
    if (value != _expand) {
      _expand = value;
      markNeedsLayout();
    }
  }

  set minWidth(double value) {
    if (value != _minWidth) {
      _minWidth = value;
      markNeedsLayout();
    }
  }

  BoxConstraints _innerConstraints(BoxConstraints constraints) {
    final fill = _expand && constraints.hasBoundedWidth;
    final wanted = fill
        ? constraints.maxWidth
        : math.min(_minWidth, constraints.maxWidth);
    return constraints.copyWith(
      minWidth: math.max(constraints.minWidth, wanted),
    );
  }

  @override
  void performLayout() {
    final box = child;
    if (box == null) {
      size = constraints.smallest;
      return;
    }
    box.layout(_innerConstraints(constraints), parentUsesSize: true);
    size = box.size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(_innerConstraints(constraints)) ??
      constraints.smallest;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => child?.getDryBaseline(_innerConstraints(constraints), baseline);

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_minWidth, super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(_minWidth, super.computeMaxIntrinsicWidth(height));
}
