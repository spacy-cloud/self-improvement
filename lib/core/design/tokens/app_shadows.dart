import 'package:flutter/painting.dart';

/// Shadows of the design system (Figma effects, read 2026-10-03).
abstract final class AppShadows {
  /// Card shadow: offset (0, 4), blur 12. Pass `AppColors.shadow`.
  static List<BoxShadow> card(Color color) => <BoxShadow>[
    BoxShadow(color: color, offset: const Offset(0, 4), blurRadius: 12),
  ];

  /// Shadow of a floating sheet (Figma Plus sheet: offset (0, 8), blur 30,
  /// black at 18 %).
  static const List<BoxShadow> sheet = <BoxShadow>[
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 8), blurRadius: 30),
  ];

  /// Soft inner highlight of the selected segment (offset (0, 1), blur 3).
  static const List<BoxShadow> segment = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 3),
  ];
}
