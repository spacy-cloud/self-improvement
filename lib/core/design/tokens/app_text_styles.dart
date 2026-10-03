import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';

/// The 12 Figma text styles (groups Display, Title, Body, Label, Caption), all
/// in Inter with letter spacing 0. The styles carry no colour: colour comes
/// from the theme or from the component.
///
/// Sizes scale with the system font scale. Nothing here clamps the scale.
abstract final class AppTextStyles {
  /// Bundled font family (see `assets/fonts/README.md`).
  static const String fontFamily = 'Inter';

  /// Figma `Display/XL`: Inter Bold 48, line height 115 %.
  static const TextStyle displayXl = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: 0,
  );

  /// Figma `Display/L`: Inter Bold 34, line height 115 %.
  static const TextStyle displayL = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: 0,
  );

  /// Figma `Title/Screen`: Inter Bold 24, line height 115 %.
  static const TextStyle titleScreen = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.15,
    letterSpacing: 0,
  );

  /// Figma `Title/Section`: Inter Bold 17, line height 135 %.
  static const TextStyle titleSection = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Title/Card`: Inter SemiBold 16, line height 135 %.
  static const TextStyle titleCard = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Body/Strong`: Inter SemiBold 15, line height 135 %.
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Body/Default`: Inter Medium 15, line height 135 %.
  static const TextStyle bodyDefault = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Body/Regular`: Inter Regular 14, line height 135 %.
  static const TextStyle bodyRegular = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Label/Button`: Inter SemiBold 17, line height 135 %.
  static const TextStyle labelButton = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Caption/Default`: Inter Regular 12, line height 135 %.
  static const TextStyle captionDefault = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Caption/Strong`: Inter SemiBold 12, line height 135 %.
  static const TextStyle captionStrong = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0,
  );

  /// Figma `Caption/Nav`: Inter Medium 10, line height 135 %.
  static const TextStyle captionNav = TextStyle(
    fontFamily: fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0,
  );

  /// All styles keyed by their Figma name (used by tests and documentation).
  static const Map<String, TextStyle> byFigmaName = <String, TextStyle>{
    'Display/XL': displayXl,
    'Display/L': displayL,
    'Title/Screen': titleScreen,
    'Title/Section': titleSection,
    'Title/Card': titleCard,
    'Body/Strong': bodyStrong,
    'Body/Default': bodyDefault,
    'Body/Regular': bodyRegular,
    'Label/Button': labelButton,
    'Caption/Default': captionDefault,
    'Caption/Strong': captionStrong,
    'Caption/Nav': captionNav,
  };

  /// Material [TextTheme] built from the 12 styles.
  ///
  /// Mapping: displayLarge/headlineLarge = Display/XL and Display/L,
  /// titleLarge = Title/Screen, titleMedium = Title/Card,
  /// titleSmall = Body/Strong, bodyLarge = Body/Default,
  /// bodyMedium = Body/Regular, bodySmall = Caption/Default,
  /// labelLarge = Label/Button, labelMedium = Caption/Strong,
  /// labelSmall = Caption/Nav.
  static TextTheme textTheme(AppColors colors) {
    TextStyle c(TextStyle style) => style.copyWith(color: colors.textPrimary);
    return TextTheme(
      displayLarge: c(displayXl),
      displayMedium: c(displayL),
      displaySmall: c(titleScreen),
      headlineLarge: c(displayL),
      headlineMedium: c(titleScreen),
      headlineSmall: c(titleSection),
      titleLarge: c(titleScreen),
      titleMedium: c(titleCard),
      titleSmall: c(bodyStrong),
      bodyLarge: c(bodyDefault),
      bodyMedium: c(bodyRegular),
      bodySmall: c(captionDefault).copyWith(color: colors.textSecondary),
      labelLarge: c(labelButton),
      labelMedium: c(captionStrong),
      labelSmall: c(captionNav),
    );
  }
}
