import 'package:flutter/painting.dart';

/// Corner radii. The four token values come from the Figma variables
/// `radius/*`; the component values are the ones the Figma components use
/// (partly hard-coded there, see `docs/design-handoff.md` section 8).
abstract final class AppRadii {
  /// `radius/chip` (18). Figma applies it to the primary button.
  static const double chip = 18;

  /// `radius/control` (14): text fields and snack bars.
  static const double control = 14;

  /// `radius/card` (16): cards and list groups.
  static const double card = 16;

  /// `radius/sheet` (20): sheets, empty and error states.
  static const double sheet = 20;

  /// Primary button (Figma component value, equals [chip]).
  static const double button = 18;

  /// Secondary button (Figma component value 16).
  static const double secondaryButton = 16;

  /// Icon tile in list rows and menus.
  static const double tile = 12;

  /// Outer corner of the segmented control.
  static const double segmentOuter = 12;

  /// Inner corner of a segment.
  static const double segmentInner = 9;

  /// Progress bars (half of the 12 px height).
  static const double bar = 6;

  /// Fully rounded (chips, pills, circles).
  static const double pill = 999;

  /// [chip] as border radius.
  static const BorderRadius chipBorder = BorderRadius.all(
    Radius.circular(chip),
  );

  /// [control] as border radius.
  static const BorderRadius controlBorder = BorderRadius.all(
    Radius.circular(control),
  );

  /// [card] as border radius.
  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );

  /// [sheet] as border radius.
  static const BorderRadius sheetBorder = BorderRadius.all(
    Radius.circular(sheet),
  );

  /// Primary button as border radius.
  static const BorderRadius buttonBorder = BorderRadius.all(
    Radius.circular(button),
  );

  /// Secondary button as border radius.
  static const BorderRadius secondaryButtonBorder = BorderRadius.all(
    Radius.circular(secondaryButton),
  );
}
