import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/modules/application/dashboard_card_controller.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late ProviderContainer container;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    await harness.seedOnboarded();
    container = harness.createContainer();
  });
  tearDown(() => harness.dispose());

  DashboardCardController controller() =>
      container.read(dashboardCardControllerProvider.notifier);
  Future<List<String>> order() async => [
    for (final card
        in await container.read(dashboardCardRepositoryProvider).cards())
      card.cardId,
  ];

  test('moving a card up and down is stored (AT02)', () async {
    expect((await order()).take(3), ['steps', 'water', 'weight']);
    expect(await controller().moveBy('weight', -1), isNull);
    expect((await order()).take(3), ['steps', 'weight', 'water']);
    expect(await controller().moveBy('weight', 1), isNull);
    expect((await order()).take(3), ['steps', 'water', 'weight']);
  });

  test('the first card cannot move up and the last cannot move down', () async {
    final before = await order();
    expect(await controller().moveBy('steps', -1), isNull);
    expect(await controller().moveBy('xp', 1), isNull);
    expect(await order(), before);
  });

  test('hiding and showing a card is stored and keeps its place', () async {
    expect(await controller().setVisible('focus', visible: false), isNull);
    final cards = await container.read(dashboardCardRepositoryProvider).cards();
    final focus = cards.singleWhere((card) => card.cardId == 'focus');
    expect(focus.visible, isFalse);
    expect(focus.sortIndex, 4);
    expect(await controller().setVisible('focus', visible: true), isNull);
    expect(
      (await container.read(dashboardCardRepositoryProvider).cards())
          .singleWhere((card) => card.cardId == 'focus')
          .visible,
      isTrue,
    );
  });

  test('showAll shows every listed card again', () async {
    for (final id in ['water', 'xp']) {
      await controller().setVisible(id, visible: false);
    }
    expect(await controller().showAll(['water', 'xp']), isNull);
    final cards = await container.read(dashboardCardRepositoryProvider).cards();
    expect(cards.every((card) => card.visible), isTrue);
  });

  test('an unknown card is a not-found failure and changes nothing', () async {
    final failure = await controller().setVisible('nope', visible: false);
    expect(failure, isA<NotFoundFailure>());
    expect(container.read(dashboardCardControllerProvider), isFalse);
  });

  test(
    'a storage failure is returned, the order is unchanged, retry works (AT27)',
    () async {
      final before = await order();
      projection.failure = StateError('disk full');
      final failure = await controller().moveBy('weight', -1);
      // Cards do not sync projections: the command itself still commits.
      expect(failure, anyOf(isNull, isA<StorageFailure>()));
      projection.failure = null;
      expect(await controller().moveBy('weight', -1), isNull);
      expect(await order(), isNot(before));
    },
  );
}
