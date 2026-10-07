import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

/// WCAG contrast ratio of two opaque colours.
double _ratio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The colour pairs the task and habit screens draw text on, checked in all
/// three themes. The widget contrast guideline of the test framework samples
/// anti-aliased pixels of 12 px text and reports false findings, so the token
/// pairs are checked directly (4.5:1 for text, 3:1 for symbols and borders).
void main() {
  for (final variant in AppThemeVariant.values) {
    final c = variant.colors;

    group('contrast in the ${variant.name} theme', () {
      void text(String name, Color foreground, Color background) {
        test('$name has 4.5:1 or more', () {
          expect(_ratio(foreground, background), greaterThanOrEqualTo(4.5));
        });
      }

      void symbol(String name, Color foreground, Color background) {
        test('$name has 3:1 or more', () {
          expect(_ratio(foreground, background), greaterThanOrEqualTo(3));
        });
      }

      text('primary text on the page', c.textPrimary, c.background);
      text('primary text on a card', c.textPrimary, c.surface);
      text('secondary text on the page', c.textSecondary, c.background);
      text('secondary text on a card', c.textSecondary, c.surface);
      text('secondary text on an overdue row', c.textSecondary, c.errorTint);
      text('low priority pill', c.textSecondary, c.track);
      text('count badge of a segment', c.textSecondary, c.surfaceMuted);
      text('overdue text on a card', c.error, c.surface);
      text(
        'overdue text and high pill on the error tint',
        c.error,
        c.errorTint,
      );
      text('normal priority pill', c.warningText, c.warningTint);
      text('archive hint on a card', c.warningText, c.surface);
      text('green text on a card', c.primaryText, c.surface);
      text('green text on the page', c.primaryText, c.background);
      text(
        'green text on its tint (badge, tag, daily choice)',
        c.primaryText,
        c.primaryTint,
      );
      text('selected day of the week strip', c.onPrimary, c.primaryButton);
      text('series text on a card', c.streakText, c.surface);
      // BS-110: the rows of the Home card "Heute abhaken".
      text(
        'kind chip "Aufgabe" (green text on the green tint)',
        c.primaryText,
        c.primaryTint,
      );
      text(
        'kind chip "Gewohnheit" (habits violet on the quiet surface)',
        c.moduleHabits,
        c.surfaceMuted,
      );
      symbol(
        'kind icon of a habit (violet on the quiet surface)',
        c.moduleHabits,
        c.surfaceMuted,
      );
      symbol(
        'kind icon of a task (green on the green tint)',
        c.primaryText,
        c.primaryTint,
      );
      symbol(
        'the box of an open row (input border on a card)',
        c.borderInput,
        c.surface,
      );
      symbol(
        'the check mark of a done row (on the button green)',
        c.onPrimary,
        c.primaryButton,
      );
      text(
        'count of a finished day (green text on the page)',
        c.primaryText,
        c.background,
      );

      for (final icon in HabitIcon.values) {
        final accent = icon.accent;
        text(
          'day number on a checked ${icon.key} day',
          c.surface,
          c.accent(accent),
        );
        text(
          'day number on an open ${icon.key} day',
          c.textPrimary,
          c.accentTint(accent),
        );
        symbol(
          'the ${icon.key} symbol on its tile',
          c.accent(accent),
          c.accentTint(accent),
        );
        symbol(
          'the selection border of the ${icon.key} symbol',
          c.accent(accent),
          c.background,
        );
      }
    });
  }
}
