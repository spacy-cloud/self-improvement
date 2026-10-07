import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/contrast.dart';

typedef _Pair = ({
  String name,
  Color Function(AppColors) foreground,
  Color Function(AppColors) background,
});

/// A Figma value that failed its contrast requirement and was corrected.
class _Correction {
  const _Correction({
    required this.token,
    required this.pair,
    required this.against,
    required this.intended,
    required this.corrected,
    required this.intendedRatio,
    required this.correctedRatio,
    required this.minimum,
    required this.read,
  });

  final String token;
  final String pair;

  /// The colour the corrected value is measured against (white text or knob).
  final Color against;
  final Color intended;
  final Color corrected;
  final double intendedRatio;
  final double correctedRatio;
  final double minimum;

  /// Reads the corrected role from a colour set.
  final Color Function(AppColors) read;
}

/// Soll-Ist table of contrast corrections (Dark and OLED). Keep in sync with
/// docs/design-handoff.md section 8.
final List<_Correction> _corrections = <_Correction>[
  _Correction(
    token: 'color/primary-button',
    pair: 'color/on-primary (#FFFFFF) on color/primary-button',
    against: const Color(0xFFFFFFFF),
    intended: const Color(0xFF1F9D55),
    corrected: const Color(0xFF1F8655),
    intendedRatio: 3.49,
    correctedRatio: 4.57,
    minimum: 4.5,
    read: (c) => c.primaryButton,
  ),
  _Correction(
    token: 'color/toggle-on',
    pair: 'white toggle knob on color/toggle-on',
    against: const Color(0xFFFFFFFF),
    intended: const Color(0xFF2FCB6E),
    corrected: const Color(0xFF2FA26E),
    intendedRatio: 2.12,
    correctedRatio: 3.22,
    minimum: 3,
    read: (c) => c.toggleOn,
  ),
];

_Pair _p(
  String name,
  Color Function(AppColors) foreground,
  Color Function(AppColors) background,
) => (name: name, foreground: foreground, background: background);

/// Text pairs: normal text needs 4.5:1.
final List<_Pair> _textPairs = <_Pair>[
  _p(
    'on-primary on primary-button',
    (c) => c.onPrimary,
    (c) => c.primaryButton,
  ),
  _p('text-primary on background', (c) => c.textPrimary, (c) => c.background),
  _p('text-primary on surface', (c) => c.textPrimary, (c) => c.surface),
  _p('text-primary on track', (c) => c.textPrimary, (c) => c.track),
  _p(
    'text-primary on primary-tint',
    (c) => c.textPrimary,
    (c) => c.primaryTint,
  ),
  _p(
    'text-secondary on background',
    (c) => c.textSecondary,
    (c) => c.background,
  ),
  _p('text-secondary on surface', (c) => c.textSecondary, (c) => c.surface),
  _p(
    'text-secondary on surface-muted',
    (c) => c.textSecondary,
    (c) => c.surfaceMuted,
  ),
  _p('text-secondary on track', (c) => c.textSecondary, (c) => c.track),
  _p(
    'text-secondary on primary-tint',
    (c) => c.textSecondary,
    (c) => c.primaryTint,
  ),
  _p('text-tertiary on background', (c) => c.textTertiary, (c) => c.background),
  _p('text-tertiary on surface', (c) => c.textTertiary, (c) => c.surface),
  _p(
    'text-tertiary on track (disabled button)',
    (c) => c.textTertiary,
    (c) => c.track,
  ),
  _p('primary-text on background', (c) => c.primaryText, (c) => c.background),
  _p('primary-text on surface', (c) => c.primaryText, (c) => c.surface),
  _p(
    'primary-text on primary-tint',
    (c) => c.primaryText,
    (c) => c.primaryTint,
  ),
  _p('error on background', (c) => c.error, (c) => c.background),
  _p('error on surface', (c) => c.error, (c) => c.surface),
  _p('error on error-tint', (c) => c.error, (c) => c.errorTint),
  _p('on-error on error', (c) => c.onError, (c) => c.error),
  _p('warning-text on surface', (c) => c.warningText, (c) => c.surface),
  _p(
    'warning-text on warning-tint',
    (c) => c.warningText,
    (c) => c.warningTint,
  ),
  _p(
    'snack bar text on snack bar',
    (c) => c.onSnackBar,
    (c) => c.snackBarSurface,
  ),
  _p(
    'snack bar action on snack bar',
    (c) => c.snackBarAction,
    (c) => c.snackBarSurface,
  ),
  _p(
    'snack bar text on error snack bar',
    (c) => c.onSnackBar,
    (c) => c.snackBarErrorSurface,
  ),
  _p(
    'snack bar action on error snack bar',
    (c) => c.snackBarErrorAction,
    (c) => c.snackBarErrorSurface,
  ),
];

/// Control boundaries and graphics: 3:1.
final List<_Pair> _controlPairs = <_Pair>[
  _p('border-input vs surface', (c) => c.borderInput, (c) => c.surface),
  _p('border-input vs background', (c) => c.borderInput, (c) => c.background),
  _p('primary-button vs surface', (c) => c.primaryButton, (c) => c.surface),
  _p(
    'primary-button vs background',
    (c) => c.primaryButton,
    (c) => c.background,
  ),
  _p(
    'primary-button vs primary-tint (chip border)',
    (c) => c.primaryButton,
    (c) => c.primaryTint,
  ),
  _p('toggle-on vs surface', (c) => c.toggleOn, (c) => c.surface),
  _p('toggle-on vs background', (c) => c.toggleOn, (c) => c.background),
  _p('white knob on toggle-on', (c) => Colors.white, (c) => c.toggleOn),
  _p(
    'white knob on border-input (off)',
    (c) => Colors.white,
    (c) => c.borderInput,
  ),
  _p('error border vs surface', (c) => c.error, (c) => c.surface),
  _p('focus indicator vs surface', (c) => c.focus, (c) => c.surface),
  _p('focus indicator vs background', (c) => c.focus, (c) => c.background),
  _p(
    'day ring arc vs track (Dark and OLED only)',
    (c) => c.dayRing,
    (c) => c.track,
  ),
  _p(
    'day ring complete arc vs surface (Dark and OLED only)',
    (c) => c.dayRingComplete,
    (c) => c.surface,
  ),
  _p(
    'day ring complete arc vs track (Dark and OLED only)',
    (c) => c.dayRingComplete,
    (c) => c.track,
  ),
];

/// Pairs that are known to be below 3:1. They are decorative or always paired
/// with a text alternative. The measured value is pinned so that the
/// documentation (Soll-Ist) cannot drift away from the code.
const Map<String, double> _documentedLowContrast = <String, double>{
  'light primary (accent fill) vs surface': 2.66,
  'light primary (accent fill) vs track': 2.30,
  'light water-chart vs track': 2.45,
  'light streak (flame) vs surface': 2.86,
  'light day ring arc vs track': 1.36,
  'light day ring complete arc vs surface': 2.66,
  'light day ring complete arc vs track': 2.30,
  'light on-primary on primary (accent fill)': 2.66,
  'dark on-primary on primary (accent fill)': 2.12,
};

void main() {
  const variants = AppThemeVariant.values;

  group('WCAG helper', () {
    test('black on white is 21:1 and a colour on itself is 1:1', () {
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 1e-9));
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 1e-9));
      expect(
        contrastRatio(const Color(0xFF123456), const Color(0xFF123456)),
        1,
      );
    });

    test('mid grey #767676 on white is the known 4.54:1 boundary', () {
      expect(roundedRatio(const Color(0xFF767676), Colors.white), 4.54);
    });
  });

  group('text contrast is at least 4.5:1', () {
    for (final variant in variants) {
      for (final pair in _textPairs) {
        test('${variant.name}: ${pair.name}', () {
          final colors = variant.colors;
          final ratio = contrastRatio(
            pair.foreground(colors),
            pair.background(colors),
          );
          expect(ratio, greaterThanOrEqualTo(4.5), reason: pair.name);
        });
      }
    }

    for (final variant in variants) {
      for (final accent in AppAccent.values) {
        test(
          '${variant.name}: accent ${accent.name} text on surface and page',
          () {
            final colors = variant.colors;
            expect(
              contrastRatio(colors.accent(accent), colors.surface),
              greaterThanOrEqualTo(4.5),
            );
            expect(
              contrastRatio(colors.accent(accent), colors.background),
              greaterThanOrEqualTo(4.5),
            );
          },
        );

        test(
          '${variant.name}: accent ${accent.name} icon on its tint is at least 3:1',
          () {
            final colors = variant.colors;
            expect(
              contrastRatio(colors.accent(accent), colors.accentTint(accent)),
              greaterThanOrEqualTo(3),
            );
          },
        );
      }
    }
  });

  group('control boundaries and graphics are at least 3:1', () {
    for (final variant in variants) {
      for (final pair in _controlPairs) {
        if (pair.name.contains('Dark and OLED only') &&
            variant == AppThemeVariant.light) {
          continue;
        }
        test('${variant.name}: ${pair.name}', () {
          final colors = variant.colors;
          final ratio = contrastRatio(
            pair.foreground(colors),
            pair.background(colors),
          );
          expect(ratio, greaterThanOrEqualTo(3), reason: pair.name);
        });
      }
    }
  });

  group('documented exemptions stay as documented', () {
    test('pairs below 3:1 are exactly the documented decorative ones', () {
      const light = AppColors.light;
      const dark = AppColors.dark;
      final measured = <String, double>{
        'light primary (accent fill) vs surface': roundedRatio(
          light.primary,
          light.surface,
        ),
        'light primary (accent fill) vs track': roundedRatio(
          light.primary,
          light.track,
        ),
        'light water-chart vs track': roundedRatio(
          light.moduleWaterChart,
          light.track,
        ),
        'light streak (flame) vs surface': roundedRatio(
          light.streak,
          light.surface,
        ),
        'light day ring arc vs track': roundedRatio(light.dayRing, light.track),
        'light day ring complete arc vs surface': roundedRatio(
          light.dayRingComplete,
          light.surface,
        ),
        'light day ring complete arc vs track': roundedRatio(
          light.dayRingComplete,
          light.track,
        ),
        'light on-primary on primary (accent fill)': roundedRatio(
          light.onPrimary,
          light.primary,
        ),
        'dark on-primary on primary (accent fill)': roundedRatio(
          dark.onPrimary,
          dark.primary,
        ),
      };
      expect(measured, _documentedLowContrast);
    });

    test(
      'text never sits on the accent fill: button text uses primary-button',
      () {
        for (final variant in variants) {
          final colors = variant.colors;
          expect(colors.primaryButton, isNot(colors.primary));
          expect(
            contrastRatio(colors.onPrimary, colors.primaryButton),
            greaterThanOrEqualTo(4.5),
          );
        }
      },
    );
  });

  group('day ring complete: chosen colour and its alternative (BS-121)', () {
    // The full ring is drawn with color/primary (Figma "Ziele-Ring – Zustände").
    // The alternative color/primary-button was measured as well and not chosen
    // (D-026). Both against the card surface and the track; the full ring hides
    // the track, so the pair against the surface is the one that is seen.
    // Order: chosen vs surface, chosen vs track, alternative vs surface,
    // alternative vs track. Keep in sync with docs/design-handoff.md section
    // 8.4.
    const expected = <AppThemeVariant, (double, double, double, double)>{
      AppThemeVariant.light: (2.66, 2.30, 4.72, 4.09),
      AppThemeVariant.dark: (7.85, 6.33, 3.65, 2.94),
      AppThemeVariant.oled: (8.96, 7.06, 4.17, 3.29),
    };

    for (final variant in variants) {
      test('${variant.name}: the measured values are the documented ones', () {
        final colors = variant.colors;
        final (chosenSurface, chosenTrack, altSurface, altTrack) =
            expected[variant]!;
        expect(
          roundedRatio(colors.dayRingComplete, colors.surface),
          chosenSurface,
        );
        expect(roundedRatio(colors.dayRingComplete, colors.track), chosenTrack);
        expect(roundedRatio(colors.primaryButton, colors.surface), altSurface);
        expect(roundedRatio(colors.primaryButton, colors.track), altTrack);
      });
    }

    test('the chosen colour is the accent fill, so its Light pair is the '
        'already documented decorative one', () {
      const light = AppColors.light;
      expect(light.dayRingComplete, light.primary);
      expect(
        roundedRatio(light.dayRingComplete, light.surface),
        _documentedLowContrast['light primary (accent fill) vs surface'],
      );
      expect(
        roundedRatio(light.dayRingComplete, light.track),
        _documentedLowContrast['light primary (accent fill) vs track'],
      );
    });
  });

  group('corrections (Soll-Ist)', () {
    const corrected = <AppThemeVariant>[
      AppThemeVariant.dark,
      AppThemeVariant.oled,
    ];
    for (final correction in _corrections) {
      for (final variant in corrected) {
        test('${correction.token} in ${variant.name}', () {
          // The Figma value fails, the corrected value passes.
          expect(
            roundedRatio(correction.against, correction.intended),
            correction.intendedRatio,
            reason: correction.pair,
          );
          expect(correction.intendedRatio, lessThan(correction.minimum));
          expect(
            roundedRatio(correction.against, correction.corrected),
            correction.correctedRatio,
          );
          expect(
            correction.correctedRatio,
            greaterThanOrEqualTo(correction.minimum),
          );
          // The implementation uses the corrected value, only in Dark and OLED.
          expect(correction.read(variant.colors), correction.corrected);
          expect(correction.read(variant.colors), isNot(correction.intended));
        });
      }

      test('${correction.token} needed no correction in Light', () {
        expect(
          contrastRatio(correction.against, correction.read(AppColors.light)),
          greaterThanOrEqualTo(correction.minimum),
        );
      });

      test(
        '${correction.token}: the corrected value changed only one channel',
        () {
          final a = correction.intended;
          final b = correction.corrected;
          final changed = <bool>[a.r != b.r, a.g != b.g, a.b != b.b];
          expect(changed.where((c) => c).length, 1);
          expect(a.g != b.g, isTrue);
        },
      );
    }
  });
}
