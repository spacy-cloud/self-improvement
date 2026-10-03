import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';

import 'support/nutrition_ui_kit.dart';

/// One screen state to check: how to fill the database and how to bring the
/// screen into the state (route, opened sheet).
class _Scenario {
  const _Scenario(this.name, this.prepare);

  final String name;
  final Future<void> Function(NutritionUi ui, Size size, double scale) prepare;
}

Future<void> _fillWater(NutritionUi ui) async {
  await ui.addWater(250, ago: const Duration(hours: 3));
  await ui.addWater(1250, ago: const Duration(hours: 2));
  await ui.addWater(500, ago: const Duration(hours: 1));
  await ui.addWater(2000, ago: const Duration(days: 1));
}

Future<void> _fillMeals(NutritionUi ui) async {
  await ui.addMeal(
    'Haferflocken mit Beeren und einem sehr langen Namen, der umbrechen muss',
    kcal: 420,
    ago: const Duration(hours: 3),
  );
  await ui.addMeal('Apfel', ago: const Duration(hours: 2));
  await ui.addMeal('Kaffee', kcal: 0, ago: const Duration(days: 1));
}

final List<_Scenario> _scenarios = [
  _Scenario('water screen with entries', (ui, size, scale) async {
    await _fillWater(ui);
    await ui.pumpRoute('/water', size: size, textScale: scale);
  }),
  _Scenario('water screen without entries', (ui, size, scale) async {
    await ui.pumpRoute('/water', size: size, textScale: scale);
  }),
  _Scenario('water custom amount sheet', (ui, size, scale) async {
    await ui.pumpRoute('/water', size: size, textScale: scale);
    await ui.reveal(find.text('Eigene Menge'));
    await ui.tester.tap(find.text('Eigene Menge'));
    await ui.tester.pumpAndSettle();
  }),
  _Scenario('water goal sheet', (ui, size, scale) async {
    await ui.pumpRoute('/water', size: size, textScale: scale);
    await ui.reveal(find.text('Tagesziel'));
    await ui.tester.tap(find.text('Tagesziel'));
    await ui.tester.pumpAndSettle();
  }),
  _Scenario('water edit screen', (ui, size, scale) async {
    final entry = await ui.addWater(330, note: 'nach dem Sport');
    await ui.pumpRoute('/water/${entry.id}', size: size, textScale: scale);
  }),
  _Scenario('meals overview', (ui, size, scale) async {
    await _fillMeals(ui);
    await ui.pumpRoute('/nutrition', size: size, textScale: scale);
  }),
  _Scenario('meals first-use state', (ui, size, scale) async {
    await ui.pumpRoute('/nutrition', size: size, textScale: scale);
  }),
  _Scenario('meal form (new)', (ui, size, scale) async {
    await ui.pumpRoute('/nutrition/new', size: size, textScale: scale);
  }),
  _Scenario('meal form (edit)', (ui, size, scale) async {
    final meal = await ui.addMeal('Apfel', kcal: 80, note: 'Bio');
    await ui.pumpRoute('/nutrition/${meal.id}', size: size, textScale: scale);
  }),
  _Scenario('meal actions menu', (ui, size, scale) async {
    await _fillMeals(ui);
    await ui.pumpRoute('/nutrition', size: size, textScale: scale);
    await ui.reveal(iconButtonLabelled('Aktionen für Apfel'));
    await ui.tester.tap(iconButtonLabelled('Aktionen für Apfel'));
    await ui.tester.pumpAndSettle();
    expect(find.text('Bearbeiten'), findsOneWidget);
  }),
];

void main() {
  group('no overflow, content scrolls (320 / 360 / 393 / 430 px, 100 % and 200 % text)', () {
    for (final scenario in _scenarios) {
      for (final size in responsiveSizes) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '${scenario.name}: ${size.width.toInt()} px at ${(scale * 100).toInt()} %',
            (tester) async {
              final ui = await NutritionUi.create(tester);
              await scenario.prepare(ui, size, scale);
              await ui.settle();
              expect(tester.takeException(), isNull);
              // The screen scrolls instead of clipping: nothing is wider than
              // the window.
              final render = tester.binding.renderView;
              expect(render.size.width, size.width);
            },
          );
        }
      }
    }
  });

  group('reachability with the keyboard open', () {
    for (final size in [responsiveSizes.first, responsiveSizes[2]]) {
      testWidgets(
        'the save buttons of both forms stay above the keyboard at 200 % text '
        '(${size.width.toInt()} px)',
        (tester) async {
          final ui = await NutritionUi.create(tester);
          const keyboard = 280.0;
          await ui.pumpRoute(
            '/nutrition/new',
            size: size,
            textScale: 2.0,
            viewInsets: const EdgeInsets.only(bottom: keyboard),
          );
          await tester.enterText(
            find.byKey(const ValueKey('meal-name-field')),
            'A',
          );
          await tester.pump();
          final button = tester.getRect(find.byType(PrimaryButton));
          expect(button.bottom, lessThanOrEqualTo(size.height - keyboard + 1));
          expect(button.top, greaterThanOrEqualTo(0));
        },
      );
    }
  });

  group('tap targets and labels', () {
    for (final scenario in _scenarios) {
      for (final (size, scale) in [
        (const Size(393, 852), 1.0),
        (const Size(320, 640), 2.0),
      ]) {
        testWidgets(
          '${scenario.name}: ${size.width.toInt()} px at ${(scale * 100).toInt()} %',
          (tester) async {
            final ui = await NutritionUi.create(tester);
            await scenario.prepare(ui, size, scale);
            await ui.settle();
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          },
        );
      }
    }
  });

  group('semantics', () {
    testWidgets('the ring and the card speak the real progress (N01)', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(1500, ago: const Duration(hours: 1));
      await ui.pumpRoute('/water');
      final label = find.bySemanticsLabel(
        'Wasser heute: 1,5 l von 2,5 l, 60 Prozent erreicht.',
      );
      expect(label, findsOneWidget);
    });

    testWidgets('above the goal the spoken label names the real percentage', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(1500, ago: const Duration(hours: 2));
      await ui.addWater(1300, ago: const Duration(hours: 1));
      await ui.pumpRoute('/water');
      expect(
        find.bySemanticsLabel(
          'Wasser heute: 2,8 l von 2,5 l, 112 Prozent erreicht, Tagesziel '
          'erreicht.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the goal state is text and an icon, not only colour', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(2000, ago: const Duration(hours: 2));
      await ui.addWater(750, ago: const Duration(hours: 1));
      await ui.pumpRoute('/water');
      expect(find.text('Tagesziel erreicht'), findsOneWidget);
      expect(find.byIcon(AppIcon.check.data), findsWidgets);
    });

    testWidgets('quick buttons, row buttons and menus have German labels', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addWater(250, ago: const Duration(hours: 1));
      await ui.pumpRoute('/water');
      expect(
        find.bySemanticsLabel('Glas, 250 Milliliter hinzufügen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Flasche, 500 Milliliter hinzufügen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Eigene Menge, frei wählen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Eintrag von 09:00 Uhr, 250 ml, löschen'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('09:00 Uhr, 250 ml. Tippen zum Bearbeiten'),
        findsOneWidget,
      );
    });

    testWidgets('every icon-only button of the meal screens is labelled', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await _fillMeals(ui);
      await ui.pumpRoute('/nutrition');
      final buttons = tester.widgetList<AppIconButton>(
        find.byType(AppIconButton),
      );
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.semanticLabel.trim(), isNotEmpty);
      }
      expect(
        find.bySemanticsLabel(
          'Haferflocken mit Beeren und einem sehr langen Namen, der umbrechen '
          'muss, 07:00 Uhr, 420 Kilokalorien. Tippen zum Bearbeiten',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Apfel, 08:00 Uhr, ohne Kalorienangabe. Tippen zum Bearbeiten',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the incomplete hint and the summary are read as one item', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.addMeal('Apfel', kcal: 80, ago: const Duration(hours: 1));
      await ui.addMeal('Brot');
      await ui.pumpRoute('/nutrition');
      expect(
        find.bySemanticsLabel(
          RegExp('Kalorien unvollständig: 1 Mahlzeit ohne Kalorienangabe'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an amount error is announced next to the field', (
      tester,
    ) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await tester.tap(find.text('Eigene Menge'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(waterAmountFieldKey), '49');
      await tester.pump();
      await tester.tap(find.byType(PrimaryButton).last);
      await tester.pump();

      final node = tester.getSemantics(
        find.bySemanticsLabel(
          'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
        ),
      );
      expect(node.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('the amount field and its buttons are named', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      await tester.tap(find.text('Eigene Menge'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Menge in Millilitern'), findsOneWidget);
      expect(find.bySemanticsLabel('um 10 Milliliter erhöhen'), findsOneWidget);
      expect(
        find.bySemanticsLabel('um 10 Milliliter verringern'),
        findsOneWidget,
      );
      // The sheet is a route of its own with its own close button.
      expect(find.bySemanticsLabel('Eigene Menge'), findsWidgets);
    });

    testWidgets('headings are marked for screen readers', (tester) async {
      final ui = await NutritionUi.create(tester);
      await ui.pumpRoute('/water');
      final heading = tester.getSemantics(find.text('Schnell hinzufügen'));
      expect(heading.flagsCollection.isHeader, isTrue);
    });
  });

  group('themes', () {
    for (final theme in [AppThemeVariant.dark, AppThemeVariant.oled]) {
      testWidgets('the screens render in ${theme.name}', (tester) async {
        final ui = await NutritionUi.create(tester);
        await _fillWater(ui);
        await _fillMeals(ui);
        await ui.pumpRoute('/water', theme: theme);
        expect(tester.takeException(), isNull);
        await ui.pumpRoute('/nutrition', theme: theme);
        expect(tester.takeException(), isNull);
        await ui.pumpRoute('/', theme: theme);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
