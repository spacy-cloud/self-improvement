import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

/// One arc a [ProgressRing] paints: its colour and sweep angle in radians.
typedef PaintedArc = ({Color color, double sweep});

/// The arcs of the [ProgressRing] below [ring] (default: the only ring in the
/// tree) exactly as it paints them, in drawing order: first the track (a full
/// circle), then, only when the value is above 0, the arc of the value.
///
/// Reads what really reaches the canvas, so a test sees the colour the user
/// sees and not a field that only claims it.
List<PaintedArc> paintedArcs(WidgetTester tester, {Finder? ring}) {
  final box = tester.renderObject<RenderBox>(
    find.descendant(
      of: ring ?? find.byType(ProgressRing),
      matching: find.byType(CustomPaint),
    ),
  );
  final canvas = TestRecordingCanvas();
  box.paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return <PaintedArc>[
    for (final call in canvas.invocations)
      if (call.invocation.memberName == #drawArc)
        (
          // drawArc(rect, startAngle, sweepAngle, useCenter, paint). A Paint
          // keeps its colour as 8 bit channels, so the colour is rebuilt from
          // them and compares equal to the token colour it came from.
          color: Color(
            (call.invocation.positionalArguments[4] as Paint).color.toARGB32(),
          ),
          sweep: call.invocation.positionalArguments[2] as double,
        ),
  ];
}
