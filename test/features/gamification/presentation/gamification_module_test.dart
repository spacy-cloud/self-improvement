import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/features/gamification/gamification_module.dart';

import '../../../support/pump_app.dart';
import '../../dashboard/support/dashboard_test_kit.dart';

void main() {
  const module = GamificationModule();

  test('is the bundled "Gamification" module without a plus menu entry', () {
    expect(module.id, ModuleId.gamification);
    expect(module.title, 'Gamification');
    expect(moduleFor(ModuleId.gamification), isA<GamificationModule>());
    expect(module.quickActions, isEmpty);
  });

  test(
    'contributes exactly the XP card, full width, last in the default order',
    () {
      final cards = module.dashboardCards;
      expect(cards, hasLength(1));
      final card = cards.single;
      expect(card.cardId, 'xp');
      expect(SchemaKeys.dashboardCards, contains(card.cardId));
      expect(SchemaKeys.dashboardCardModule[card.cardId], 'gamification');
      expect(card.fullWidth, isTrue);
      expect(card.defaultRank, SchemaKeys.defaultCardOrder.indexOf('xp'));
      expect(card.title, 'XP und Level');
    },
  );

  test('registers the streak and the progress route', () {
    final paths = [
      for (final route in module.routes)
        if (route is GoRoute) route.path,
    ];
    expect(paths, ['/streak', '/progress']);
  });

  testWidgets('the routes open the streak and the progress page (C02)', (
    tester,
  ) async {
    final harness = await createHarness(tester);
    final container = harness.createContainer();
    final router = await pumpRouterApp(
      tester,
      container: container,
      initialLocation: '/streak',
      routes: module.routes,
    );
    expect(find.text('Deine Streak'), findsOneWidget);
    router.go('/progress');
    await tester.pumpAndSettle();
    expect(find.text('Dein Fortschritt'), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
