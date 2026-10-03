/// Fixed sizes. `touchMin` and `buttonHeight` are the Figma variables
/// `size/touch-min` and `size/button-height`; the rest are measured from the
/// Figma components.
abstract final class AppSizes {
  /// `size/touch-min`: minimum tap target edge.
  static const double touchMin = 48;

  /// `size/button-height`: primary button height (grows with large text).
  static const double buttonHeight = 56;

  /// Secondary button height (Figma 52, grows with large text).
  static const double secondaryButtonHeight = 52;

  /// Visible circle of an icon button inside the 48 px target.
  static const double iconButtonVisual = 40;

  /// Icon inside an icon button.
  static const double iconButtonIcon = 20;

  /// Default icon size.
  static const double icon = 24;

  /// Toggle track width.
  static const double toggleWidth = 44;

  /// Toggle track height.
  static const double toggleHeight = 26;

  /// Toggle knob diameter.
  static const double toggleKnob = 22;

  /// Round checkbox diameter.
  static const double checkbox = 28;

  /// Progress bar height.
  static const double progressBar = 12;

  /// Default diameter of the day progress ring.
  static const double progressRing = 118;

  /// Stroke width of the day progress ring.
  static const double progressRingStroke = 10;

  /// Minimum height of a list row.
  static const double listRowMinHeight = 56;

  /// Icon tile in list rows.
  static const double iconTile = 36;

  /// Minimum height of a snack bar.
  static const double snackBarMinHeight = 56;

  /// Navigation pill width (shrinks on narrow screens, never below [touchMin]).
  static const double navPillWidth = 64;

  /// Navigation pill minimum height.
  static const double navPillHeight = 56;

  /// Centre plus button: halo diameter.
  static const double navPlusHalo = 68;

  /// Centre plus button: button diameter.
  static const double navPlusButton = 56;

  /// Handle of a bottom sheet.
  static const double sheetHandleWidth = 40;

  /// Handle thickness of a bottom sheet.
  static const double sheetHandleHeight = 4;

  /// Maximum content width on wide screens.
  static const double contentMaxWidth = 720;

  /// Text scale above which two-column grids stack to one column.
  static const double stackTextScale = 1.3;

  /// Upper text scale for the labels of the bottom navigation (like Material).
  static const double navLabelMaxTextScale = 1.3;
}
