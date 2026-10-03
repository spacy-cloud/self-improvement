import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG 2.2 relative luminance of an sRGB colour (alpha is ignored).
double relativeLuminance(Color color) {
  double channel(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// WCAG 2.2 contrast ratio between two opaque colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Contrast ratio rounded to two decimals (for the documented tables).
double roundedRatio(Color a, Color b) {
  return (contrastRatio(a, b) * 100).round() / 100;
}
