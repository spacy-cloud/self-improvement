import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_spacing.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// The theme setting of the user ("Design" in the settings). Persisted by
/// [key]: `system`, `light`, `dark` or `oled`.
enum AppThemeMode {
  /// Follows the platform brightness (dark resolves to Dark, never to OLED).
  system('system'),

  /// Light theme.
  light('light'),

  /// Dark theme.
  dark('dark'),

  /// Dark theme with true black background. Only when chosen explicitly.
  oled('oled');

  const AppThemeMode(this.key);

  /// Stable persisted identifier.
  final String key;

  /// The mode for a persisted [key], or `null` when the key is unknown.
  static AppThemeMode? tryParse(String? key) {
    if (key == null) {
      return null;
    }
    for (final mode in values) {
      if (mode.key == key) {
        return mode;
      }
    }
    return null;
  }

  /// The variant that is shown for [platformBrightness].
  AppThemeVariant resolve(Brightness platformBrightness) {
    return switch (this) {
      AppThemeMode.system =>
        platformBrightness == Brightness.dark
            ? AppThemeVariant.dark
            : AppThemeVariant.light,
      AppThemeMode.light => AppThemeVariant.light,
      AppThemeMode.dark => AppThemeVariant.dark,
      AppThemeMode.oled => AppThemeVariant.oled,
    };
  }

  /// The matching [ThemeMode] for `MaterialApp` when `theme` is
  /// [AppTheme.light] and `darkTheme` is [AppTheme.dark] (or [AppTheme.oled]
  /// for [oled]).
  ThemeMode get themeMode {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark || AppThemeMode.oled => ThemeMode.dark,
    };
  }
}

/// Builds the [ThemeData] of the three variants from the design tokens.
///
/// A [ThemeData] fixes its [ThemeData.platform] when it is built. The themes
/// are therefore cached per platform and variant, and a theme always carries
/// the [defaultTargetPlatform] that is current when it is asked for. On a
/// device the platform never changes, so each variant is built once and the
/// same instance is returned every time, as before. A host test that runs a
/// variant on another platform (`TargetPlatformVariant`) gets a theme of that
/// platform, so the scroll physics and the text field gestures of the Material
/// widgets follow it too (BS-98, R1-01).
abstract final class AppTheme {
  static final Map<(TargetPlatform, AppThemeVariant), ThemeData> _themes =
      <(TargetPlatform, AppThemeVariant), ThemeData>{};

  /// Light theme.
  static ThemeData light() => forVariant(AppThemeVariant.light);

  /// Dark theme.
  static ThemeData dark() => forVariant(AppThemeVariant.dark);

  /// OLED theme (true black background).
  static ThemeData oled() => forVariant(AppThemeVariant.oled);

  /// Theme of a resolved [variant] for the current [defaultTargetPlatform].
  static ThemeData forVariant(AppThemeVariant variant) {
    final platform = defaultTargetPlatform;
    final key = (platform, variant);
    return _themes[key] ??= _build(AppTokens.forVariant(variant), platform);
  }
}

/// Theme for a user [mode] and the platform brightness: `system` follows the
/// platform (dark resolves to Dark, never to OLED); OLED only when chosen
/// explicitly.
ThemeData themeFor(AppThemeMode mode, Brightness platformBrightness) {
  return AppTheme.forVariant(mode.resolve(platformBrightness));
}

ThemeData _build(AppTokens tokens, TargetPlatform platform) {
  final c = tokens.colors;
  final brightness = tokens.variant.brightness;
  final textTheme = AppTextStyles.textTheme(c);
  const sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
  );

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primaryButton,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryTint,
    onPrimaryContainer: c.primaryText,
    secondary: c.primaryText,
    onSecondary: c.surface,
    secondaryContainer: c.primaryTint,
    onSecondaryContainer: c.primaryText,
    tertiary: c.moduleFocus,
    onTertiary: c.surface,
    tertiaryContainer: c.tintFocus,
    onTertiaryContainer: c.moduleFocus,
    error: c.error,
    onError: c.onError,
    errorContainer: c.errorTint,
    onErrorContainer: c.error,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textSecondary,
    surfaceDim: c.background,
    surfaceBright: c.surface,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface,
    surfaceContainerHighest: c.track,
    outline: c.borderInput,
    outlineVariant: c.borderDecorative,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: c.snackBarSurface,
    onInverseSurface: c.onSnackBar,
    inversePrimary: c.snackBarAction,
    surfaceTint: Colors.transparent,
  );

  OutlineInputBorder inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: AppRadii.controlBorder,
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return ThemeData(
    useMaterial3: true,
    platform: platform,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: AppTextStyles.fontFamily,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.track,
    focusColor: c.focus.withValues(alpha: 0.16),
    hoverColor: c.focus.withValues(alpha: 0.08),
    highlightColor: c.focus.withValues(alpha: 0.08),
    splashColor: c.focus.withValues(alpha: 0.12),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: IconThemeData(color: c.textPrimary, size: AppSizes.icon),
    extensions: <ThemeExtension<dynamic>>[tokens],
    appBarTheme: AppBarThemeData(
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTextStyles.titleScreen.copyWith(color: c.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardBorder,
        side: BorderSide(color: c.borderDecorative),
      ),
    ),
    dividerTheme: DividerThemeData(color: c.track, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      minTileHeight: AppSizes.listRowMinHeight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      tileColor: c.surface,
      textColor: c.textPrimary,
      iconColor: c.textSecondary,
      titleTextStyle: AppTextStyles.bodyDefault.copyWith(color: c.textPrimary),
      subtitleTextStyle: AppTextStyles.captionDefault.copyWith(
        color: c.textSecondary,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? c.toggleOn
            : c.borderInput;
      }),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(
        Colors.transparent,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      fillColor: WidgetStateProperty.resolveWith<Color>((states) {
        return states.contains(WidgetState.selected)
            ? c.primaryButton
            : c.surface;
      }),
      checkColor: WidgetStatePropertyAll<Color>(c.onPrimary),
      side: WidgetStateBorderSide.resolveWith((states) {
        return BorderSide(
          color: states.contains(WidgetState.selected)
              ? c.primaryButton
              : c.borderInput,
          width: 2,
        );
      }),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.primaryTint,
      disabledColor: c.track,
      checkmarkColor: c.primaryText,
      labelStyle: AppTextStyles.bodyDefault.copyWith(color: c.textPrimary),
      secondaryLabelStyle: AppTextStyles.bodyStrong.copyWith(
        color: c.primaryText,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: const StadiumBorder(),
      side: WidgetStateBorderSide.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? BorderSide(color: c.primaryButton, width: 1.5)
            : BorderSide(color: c.borderInput);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.snackBarSurface,
      contentTextStyle: AppTextStyles.bodyDefault.copyWith(color: c.onSnackBar),
      actionTextColor: c.snackBarAction,
      disabledActionTextColor: c.snackBarAction.withValues(alpha: 0.5),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.controlBorder),
      showCloseIcon: false,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      hintStyle: AppTextStyles.bodyDefault.copyWith(color: c.textTertiary),
      helperStyle: AppTextStyles.captionDefault.copyWith(
        color: c.textSecondary,
      ),
      errorStyle: AppTextStyles.captionStrong.copyWith(color: c.error),
      border: inputBorder(c.borderInput, 1.5),
      enabledBorder: inputBorder(c.borderInput, 1.5),
      disabledBorder: inputBorder(c.borderDecorative, 1.5),
      focusedBorder: inputBorder(c.primaryButton, 2),
      errorBorder: inputBorder(c.error, 2),
      focusedErrorBorder: inputBorder(c.error, 2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: c.scrim,
      elevation: 0,
      modalElevation: 0,
      shape: sheetShape,
      clipBehavior: Clip.antiAlias,
      dragHandleColor: c.borderInput,
      dragHandleSize: const Size(
        AppSizes.sheetHandleWidth,
        AppSizes.sheetHandleHeight,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: c.scrim,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.sheetBorder),
      titleTextStyle: AppTextStyles.titleSection.copyWith(color: c.textPrimary),
      contentTextStyle: AppTextStyles.bodyRegular.copyWith(
        color: c.textSecondary,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: c.track,
      circularTrackColor: c.track,
      linearMinHeight: AppSizes.progressBar,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.bar)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primaryButton,
      selectionColor: c.primaryButton.withValues(alpha: 0.28),
      selectionHandleColor: c.primaryButton,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primaryButton,
        foregroundColor: c.onPrimary,
        disabledBackgroundColor: c.track,
        disabledForegroundColor: c.textTertiary,
        minimumSize: const Size(64, AppSizes.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s24),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.buttonBorder,
        ),
        textStyle: AppTextStyles.labelButton,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        disabledForegroundColor: c.textTertiary,
        side: BorderSide(color: c.borderInput, width: 1.5),
        minimumSize: const Size(64, AppSizes.secondaryButtonHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.secondaryButtonBorder,
        ),
        textStyle: AppTextStyles.bodyStrong,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.primaryText,
        disabledForegroundColor: c.textTertiary,
        minimumSize: const Size(AppSizes.touchMin, AppSizes.touchMin),
        textStyle: AppTextStyles.bodyStrong,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.primaryTint,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
        return AppTextStyles.captionNav.copyWith(
          color: states.contains(WidgetState.selected)
              ? c.primaryText
              : c.textSecondary,
        );
      }),
    ),
  );
}
