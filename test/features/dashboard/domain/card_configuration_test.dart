import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/dashboard/domain/card_configuration.dart';

import '../support/dashboard_test_kit.dart';

void main() {
  final modules = testModules(TapLog());

  List<DashboardCardConfig> stored({Set<String> hidden = const <String>{}}) => [
    for (var i = 0; i < SchemaKeys.defaultCardOrder.length; i++)
      DashboardCardConfig(
        cardId: SchemaKeys.defaultCardOrder[i],
        module: ModuleId.tryParse(
          SchemaKeys.dashboardCardModule[SchemaKeys.defaultCardOrder[i]]!,
        )!,
        visible: !hidden.contains(SchemaKeys.defaultCardOrder[i]),
        sortIndex: i,
      ),
  ];

  Map<ModuleId, bool> on({Set<ModuleId> off = const <ModuleId>{}}) => {
    for (final module in ModuleId.values) module: !off.contains(module),
  };

  List<String> ids(List<ConfigurableCard> cards) => [
    for (final card in cards) card.cardId,
  ];

  group('configurableDashboardCards', () {
    test('lists the cards of all active modules in stored order (C04)', () {
      final cards = configurableDashboardCards(
        configs: stored(),
        moduleStatuses: on(),
        modules: modules,
      );
      expect(ids(cards), SchemaKeys.defaultCardOrder);
    });

    test('keeps hidden cards in the list so they can be shown again', () {
      final cards = configurableDashboardCards(
        configs: stored(hidden: {'water', 'xp'}),
        moduleStatuses: on(),
        modules: modules,
      );
      expect(ids(cards), SchemaKeys.defaultCardOrder);
      expect({
        for (final card in cards) card.cardId: card.visible,
      }, containsPair('water', false));
      expect(cards.last.visible, isFalse);
    });

    test('leaves out the cards of a switched-off module (C03)', () {
      final cards = configurableDashboardCards(
        configs: stored(),
        moduleStatuses: on(off: {ModuleId.body}),
        modules: modules,
      );
      expect(ids(cards), isNot(contains('steps')));
      expect(ids(cards), isNot(contains('weight')));
      expect(ids(cards), hasLength(6));
    });

    test('ignores stored cards no module provides', () {
      final cards = configurableDashboardCards(
        configs: [
          ...stored(),
          const DashboardCardConfig(
            cardId: 'ghost',
            module: ModuleId.body,
            visible: true,
            sortIndex: 99,
          ),
        ],
        moduleStatuses: on(),
        modules: modules,
      );
      expect(ids(cards), isNot(contains('ghost')));
    });

    test('shows nothing when every module is off', () {
      final cards = configurableDashboardCards(
        configs: stored(),
        moduleStatuses: {for (final module in ModuleId.values) module: false},
        modules: modules,
      );
      expect(cards, isEmpty);
    });
  });

  group('hiddenByModuleCount', () {
    test('counts the known cards of switched-off modules only', () {
      expect(
        hiddenByModuleCount(
          configs: stored(),
          moduleStatuses: on(off: {ModuleId.body, ModuleId.gamification}),
          modules: modules,
        ),
        3,
      );
    });

    test('is 0 when all modules are on or the card is unknown', () {
      expect(
        hiddenByModuleCount(
          configs: stored(),
          moduleStatuses: on(),
          modules: modules,
        ),
        0,
      );
      expect(
        hiddenByModuleCount(
          configs: const [
            DashboardCardConfig(
              cardId: 'ghost',
              module: ModuleId.body,
              visible: true,
              sortIndex: 0,
            ),
          ],
          moduleStatuses: on(off: {ModuleId.body}),
          modules: modules,
        ),
        0,
      );
    });
  });

  group('fullListTargetIndex', () {
    final all = stored();
    final shown = configurableDashboardCards(
      configs: all,
      moduleStatuses: on(off: {ModuleId.body}),
      modules: modules,
    );

    test('targets the position of the listed neighbour in the full list', () {
      // Listed: water, workout, focus, tasks, nutrition, xp. "workout" moving
      // up takes the place of "water" (full position 1), not of the unlisted
      // "weight" in front of it (full position 2).
      expect(
        fullListTargetIndex(all: all, shown: shown, fromShown: 1, toShown: 0),
        1,
      );
      // Moving "water" down takes the place of "workout" (full position 3).
      expect(
        fullListTargetIndex(all: all, shown: shown, fromShown: 0, toShown: 1),
        3,
      );
    });

    test('is null when nothing would change or an index is out of range', () {
      expect(
        fullListTargetIndex(all: all, shown: shown, fromShown: 2, toShown: 2),
        isNull,
      );
      expect(
        fullListTargetIndex(all: all, shown: shown, fromShown: 0, toShown: -1),
        isNull,
      );
      expect(
        fullListTargetIndex(
          all: all,
          shown: shown,
          fromShown: shown.length - 1,
          toShown: shown.length,
        ),
        isNull,
      );
    });
  });
}
