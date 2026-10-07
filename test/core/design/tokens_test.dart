import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';

/// Figma variable collection "App Tokens", read on 2026-10-03: Light, Dark,
/// OLED. This table is deliberately independent of the Dart constants.
const Map<String, List<int>> _figmaColors = <String, List<int>>{
  'color/background': <int>[0xF7F8FA, 0x121212, 0x000000],
  'color/surface': <int>[0xFFFFFF, 0x1E1E1E, 0x101010],
  'color/surface-muted': <int>[0xF7F8FA, 0x26292E, 0x17191C],
  'color/text-primary': <int>[0x111111, 0xF5F5F5, 0xF5F5F5],
  'color/text-secondary': <int>[0x52555C, 0xB8BDC7, 0xB8BDC7],
  'color/text-tertiary': <int>[0x5F636B, 0xA9AEB7, 0xA9AEB7],
  'color/border-decorative': <int>[0xECECEC, 0x2C2F34, 0x24272B],
  'color/border-input': <int>[0x8A8F98, 0x6B7079, 0x6B7079],
  'color/track': <int>[0xECEFF3, 0x2C2F34, 0x24272B],
  'color/primary': <int>[0x20B65C, 0x2FCB6E, 0x2FCB6E],
  'color/primary-button': <int>[0x0E8540, 0x1F9D55, 0x1F9D55],
  'color/on-primary': <int>[0xFFFFFF, 0xFFFFFF, 0xFFFFFF],
  'color/primary-text': <int>[0x087B3E, 0x5FD68F, 0x5FD68F],
  'color/primary-tint': <int>[0xE9F8EF, 0x123222, 0x0C2418],
  'color/toggle-on': <int>[0x13994C, 0x2FCB6E, 0x2FCB6E],
  'color/error': <int>[0xB42318, 0xFF8A80, 0xFF8A80],
  'color/error-tint': <int>[0xFDECEC, 0x3A1414, 0x2A0E0E],
  'color/warning-text': <int>[0x92400E, 0xF5B75F, 0xF5B75F],
  'color/warning-tint': <int>[0xFFF7E6, 0x33260F, 0x241B0A],
  'color/module/weight': <int>[0x0D7F3F, 0x5FD68F, 0x5FD68F],
  'color/module/water': <int>[0x1474C4, 0x6CB8FF, 0x6CB8FF],
  'color/module/water-chart': <int>[0x2E9FF7, 0x4AAEFF, 0x4AAEFF],
  'color/module/steps': <int>[0xC21FB7, 0xE36AD9, 0xE36AD9],
  'color/module/workout': <int>[0xC2410C, 0xFF9A5C, 0xFF9A5C],
  'color/module/focus': <int>[0x4F5BD5, 0x8C95FF, 0x8C95FF],
  'color/module/habits': <int>[0x6A3FD0, 0xB49BFF, 0xB49BFF],
  'color/module/nutrition': <int>[0xB45309, 0xF5B75F, 0xF5B75F],
  'color/module/gamification': <int>[0xD97706, 0xF5B75F, 0xF5B75F],
  'color/streak': <int>[0xFF693F, 0xFF8A66, 0xFF8A66],
};

final Map<String, Color Function(AppColors)> _bindings =
    <String, Color Function(AppColors)>{
      'color/background': (c) => c.background,
      'color/surface': (c) => c.surface,
      'color/surface-muted': (c) => c.surfaceMuted,
      'color/text-primary': (c) => c.textPrimary,
      'color/text-secondary': (c) => c.textSecondary,
      'color/text-tertiary': (c) => c.textTertiary,
      'color/border-decorative': (c) => c.borderDecorative,
      'color/border-input': (c) => c.borderInput,
      'color/track': (c) => c.track,
      'color/primary': (c) => c.primary,
      'color/primary-button': (c) => c.primaryButton,
      'color/on-primary': (c) => c.onPrimary,
      'color/primary-text': (c) => c.primaryText,
      'color/primary-tint': (c) => c.primaryTint,
      'color/toggle-on': (c) => c.toggleOn,
      'color/error': (c) => c.error,
      'color/error-tint': (c) => c.errorTint,
      'color/warning-text': (c) => c.warningText,
      'color/warning-tint': (c) => c.warningTint,
      'color/module/weight': (c) => c.moduleWeight,
      'color/module/water': (c) => c.moduleWater,
      'color/module/water-chart': (c) => c.moduleWaterChart,
      'color/module/steps': (c) => c.moduleSteps,
      'color/module/workout': (c) => c.moduleWorkout,
      'color/module/focus': (c) => c.moduleFocus,
      'color/module/habits': (c) => c.moduleHabits,
      'color/module/nutrition': (c) => c.moduleNutrition,
      'color/module/gamification': (c) => c.moduleGamification,
      'color/streak': (c) => c.streak,
    };

/// The only deliberate deviations from the Figma values (contrast
/// corrections, see contrast_test.dart and docs/design-handoff.md section 8).
const Map<(String, int), int> _corrections = <(String, int), int>{
  ('color/primary-button', 1): 0x1F8655,
  ('color/primary-button', 2): 0x1F8655,
  ('color/toggle-on', 1): 0x2FA26E,
  ('color/toggle-on', 2): 0x2FA26E,
};

void main() {
  const palettes = <AppColors>[AppColors.light, AppColors.dark, AppColors.oled];
  const modeNames = <String>['Light', 'Dark', 'OLED'];

  group('colour roles equal the Figma variables', () {
    test('every Figma variable is bound to a Dart role', () {
      expect(_bindings.keys.toSet(), _figmaColors.keys.toSet());
      expect(_figmaColors.length, 29);
    });

    for (final entry in _figmaColors.entries) {
      for (var mode = 0; mode < 3; mode++) {
        test('${entry.key} in ${modeNames[mode]}', () {
          final expected = _corrections[(entry.key, mode)] ?? entry.value[mode];
          final actual = _bindings[entry.key]!(palettes[mode]);
          expect(actual, Color(0xFF000000 | expected));
        });
      }
    }

    test(
      'only primary-button and toggle-on differ from Figma (Dark, OLED)',
      () {
        final differences = <String>[];
        for (final entry in _figmaColors.entries) {
          for (var mode = 0; mode < 3; mode++) {
            final actual = _bindings[entry.key]!(palettes[mode]);
            if (actual != Color(0xFF000000 | entry.value[mode])) {
              differences.add('${entry.key}/${modeNames[mode]}');
            }
          }
        }
        expect(differences, <String>[
          'color/primary-button/Dark',
          'color/primary-button/OLED',
          'color/toggle-on/Dark',
          'color/toggle-on/OLED',
        ]);
      },
    );
  });

  group('roles that are not Figma variables', () {
    test('day ring arc is the hard-coded Figma yellow in all modes', () {
      for (final p in palettes) {
        expect(p.dayRing, const Color(0xFFE2D11E));
      }
    });

    test('day ring arc for all goals reached is color/primary (BS-121)', () {
      // Figma "Ziele-Ring – Zustände": Light 4127:316, Dark 4127:365, OLED
      // 4127:414 draw the full ring with color/primary.
      for (var mode = 0; mode < 3; mode++) {
        expect(
          palettes[mode].dayRingComplete,
          Color(0xFF000000 | _figmaColors['color/primary']![mode]),
          reason: modeNames[mode],
        );
      }
      // The values themselves, so that a changed table cannot hide a change of
      // the ring.
      expect(AppColors.light.dayRingComplete, const Color(0xFF20B65C));
      expect(AppColors.dark.dayRingComplete, const Color(0xFF2FCB6E));
      expect(AppColors.oled.dayRingComplete, const Color(0xFF2FCB6E));
    });

    test('track, partial arc and complete arc are three colours (BS-121)', () {
      for (final p in palettes) {
        expect(<Color>{p.track, p.dayRing, p.dayRingComplete}, hasLength(3));
      }
    });

    test('snack bar colours are the fixed Figma values in all modes', () {
      for (final p in palettes) {
        expect(p.snackBarSurface, const Color(0xFF1F2328));
        expect(p.snackBarErrorSurface, const Color(0xFF6B140F));
        expect(p.onSnackBar, const Color(0xFFFFFFFF));
        expect(p.snackBarAction, const Color(0xFF7DE2A8));
        expect(p.snackBarErrorAction, const Color(0xFFFFCCC7));
      }
    });

    test('Light accent tints are the values of the Figma Plus menu', () {
      const light = AppColors.light;
      expect(light.tintWater, const Color(0xFFE8F4FF));
      expect(light.tintSteps, const Color(0xFFFBEAFA));
      expect(light.tintWorkout, const Color(0xFFFFF3E8));
      expect(light.tintFocus, const Color(0xFFEEF0FD));
      expect(light.tintHabits, const Color(0xFFF3EFFD));
    });

    test('Dark and OLED accent tints are 16 percent accent over surface', () {
      for (final p in const <AppColors>[AppColors.dark, AppColors.oled]) {
        final derived = <Color, Color>{
          p.tintWater: p.moduleWater,
          p.tintSteps: p.moduleSteps,
          p.tintWorkout: p.moduleWorkout,
          p.tintFocus: p.moduleFocus,
          p.tintHabits: p.moduleHabits,
        };
        for (final entry in derived.entries) {
          final expected = Color.lerp(p.surface, entry.value, 0.16)!;
          expect((entry.key.r - expected.r).abs() * 255, lessThan(1.01));
          expect((entry.key.g - expected.g).abs() * 255, lessThan(1.01));
          expect((entry.key.b - expected.b).abs() * 255, lessThan(1.01));
        }
      }
    });

    test('scrim is black at 50 percent, shadow stronger in dark themes', () {
      expect(AppColors.light.scrim, const Color(0x80000000));
      expect(AppColors.light.shadow.a, closeTo(0.05, 0.01));
      expect(AppColors.dark.shadow.a, closeTo(0.15, 0.01));
      expect(AppColors.oled.shadow.a, closeTo(0.15, 0.01));
    });
  });

  group('accent mapping', () {
    test('every accent resolves to a colour, a fill and a tint', () {
      for (final p in palettes) {
        for (final accent in AppAccent.values) {
          expect(p.accent(accent).a, 1);
          expect(p.accentFill(accent).a, 1);
          expect(p.accentTint(accent).a, 1);
        }
      }
    });

    test('water fills use the chart colour, water icons the text colour', () {
      for (final p in palettes) {
        expect(p.accentFill(AppAccent.water), p.moduleWaterChart);
        expect(p.accent(AppAccent.water), p.moduleWater);
      }
    });

    test('gamification and streak use legible text colours in Light', () {
      const light = AppColors.light;
      expect(
        light.accent(AppAccent.gamification),
        isNot(light.moduleGamification),
      );
      expect(light.accent(AppAccent.streak), isNot(light.streak));
      expect(
        light.accentFill(AppAccent.gamification),
        light.moduleGamification,
      );
      expect(light.accentFill(AppAccent.streak), light.streak);
    });

    test('modules map to the accents of the Figma module colours', () {
      expect(AppAccent.forModule(ModuleId.body), AppAccent.weight);
      expect(AppAccent.forModule(ModuleId.nutrition), AppAccent.nutrition);
      expect(AppAccent.forModule(ModuleId.focus), AppAccent.focus);
      expect(AppAccent.forModule(ModuleId.tasks), AppAccent.habits);
      expect(
        AppAccent.forModule(ModuleId.gamification),
        AppAccent.gamification,
      );
    });
  });

  group('AppColors value semantics', () {
    test('equal palettes are equal, different ones are not', () {
      expect(AppColors.light, AppColors.light);
      expect(AppColors.light.hashCode, AppColors.light.hashCode);
      expect(AppColors.light == AppColors.dark, isFalse);
    });

    test('lerp returns the ends at t = 0 and t = 1', () {
      expect(
        AppColors.lerp(AppColors.light, AppColors.dark, 0),
        AppColors.light,
      );
      expect(
        AppColors.lerp(AppColors.light, AppColors.dark, 1),
        AppColors.dark,
      );
      final mid = AppColors.lerp(AppColors.light, AppColors.oled, 0.5);
      expect(mid.background, isNot(AppColors.light.background));
      expect(mid.background, isNot(AppColors.oled.background));
      // The complete ring colour is blended too (BS-121).
      expect(mid.dayRingComplete, isNot(AppColors.light.dayRingComplete));
      expect(mid.dayRingComplete, isNot(AppColors.oled.dayRingComplete));
    });

    test('AppTokens copyWith and lerp keep the variant of the nearer end', () {
      expect(AppTokens.light.lerp(AppTokens.dark, 0), AppTokens.light);
      expect(AppTokens.light.lerp(AppTokens.dark, 1), AppTokens.dark);
      final nearLight = AppTokens.light.lerp(AppTokens.dark, 0.2);
      expect(nearLight.variant, AppThemeVariant.light);
      expect(nearLight.colors.background, isNot(AppColors.light.background));
      expect(
        AppTokens.light.lerp(AppTokens.dark, 0.8).variant,
        AppThemeVariant.dark,
      );
      expect(AppTokens.light.lerp(null, 0.5), AppTokens.light);
      expect(
        AppTokens.light.copyWith(colors: AppColors.dark).colors,
        AppColors.dark,
      );
      expect(AppTokens.forVariant(AppThemeVariant.oled), AppTokens.oled);
      expect(AppTokens.oled.isDark, isTrue);
      expect(AppTokens.light.isDark, isFalse);
    });
  });

  group('spacing, radii and sizes', () {
    test('spacing scale is 4 8 12 16 24 32', () {
      expect(
        <double>[
          AppSpacing.s4,
          AppSpacing.s8,
          AppSpacing.s12,
          AppSpacing.s16,
          AppSpacing.s24,
          AppSpacing.s32,
        ],
        <double>[4, 8, 12, 16, 24, 32],
      );
    });

    test('radius tokens are 18 14 16 20', () {
      expect(AppRadii.chip, 18);
      expect(AppRadii.control, 14);
      expect(AppRadii.card, 16);
      expect(AppRadii.sheet, 20);
    });

    test('size tokens and measured component sizes', () {
      expect(AppSizes.touchMin, 48);
      expect(AppSizes.buttonHeight, 56);
      expect(AppSizes.secondaryButtonHeight, 52);
      expect(AppSizes.toggleWidth, 44);
      expect(AppSizes.toggleHeight, 26);
      expect(AppSizes.checkbox, 28);
      expect(AppSizes.progressBar, 12);
      expect(AppSizes.contentMaxWidth, 720);
    });
  });

  group('text styles', () {
    // Figma name: (size, weight, line height factor).
    const expected = <String, (double, FontWeight, double)>{
      'Display/XL': (48, FontWeight.w700, 1.15),
      'Display/L': (34, FontWeight.w700, 1.15),
      'Title/Screen': (24, FontWeight.w700, 1.15),
      'Title/Section': (17, FontWeight.w700, 1.35),
      'Title/Card': (16, FontWeight.w600, 1.35),
      'Body/Strong': (15, FontWeight.w600, 1.35),
      'Body/Default': (15, FontWeight.w500, 1.35),
      'Body/Regular': (14, FontWeight.w400, 1.35),
      'Label/Button': (17, FontWeight.w600, 1.35),
      'Caption/Default': (12, FontWeight.w400, 1.35),
      'Caption/Strong': (12, FontWeight.w600, 1.35),
      'Caption/Nav': (10, FontWeight.w500, 1.35),
    };

    test('there are exactly the 12 Figma styles', () {
      expect(AppTextStyles.byFigmaName.keys.toSet(), expected.keys.toSet());
    });

    for (final entry in expected.entries) {
      test('${entry.key} is Inter with the Figma size, weight and height', () {
        final style = AppTextStyles.byFigmaName[entry.key]!;
        expect(style.fontFamily, 'Inter');
        expect(style.fontSize, entry.value.$1);
        expect(style.fontWeight, entry.value.$2);
        expect(style.height, closeTo(entry.value.$3, 1e-9));
        expect(style.letterSpacing, 0);
      });
    }

    test('text styles carry no colour', () {
      for (final style in AppTextStyles.byFigmaName.values) {
        expect(style.color, isNull);
      }
    });

    test('text theme maps the styles and uses the primary text colour', () {
      final theme = AppTextStyles.textTheme(AppColors.dark);
      expect(theme.titleLarge?.fontSize, 24);
      expect(theme.bodyMedium?.fontSize, 14);
      expect(theme.labelLarge?.fontSize, 17);
      expect(theme.bodyMedium?.color, AppColors.dark.textPrimary);
      expect(theme.bodySmall?.color, AppColors.dark.textSecondary);
    });
  });

  group('shadows', () {
    test('card shadow is offset (0, 4) with blur 12', () {
      final shadow = AppShadows.card(AppColors.light.shadow).single;
      expect(shadow.offset, const Offset(0, 4));
      expect(shadow.blurRadius, 12);
    });
  });
}
