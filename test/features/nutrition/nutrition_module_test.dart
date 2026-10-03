import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/nutrition/nutrition_module.dart';

import 'presentation/support/nutrition_ui_kit.dart';

void main() {
  const module = NutritionModule();

  test('identifies itself as the nutrition module', () {
    expect(module.id, ModuleId.nutrition);
    expect(module.title, 'Wasser & Ernährung');
    expect(module.description, 'Trinkmenge und Mahlzeiten');
  });

  test('registers one shared water screen and the meal screens, static paths '
      'before parametric ones', () {
    final paths = [for (final route in module.routes) (route as GoRoute).path];
    expect(paths, [
      '/water',
      '/water/:id',
      '/nutrition',
      '/nutrition/new',
      '/nutrition/:id',
    ]);
    expect(
      paths.indexOf('/nutrition/new'),
      lessThan(paths.indexOf('/nutrition/:id')),
      reason: '/nutrition/new must never be read as a meal id',
    );
    expect(
      paths.where((p) => p.startsWith('/water')),
      hasLength(2),
      reason: 'no separate water detail page, only the record editor',
    );
  });

  test('provides the water and nutrition cards with the default ranks', () {
    final cards = module.dashboardCards;
    expect([for (final c in cards) c.cardId], ['water', 'nutrition']);
    for (final card in cards) {
      expect(SchemaKeys.dashboardCards, contains(card.cardId));
      expect(SchemaKeys.dashboardCardModule[card.cardId], 'nutrition');
      expect(
        card.defaultRank,
        SchemaKeys.defaultCardOrder.indexOf(card.cardId),
        reason: 'the rank follows the default order of the cards',
      );
      expect(card.fullWidth, isFalse, reason: 'small metric cards');
    }
    expect([for (final c in cards) c.title], ['Wasser', 'Ernährung']);
  });

  test('offers the water and meal quick actions in the fixed plus order', () {
    final actions = {for (final a in module.quickActions) a.id: a};
    expect(actions.keys, ['water', 'meal']);
    expect(actions['water']!.plusOrder, 2);
    expect(actions['water']!.route, '/water');
    expect(actions['water']!.label, 'Wasser');
    expect(actions['meal']!.plusOrder, 7);
    expect(actions['meal']!.route, '/nutrition/new');
    expect(actions['meal']!.label, 'Mahlzeit');
  });

  testWidgets('every route opens its own screen', (tester) async {
    final ui = await NutritionUi.create(tester);
    final water = await ui.addWater(250);
    final meal = await ui.addMeal('Apfel', kcal: 80);

    Future<void> expectTitle(String location, String title) async {
      final router = await ui.pumpRoute(location);
      expect(find.text(title), findsWidgets, reason: location);
      expect(router.state.uri.path, location);
    }

    await expectTitle('/water', 'Wasser eintragen');
    await expectTitle('/water/${water.id}', 'Eintrag bearbeiten');
    await expectTitle('/nutrition', 'Ernährung');
    await expectTitle('/nutrition/new', 'Mahlzeit eintragen');
    await expectTitle('/nutrition/${meal.id}', 'Mahlzeit bearbeiten');
  });
}
