import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_cards_controller.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';

import '../support/dashboard_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  ProviderContainer open() {
    final c = harness.createContainer(
      overrides: [
        dashboardModulesProvider.overrideWithValue(testModules(TapLog())),
      ],
    );
    c.listen(configurableCardsProvider, (_, _) {});
    c.listen(dashboardCardsControllerProvider, (_, _) {});
    return c;
  }

  Future<List<String>> listed(ProviderContainer c) async {
    await c.read(dashboardCardsProvider.future);
    await c.read(moduleStatusesProvider.future);
    await pumpEventQueue();
    return [
      for (final card in c.read(configurableCardsProvider).requireValue)
        card.cardId,
    ];
  }

  Future<List<String>> stored(ProviderContainer c) async => [
    for (final card in await c.read(dashboardCardRepositoryProvider).cards())
      card.cardId,
  ];

  DashboardCardsController controller(ProviderContainer c) =>
      c.read(dashboardCardsControllerProvider.notifier);

  Future<void> setModule(ModuleId module, {required bool enabled}) => container
      .read(moduleManagerProvider)
      .setEnabled(
        commandId: harness.ids.newId(),
        module: module,
        enabled: enabled,
      );

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded();
    container = open();
    await listed(container);
  });
  tearDown(() => harness.dispose());

  test('hiding a card is stored and survives a restart (AT02, C04)', () async {
    expect(
      await controller(container).setVisible('water', visible: false),
      isNull,
    );
    final cards = await container.read(dashboardCardRepositoryProvider).cards();
    expect(
      {for (final card in cards) card.cardId: card.visible}['water'],
      isFalse,
    );

    // Restart: a new container reads the same database.
    final restarted = open();
    await listed(restarted);
    final visible = {
      for (final card in restarted.read(configurableCardsProvider).requireValue)
        card.cardId: card.visible,
    };
    expect(visible['water'], isFalse);
    expect(visible['steps'], isTrue);
  });

  test('showing a hidden card again restores it in its place', () async {
    await controller(container).setVisible('focus', visible: false);
    await controller(container).setVisible('focus', visible: true);
    final cards = await container.read(dashboardCardRepositoryProvider).cards();
    expect(cards.firstWhere((card) => card.cardId == 'focus').visible, isTrue);
    expect(await stored(container), [
      'steps',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
  });

  test('moveBy swaps with the listed neighbour, not an unlisted card (C03)', () async {
    await setModule(ModuleId.body, enabled: false);
    expect(await listed(container), [
      'water',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
    expect(await controller(container).moveBy('workout', -1), isNull);
    // "workout" took the place of "water"; the stored cards of the switched-off
    // module keep their positions around it.
    expect(await listed(container), [
      'workout',
      'water',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
    expect(await stored(container), [
      'steps',
      'workout',
      'water',
      'weight',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
  });

  test(
    'a reactivated module brings its cards back where they were (AT03)',
    () async {
      await controller(container).setVisible('weight', visible: false);
      await setModule(ModuleId.body, enabled: false);
      expect(await listed(container), isNot(contains('weight')));
      await setModule(ModuleId.body, enabled: true);
      expect(await listed(container), [
        'steps',
        'water',
        'weight',
        'workout',
        'focus',
        'tasks',
        'nutrition',
        'xp',
      ]);
      final weight =
          (await container.read(dashboardCardRepositoryProvider).cards())
              .firstWhere((card) => card.cardId == 'weight');
      expect(weight.visible, isFalse, reason: 'the choice to hide it is kept');
    },
  );

  test('reorder uses the final position of a drag', () async {
    expect(await controller(container).reorder(0, 2), isNull);
    expect((await listed(container)).take(3), ['water', 'weight', 'steps']);
    expect(await controller(container).reorder(2, 0), isNull);
    expect((await listed(container)).take(3), ['steps', 'water', 'weight']);
  });

  test('moving past either end or onto itself changes nothing', () async {
    expect(await controller(container).moveBy('steps', -1), isNull);
    expect(await controller(container).moveBy('xp', 1), isNull);
    expect(await controller(container).reorder(3, 3), isNull);
    expect(await controller(container).moveBy('ghost', 1), isNull);
    expect(await stored(container), [
      'steps',
      'water',
      'weight',
      'workout',
      'focus',
      'tasks',
      'nutrition',
      'xp',
    ]);
  });

  test('two quick taps apply the change once', () async {
    final first = controller(container).moveBy('water', 1);
    final second = controller(container).moveBy('water', 1);
    await Future.wait([first, second]);
    expect((await listed(container)).take(3), ['steps', 'weight', 'water']);
  });

  test(
    'a failed write keeps the order and the retry reuses the command id (AT27)',
    () async {
      final db = harness.database;
      final before = harness.ids.newId();
      await db.customStatement(
        "CREATE TRIGGER fail_move BEFORE UPDATE ON dashboard_cards "
        "BEGIN SELECT RAISE(ABORT, 'simulated write error'); END",
      );
      final failure = await controller(container).moveBy('water', 1);
      expect(failure, isA<StorageFailure>());
      expect(await stored(container), [
        'steps',
        'water',
        'weight',
        'workout',
        'focus',
        'tasks',
        'nutrition',
        'xp',
      ]);
      expect(
        await (db.select(
          db.commandReceipts,
        )..where((r) => r.commandType.equals('dashboard.card.move'))).get(),
        isEmpty,
      );

      await db.customStatement('DROP TRIGGER fail_move');
      expect(await controller(container).moveBy('water', 1), isNull);
      expect((await listed(container)).take(3), ['steps', 'weight', 'water']);

      // One id for the failed attempt, reused by the retry: the next free id is
      // exactly two after the one taken before.
      final after = harness.ids.newId();
      int sequence(String id) =>
          int.parse(id.substring(id.length - 12), radix: 16);
      expect(sequence(after), sequence(before) + 2);
      final receipts = await (db.select(
        db.commandReceipts,
      )..where((r) => r.commandType.equals('dashboard.card.move'))).get();
      expect(receipts, hasLength(1));
    },
  );

  test('a different change after a failure gets its own command id', () async {
    final db = harness.database;
    await db.customStatement(
      "CREATE TRIGGER fail_move BEFORE UPDATE ON dashboard_cards "
      "BEGIN SELECT RAISE(ABORT, 'simulated write error'); END",
    );
    expect(
      await controller(container).moveBy('water', 1),
      isA<StorageFailure>(),
    );
    await db.customStatement('DROP TRIGGER fail_move');
    expect(await controller(container).moveBy('tasks', -1), isNull);
    expect(await listed(container), [
      'steps',
      'water',
      'weight',
      'workout',
      'tasks',
      'focus',
      'nutrition',
      'xp',
    ]);
  });
}
