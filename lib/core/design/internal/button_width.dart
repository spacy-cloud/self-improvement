import 'package:flutter/widgets.dart';

/// Gives a button the full available width when [expand] is true and the
/// parent bounds its width; otherwise the button keeps its natural width. This
/// avoids the "infinite width" error when a button is placed in a `Row`.
///
/// [builder] receives `fill`, whether the button fills the width.
class ButtonWidth extends StatelessWidget {
  /// Creates the wrapper.
  const ButtonWidth({
    required this.expand,
    required this.minWidth,
    required this.builder,
    super.key,
  });

  /// Whether to fill the available width.
  final bool expand;

  /// Minimum width when the button does not fill the width.
  final double minWidth;

  /// Builds the button.
  final Widget Function(BuildContext context, bool fill) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fill = expand && constraints.hasBoundedWidth;
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: fill ? constraints.maxWidth : minWidth,
          ),
          child: builder(context, fill),
        );
      },
    );
  }
}
