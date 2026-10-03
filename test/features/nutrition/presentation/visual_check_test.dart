import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:self_improvement/features/nutrition/presentation/meal_form_screen.dart';

import 'support/nutrition_ui_kit.dart';

/// Renders the nutrition screens to PNG files under the git-ignored `build/`
/// folder for the visual comparison with the Figma frames. The tests double as
/// smoke tests: every state must render without an exception.
const String _out = 'build/nutrition_ui';

Future<void> _water(NutritionUi ui) async {
  await ui.addWater(250, ago: const Duration(hours: 1, minutes: 50));
  await ui.addWater(500, ago: const Duration(hours: 1));
  await ui.addWater(250, ago: const Duration(minutes: 45));
  await ui.addWater(500, ago: const Duration(minutes: 20));
}

Future<void> _meals(NutritionUi ui) async {
  await ui.addMeal(
    'Haferflocken mit Beeren',
    kcal: 420,
    ago: const Duration(hours: 1, minutes: 50),
  );
  await ui.addMeal(
    'Linsencurry mit Reis',
    kcal: 650,
    ago: const Duration(hours: 1),
  );
  await ui.addMeal('Apfel', ago: const Duration(minutes: 20));
}

void main() {
  testWidgets('water screen with entries (4021:2)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await ui.pumpRoute('/water');
    await savePng(tester, '$_out/water_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water screen 320 px at 200 % text (4057:208)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await ui.pumpRoute('/water', size: const Size(320, 640), textScale: 2.0);
    await savePng(tester, '$_out/water_320_x2.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water screen 320 px at 100 % text (4057:208)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await ui.pumpRoute('/water', size: const Size(320, 800));
    await savePng(tester, '$_out/water_320.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water custom amount sheet (4055:25)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await ui.pumpRoute('/water');
    await tester.tap(find.text('Eigene Menge'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('um 10 Milliliter erhöhen'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('um 10 Milliliter erhöhen'));
    await tester.pump();
    await savePng(tester, '$_out/water_custom_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water custom sheet 320 px, 200 % text, keyboard', (
    tester,
  ) async {
    final ui = await NutritionUi.create(tester);
    await ui.pumpRoute(
      '/water',
      size: const Size(320, 640),
      textScale: 2.0,
      viewInsets: const EdgeInsets.only(bottom: 260),
    );
    await ui.reveal(find.text('Eigene Menge'));
    await tester.tap(find.text('Eigene Menge'));
    await tester.pumpAndSettle();
    await savePng(tester, '$_out/water_custom_320_x2_keyboard.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water goal sheet', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await ui.pumpRoute('/water');
    await tester.tap(find.text('Tagesziel'));
    await tester.pumpAndSettle();
    await savePng(tester, '$_out/water_goal_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('water edit screen', (tester) async {
    final ui = await NutritionUi.create(tester);
    final entry = await ui.addWater(
      330,
      ago: const Duration(hours: 1),
      note: 'nach dem Training',
    );
    await ui.pumpRoute('/water/${entry.id}');
    await savePng(tester, '$_out/water_edit_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('meals overview (4041:2)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _meals(ui);
    await ui.pumpRoute('/nutrition');
    await savePng(tester, '$_out/meals_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('meals overview 320 px at 200 % text', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _meals(ui);
    await ui.pumpRoute(
      '/nutrition',
      size: const Size(320, 640),
      textScale: 2.0,
    );
    await savePng(tester, '$_out/meals_320_x2.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('meals empty', (tester) async {
    final ui = await NutritionUi.create(tester);
    await ui.pumpRoute('/nutrition');
    await savePng(tester, '$_out/meals_empty_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('meal form (4041:136)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await ui.pumpRoute('/nutrition/new');
    await tester.enterText(
      find.byKey(mealNameFieldKey),
      'Linsencurry mit Reis',
    );
    await tester.enterText(find.byKey(mealKcalFieldKey), '650');
    await tester.pump();
    await savePng(tester, '$_out/meal_form_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard cards (2013:2)', (tester) async {
    final ui = await NutritionUi.create(tester);
    await _water(ui);
    await _meals(ui);
    await ui.pumpRoute('/');
    await savePng(tester, '$_out/dashboard_393.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard cards empty', (tester) async {
    final ui = await NutritionUi.create(tester);
    await ui.pumpRoute('/');
    await savePng(tester, '$_out/dashboard_empty_393.png');
    expect(tester.takeException(), isNull);
  });
}
