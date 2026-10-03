import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

void main() {
  group('HabitIcon', () {
    test(
      'the stored icon keys are exactly book, moon, drop, check, flame, heart',
      () {
        expect(HabitIcon.values.map((i) => i.key).toList(), <String>[
          'book',
          'moon',
          'drop',
          'check',
          'flame',
          'heart',
        ]);
      },
    );

    test('the default is book', () {
      expect(HabitIcon.defaultIcon, HabitIcon.book);
    });

    test('tryParse finds every key and rejects unknown values', () {
      for (final icon in HabitIcon.values) {
        expect(HabitIcon.tryParse(icon.key), icon);
      }
      expect(HabitIcon.tryParse('Book'), isNull);
      expect(HabitIcon.tryParse(''), isNull);
      expect(HabitIcon.tryParse('star'), isNull);
      expect(HabitIcon.tryParse(null), isNull);
    });

    test(
      'every icon has a glyph and an accent role derived from the tokens',
      () {
        const expectedAccents = <HabitIcon, AppAccent>{
          HabitIcon.book: AppAccent.habits,
          HabitIcon.moon: AppAccent.focus,
          HabitIcon.drop: AppAccent.water,
          HabitIcon.check: AppAccent.primary,
          HabitIcon.flame: AppAccent.workout,
          HabitIcon.heart: AppAccent.error,
        };
        expect(expectedAccents.length, HabitIcon.values.length);
        for (final icon in HabitIcon.values) {
          expect(icon.accent, expectedAccents[icon]);
          expect(icon.icon.codePoint, isNonZero);
        }
      },
    );

    test('the glyphs are distinct', () {
      final points = HabitIcon.values.map((i) => i.icon.codePoint).toSet();
      expect(points.length, HabitIcon.values.length);
    });

    test('every accent resolves to a token colour in all variants', () {
      for (final variant in AppThemeVariant.values) {
        for (final icon in HabitIcon.values) {
          expect(variant.colors.accent(icon.accent).a, 1);
          expect(variant.colors.accentTint(icon.accent).a, 1);
        }
      }
    });
  });

  group('AppIcon', () {
    test('the logical keys of the brief exist', () {
      const required = <AppIcon>[
        AppIcon.home,
        AppIcon.analysis,
        AppIcon.habits,
        AppIcon.profile,
        AppIcon.plus,
        AppIcon.close,
        AppIcon.back,
        AppIcon.weight,
        AppIcon.steps,
        AppIcon.water,
        AppIcon.meal,
        AppIcon.workout,
        AppIcon.focus,
        AppIcon.task,
        AppIcon.habit,
        AppIcon.streak,
        AppIcon.flame,
        AppIcon.settings,
        AppIcon.delete,
        AppIcon.edit,
        AppIcon.check,
      ];
      expect(AppIcon.values, containsAll(required));
    });

    test('every key maps to a Material glyph', () {
      for (final icon in AppIcon.values) {
        expect(icon.data.fontFamily, 'MaterialIcons', reason: icon.name);
        expect(icon.data.codePoint, isNonZero);
      }
    });

    test(
      'home and profile have a filled selected glyph, others keep theirs',
      () {
        expect(AppIcons.of(AppIcon.home), Icons.home_outlined);
        expect(AppIcons.of(AppIcon.home, selected: true), Icons.home_rounded);
        expect(
          AppIcons.of(AppIcon.profile, selected: true),
          Icons.person_rounded,
        );
        expect(
          AppIcons.of(AppIcon.analysis, selected: true),
          AppIcon.analysis.data,
        );
        expect(AppIcon.habits.selectedData, AppIcon.habits.data);
      },
    );
  });
}
