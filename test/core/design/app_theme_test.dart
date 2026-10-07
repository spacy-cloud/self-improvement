import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/design_test_harness.dart';

void main() {
  group('AppThemeMode', () {
    test('has the persisted keys system, light, dark and oled', () {
      expect(AppThemeMode.values.map((m) => m.key), <String>[
        'system',
        'light',
        'dark',
        'oled',
      ]);
    });

    test('tryParse round-trips every key', () {
      for (final mode in AppThemeMode.values) {
        expect(AppThemeMode.tryParse(mode.key), mode);
      }
    });

    test(
      'tryParse rejects unknown, empty, differently cased and null keys',
      () {
        expect(AppThemeMode.tryParse('amoled'), isNull);
        expect(AppThemeMode.tryParse(''), isNull);
        expect(AppThemeMode.tryParse('Dark'), isNull);
        expect(AppThemeMode.tryParse(' dark'), isNull);
        expect(AppThemeMode.tryParse(null), isNull);
      },
    );

    test(
      'system follows the platform brightness and never resolves to OLED',
      () {
        expect(
          AppThemeMode.system.resolve(Brightness.light),
          AppThemeVariant.light,
        );
        expect(
          AppThemeMode.system.resolve(Brightness.dark),
          AppThemeVariant.dark,
        );
      },
    );

    test('explicit modes ignore the platform brightness', () {
      for (final platform in Brightness.values) {
        expect(AppThemeMode.light.resolve(platform), AppThemeVariant.light);
        expect(AppThemeMode.dark.resolve(platform), AppThemeVariant.dark);
        expect(AppThemeMode.oled.resolve(platform), AppThemeVariant.oled);
      }
    });

    test('OLED is only reachable through the explicit mode', () {
      for (final mode in AppThemeMode.values) {
        for (final platform in Brightness.values) {
          final isOled = mode.resolve(platform) == AppThemeVariant.oled;
          expect(isOled, mode == AppThemeMode.oled);
        }
      }
    });

    test('themeMode maps for MaterialApp', () {
      expect(AppThemeMode.system.themeMode, ThemeMode.system);
      expect(AppThemeMode.light.themeMode, ThemeMode.light);
      expect(AppThemeMode.dark.themeMode, ThemeMode.dark);
      expect(AppThemeMode.oled.themeMode, ThemeMode.dark);
    });
  });

  group('themeFor', () {
    test('returns the theme of the resolved variant', () {
      expect(themeFor(AppThemeMode.system, Brightness.light), AppTheme.light());
      expect(themeFor(AppThemeMode.system, Brightness.dark), AppTheme.dark());
      expect(themeFor(AppThemeMode.dark, Brightness.light), AppTheme.dark());
      expect(themeFor(AppThemeMode.oled, Brightness.light), AppTheme.oled());
      expect(themeFor(AppThemeMode.oled, Brightness.dark), AppTheme.oled());
      expect(themeFor(AppThemeMode.light, Brightness.dark), AppTheme.light());
    });

    test('themes are built once', () {
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.oled(), AppTheme.oled()), isTrue);
    });
  });

  group('the theme carries the platform that is current (BS-112, R1-01)', () {
    /// Runs [body] as [platform], the way `TargetPlatformVariant` does.
    T asPlatform<T>(TargetPlatform platform, T Function() body) {
      final before = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        return body();
      } finally {
        debugDefaultTargetPlatformOverride = before;
      }
    }

    test('every variant has the platform it is asked for, in any order of asking (BS-112, R1-01, AT33)', () {
      // iOS first, then Android, then iOS again, then every platform: the
      // platform of the first theme that was built must not decide.
      final order = <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.iOS,
        ...TargetPlatform.values,
      ];
      for (final platform in order) {
        for (final variant in allVariants) {
          final theme = asPlatform(
            platform,
            () => AppTheme.forVariant(variant),
          );
          expect(
            theme.platform,
            platform,
            reason: '${variant.name} on ${platform.name}',
          );
        }
      }
    });

    test('light(), dark(), oled() and themeFor follow the platform too (BS-112, R1-01, AT33)', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        asPlatform(platform, () {
          expect(AppTheme.light().platform, platform);
          expect(AppTheme.dark().platform, platform);
          expect(AppTheme.oled().platform, platform);
          for (final mode in AppThemeMode.values) {
            for (final brightness in Brightness.values) {
              expect(themeFor(mode, brightness).platform, platform);
            }
          }
        });
      }
    });

    test('a platform has one theme per variant, built once; two platforms have two (BS-112, R1-01)', () {
      for (final variant in allVariants) {
        final ios = asPlatform(
          TargetPlatform.iOS,
          () => AppTheme.forVariant(variant),
        );
        final android = asPlatform(
          TargetPlatform.android,
          () => AppTheme.forVariant(variant),
        );
        expect(
          identical(
            ios,
            asPlatform(TargetPlatform.iOS, () => AppTheme.forVariant(variant)),
          ),
          isTrue,
          reason: '${variant.name}: the same iOS theme every time',
        );
        expect(
          identical(
            android,
            asPlatform(
              TargetPlatform.android,
              () => AppTheme.forVariant(variant),
            ),
          ),
          isTrue,
          reason: '${variant.name}: the same Android theme every time',
        );
        expect(identical(ios, android), isFalse, reason: variant.name);
      }
    });

    test('the themes of two platforms look the same: colours, tokens and text differ in nothing (BS-112, R1-01)', () {
      for (final variant in allVariants) {
        final ios = asPlatform(
          TargetPlatform.iOS,
          () => AppTheme.forVariant(variant),
        );
        final android = asPlatform(
          TargetPlatform.android,
          () => AppTheme.forVariant(variant),
        );
        expect(ios.colorScheme, android.colorScheme, reason: variant.name);
        expect(
          ios.extension<AppTokens>(),
          android.extension<AppTokens>(),
          reason: variant.name,
        );
        expect(
          ios.scaffoldBackgroundColor,
          android.scaffoldBackgroundColor,
          reason: variant.name,
        );
        expect(
          ios.textTheme.bodyMedium?.fontFamily,
          android.textTheme.bodyMedium?.fontFamily,
        );
        expect(
          ios.textTheme.bodyMedium?.fontSize,
          android.textTheme.bodyMedium?.fontSize,
        );
        expect(ios.useMaterial3, android.useMaterial3);
      }
    });
  });

  group('ThemeData built from the tokens', () {
    for (final variant in allVariants) {
      final theme = AppTheme.forVariant(variant);
      final colors = variant.colors;

      test(
        '${variant.name}: brightness, Material 3 and the token extension',
        () {
          expect(theme.useMaterial3, isTrue);
          expect(
            theme.brightness,
            variant == AppThemeVariant.light
                ? Brightness.light
                : Brightness.dark,
          );
          expect(theme.extension<AppTokens>(), AppTokens.forVariant(variant));
        },
      );

      test('${variant.name}: colour scheme is mapped from the tokens', () {
        final scheme = theme.colorScheme;
        expect(scheme.primary, colors.primaryButton);
        expect(scheme.onPrimary, colors.onPrimary);
        expect(scheme.surface, colors.surface);
        expect(scheme.onSurface, colors.textPrimary);
        expect(scheme.onSurfaceVariant, colors.textSecondary);
        expect(scheme.error, colors.error);
        expect(scheme.outline, colors.borderInput);
        expect(scheme.outlineVariant, colors.borderDecorative);
        expect(scheme.surfaceTint, Colors.transparent);
        expect(theme.scaffoldBackgroundColor, colors.background);
      });

      test('${variant.name}: Inter and the Figma text sizes', () {
        expect(theme.textTheme.bodyMedium?.fontFamily, 'Inter');
        expect(theme.textTheme.bodyMedium?.fontSize, 14);
        expect(theme.textTheme.titleLarge?.fontSize, 24);
        expect(theme.textTheme.bodyMedium?.color, colors.textPrimary);
      });

      test('${variant.name}: component themes follow the design', () {
        expect(theme.snackBarTheme.backgroundColor, colors.snackBarSurface);
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.dialogTheme.backgroundColor, colors.surface);
        expect(theme.bottomSheetTheme.backgroundColor, colors.surface);
        expect(theme.progressIndicatorTheme.linearTrackColor, colors.track);
        expect(theme.progressIndicatorTheme.linearMinHeight, 12);
        expect(theme.cardTheme.color, colors.surface);
        expect(theme.dividerTheme.color, colors.track);
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.inputDecorationTheme.fillColor, colors.surface);
        expect(theme.appBarTheme.backgroundColor, colors.surface);
        expect(
          theme.switchTheme.trackColor?.resolve(<WidgetState>{
            WidgetState.selected,
          }),
          colors.toggleOn,
        );
        expect(
          theme.switchTheme.trackColor?.resolve(<WidgetState>{}),
          colors.borderInput,
        );
        expect(
          theme.checkboxTheme.fillColor?.resolve(<WidgetState>{
            WidgetState.selected,
          }),
          colors.primaryButton,
        );
        expect(theme.chipTheme.selectedColor, colors.primaryTint);
      });
    }

    test('OLED has a true black background, Dark does not', () {
      expect(AppTheme.oled().scaffoldBackgroundColor, const Color(0xFF000000));
      expect(AppTheme.dark().scaffoldBackgroundColor, const Color(0xFF121212));
    });

    testWidgets('context.tokens reads the active theme', (tester) async {
      late AppTokens seen;
      await pumpDesign(
        tester,
        Builder(
          builder: (context) {
            seen = context.tokens;
            return const SizedBox();
          },
        ),
        variant: AppThemeVariant.oled,
      );
      expect(seen, AppTokens.oled);
    });

    testWidgets(
      'context.tokens falls back by brightness without the extension',
      (tester) async {
        late AppTokens light;
        late AppTokens dark;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.light),
            home: Builder(
              builder: (context) {
                light = context.tokens;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: Brightness.dark),
            home: Builder(
              builder: (context) {
                dark = context.tokens;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(light, AppTokens.light);
        expect(dark, AppTokens.dark);
      },
    );
  });
}
