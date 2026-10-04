import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Four-segment progress of the numbered steps: the first [current] segments
/// are filled. Decorative: "Schritt N von 4" in the step header carries the
/// information for screen readers, so this widget is excluded from semantics.
class StepProgress extends StatelessWidget {
  const StepProgress({required this.current, required this.total, super.key});

  /// Number of filled segments (1 to [total]).
  final int current;

  /// Number of segments.
  final int total;

  /// Segment height and gap of the design.
  static const double _height = 6;
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    return ExcludeSemantics(
      child: Row(
        children: <Widget>[
          for (var i = 0; i < total; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: _gap),
            Expanded(
              child: AnimatedContainer(
                duration: motion.standard,
                curve: motion.curve,
                height: _height,
                decoration: BoxDecoration(
                  color: i < current ? colors.primary : colors.track,
                  borderRadius: BorderRadius.circular(_height / 2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The page dots of the welcome screen: the first dot is the long, filled one.
/// Decorative (excluded from semantics).
class PageDots extends StatelessWidget {
  const PageDots({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 6),
            Container(
              width: i == 0 ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == 0 ? colors.primary : colors.track,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
