import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late DashboardCardRepository cards;

  setUp(() async {
    harness = await DataHarness.create();
    await harness.seedOnboarded();
    cards = DashboardCardRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  Future<List<String>> order() async => [
    for (final c in await cards.cards()) c.cardId,
  ];

  test('starts in the default order with every card visible', () async {
    expect(await order(), SchemaKeys.defaultCardOrder);
    final all = await cards.cards();
    expect(all.every((c) => c.visible), isTrue);
    expect(all.map((c) => c.sortIndex), List.generate(8, (i) => i));
    expect(
      all.firstWhere((c) => c.cardId == 'water').module,
      ModuleId.nutrition,
    );
    expect(
      all.firstWhere((c) => c.cardId == 'xp').module,
      ModuleId.gamification,
    );
  });

  test(
    'hiding and showing a card is persisted and keeps its position',
    () async {
      await cards.setVisible(commandId: 'h1', cardId: 'weight', visible: false);
      final weight = (await cards.cards()).firstWhere(
        (c) => c.cardId == 'weight',
      );
      expect(weight.visible, isFalse);
      expect(weight.sortIndex, 2);
      await cards.setVisible(commandId: 'h2', cardId: 'weight', visible: true);
      expect(
        (await cards.cards()).firstWhere((c) => c.cardId == 'weight').visible,
        isTrue,
      );
    },
  );

  test('moving renumbers the positions contiguously', () async {
    await cards.move(commandId: 'm1', cardId: 'xp', toIndex: 0);
    expect(await order(), [
      'xp',
      'steps',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
    ]);
    await cards.move(commandId: 'm2', cardId: 'steps', toIndex: 7);
    expect(await order(), [
      'xp',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'steps',
    ]);
    expect(
      (await cards.cards()).map((c) => c.sortIndex),
      List.generate(8, (i) => i),
    );
  });

  test(
    'up and down buttons are the accessible alternative to dragging',
    () async {
      await cards.moveBy(commandId: 'u1', cardId: 'water', delta: -1);
      expect((await order()).take(2), ['water', 'steps']);
      await cards.moveBy(commandId: 'u2', cardId: 'water', delta: -1);
      expect((await order()).first, 'water', reason: 'already first: stays');
      await cards.moveBy(commandId: 'd1', cardId: 'xp', delta: 1);
      expect((await order()).last, 'xp', reason: 'already last: stays');
      await cards.moveBy(commandId: 'd2', cardId: 'water', delta: 1);
      expect((await order()).take(2), ['steps', 'water']);
    },
  );

  test(
    'out of range targets are clamped and unknown cards are not found',
    () async {
      await cards.move(commandId: 'c1', cardId: 'steps', toIndex: 99);
      expect((await order()).last, 'steps');
      await cards.move(commandId: 'c2', cardId: 'steps', toIndex: -5);
      expect((await order()).first, 'steps');
      await expectLater(
        cards.move(commandId: 'c3', cardId: 'sleep', toIndex: 0),
        throwsA(isA<NotFoundFailure>()),
      );
      await expectLater(
        cards.setVisible(commandId: 'c4', cardId: 'sleep', visible: false),
        throwsA(isA<NotFoundFailure>()),
      );
    },
  );

  test('a replayed move does nothing twice', () async {
    await cards.move(commandId: 'same', cardId: 'xp', toIndex: 0);
    await cards.move(commandId: 'same', cardId: 'weight', toIndex: 0);
    expect((await order()).first, 'xp');
  });

  test('configuration of a deactivated module is kept', () async {
    await cards.setVisible(commandId: 'k', cardId: 'water', visible: false);
    await harness.database
        .into(harness.database.moduleStatusHistory)
        .insert(
          ModuleStatusHistoryCompanion.insert(
            id: 'off',
            moduleId: 'nutrition',
            effectiveAtUtc: DateTime.utc(2026, 10, 3, 9),
            localDate: harness.clock.today(),
            enabled: false,
          ),
        );
    expect(
      (await cards.cards()).firstWhere((c) => c.cardId == 'water').visible,
      isFalse,
    );
  });
}
