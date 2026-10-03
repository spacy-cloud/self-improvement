import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';

/// The resolved theme variant. [AppThemeMode.system] is a user setting that
/// resolves to [light] or [dark]; [oled] is only used when chosen explicitly.
enum AppThemeVariant {
  /// Light theme.
  light,

  /// Dark theme.
  dark,

  /// Dark theme with true black background.
  oled;

  /// Colour set of this variant.
  AppColors get colors {
    return switch (this) {
      AppThemeVariant.light => AppColors.light,
      AppThemeVariant.dark => AppColors.dark,
      AppThemeVariant.oled => AppColors.oled,
    };
  }

  /// Brightness of this variant.
  Brightness get brightness {
    return this == AppThemeVariant.light ? Brightness.light : Brightness.dark;
  }
}

/// Design tokens of the active theme, provided as [ThemeData.extensions].
///
/// Read them with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// Creates tokens for [variant] with [colors].
  const AppTokens({required this.variant, required this.colors});

  /// Light tokens.
  static const AppTokens light = AppTokens(
    variant: AppThemeVariant.light,
    colors: AppColors.light,
  );

  /// Dark tokens.
  static const AppTokens dark = AppTokens(
    variant: AppThemeVariant.dark,
    colors: AppColors.dark,
  );

  /// OLED tokens.
  static const AppTokens oled = AppTokens(
    variant: AppThemeVariant.oled,
    colors: AppColors.oled,
  );

  /// The tokens that belong to [variant].
  static AppTokens forVariant(AppThemeVariant variant) {
    return switch (variant) {
      AppThemeVariant.light => light,
      AppThemeVariant.dark => dark,
      AppThemeVariant.oled => oled,
    };
  }

  /// Which variant these tokens describe.
  final AppThemeVariant variant;

  /// Colour roles.
  final AppColors colors;

  /// Whether the variant is a dark one (Dark or OLED).
  bool get isDark => variant != AppThemeVariant.light;

  @override
  AppTokens copyWith({AppThemeVariant? variant, AppColors? colors}) {
    return AppTokens(
      variant: variant ?? this.variant,
      colors: colors ?? this.colors,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) {
      return this;
    }
    return AppTokens(
      variant: t < 0.5 ? variant : other.variant,
      colors: AppColors.lerp(colors, other.colors, t),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppTokens &&
        other.variant == variant &&
        other.colors == colors;
  }

  @override
  int get hashCode => Object.hash(variant, colors);
}

/// Access to the design tokens from any widget.
extension AppTokensContext on BuildContext {
  /// Tokens of the active theme. Falls back to the Light or Dark tokens (by
  /// theme brightness) when the theme was not built with [AppTokens].
  AppTokens get tokens {
    final theme = Theme.of(this);
    final tokens = theme.extension<AppTokens>();
    if (tokens != null) {
      return tokens;
    }
    return theme.brightness == Brightness.dark
        ? AppTokens.dark
        : AppTokens.light;
  }
}
