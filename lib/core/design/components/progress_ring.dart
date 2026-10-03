import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/text_scale.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Data-driven progress ring (the day ring and the water ring).
///
/// The ring starts at the top and runs clockwise. [value] is clamped to 0..1.
/// The ring is a picture: it always has a text alternative ([semanticLabel])
/// and the centre usually shows the same value as text. On large text the ring
/// grows (up to 1.6 times) and the centre content scales down to fit.
class ProgressRing extends StatelessWidget {
  /// Creates a ring for a fraction [value] from 0 to 1.
  const ProgressRing({
    required this.value,
    required this.semanticLabel,
    super.key,
    this.center,
    this.size = AppSizes.progressRing,
    this.strokeWidth = AppSizes.progressRingStroke,
    this.color,
    this.trackColor,
  });

  /// Creates the day ring from the number of [fulfilled] of [applicable]
  /// goals. Without applicable goals the ring stays empty.
  ProgressRing.goals({
    required int fulfilled,
    required int applicable,
    Widget? center,
    String? semanticLabel,
    double size = AppSizes.progressRing,
    double strokeWidth = AppSizes.progressRingStroke,
    Color? color,
    Color? trackColor,
    Key? key,
  }) : this(
         key: key,
         value: fraction(fulfilled, applicable),
         semanticLabel:
             semanticLabel ??
             (applicable <= 0
                 ? 'Heute sind keine Ziele aktiv'
                 : '$fulfilled von $applicable Zielen erreicht'),
         center: center,
         size: size,
         strokeWidth: strokeWidth,
         color: color,
         trackColor: trackColor,
       );

  /// Progress from 0 to 1.
  final double value;

  /// Spoken text, for example "3 von 4 Zielen erreicht".
  final String semanticLabel;

  /// Content in the middle of the ring (visual only).
  final Widget? center;

  /// Outer diameter at normal text size.
  final double size;

  /// Stroke width.
  final double strokeWidth;

  /// Arc colour; defaults to the day ring colour of the tokens.
  final Color? color;

  /// Track colour; defaults to the track token.
  final Color? trackColor;

  /// `fulfilled / applicable` clamped to 0..1; 0 when nothing is applicable.
  static double fraction(int fulfilled, int applicable) {
    if (applicable <= 0 || fulfilled <= 0) {
      return 0;
    }
    return math.min(1, fulfilled / applicable);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final scale = context.textScaleFactor.clamp(1.0, 1.6);
    final diameter = size * scale;
    final fraction = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      container: true,
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: diameter,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: fraction),
          duration: motion.slow,
          curve: motion.curve,
          builder: (context, animated, _) {
            return CustomPaint(
              painter: _RingPainter(
                value: animated,
                color: color ?? colors.dayRing,
                trackColor: trackColor ?? colors.track,
                strokeWidth: strokeWidth,
              ),
              child: center == null
                  ? null
                  : Center(
                      child: Padding(
                        padding: EdgeInsets.all(strokeWidth + 4),
                        child: FittedBox(fit: BoxFit.scaleDown, child: center),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, track);
    if (value <= 0) {
      return;
    }
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeWidth;
    canvas.drawArc(arcRect, -math.pi / 2, 2 * math.pi * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.value != value ||
        old.color != color ||
        old.trackColor != trackColor ||
        old.strokeWidth != strokeWidth;
  }
}
