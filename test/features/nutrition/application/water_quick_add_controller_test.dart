import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_quick_add_controller.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late RecordingIdGenerator ids;
  late FlakyProjection projection;
  late ProviderContainer container;

  setUp(() async {
    kit = await NutritionKit.create(realProjection: true, onboarded: true);
    ids = RecordingIdGenerator(kit.harness.ids);
    projection = FlakyProjection(kit.harness.projections);
    container = containerFor(kit, ids: ids, projection: projection);
    // The controller lives with the app container; keep it alive here too.
    container.listen(waterQuickAddProvider, (_, _) {});
  });
  tearDown(() => kit.dispose());

  WaterQuickAddController controller() =>
      container.read(waterQuickAddProvider.notifier);

  WaterQuickAddState quickState() => container.read(waterQuickAddProvider);

  Future<int> totalMl() async =>
      (await container.read(waterRepositoryProvider).loadToday(kitToday))
          .totalMl;

  group('add', () {
    test('creates a real entry now and hands out the undo (AT10)', () async {
      final outcome = await controller().add(250);
      expect(outcome.undo, isNotNull);
      expect(outcome.replayed, isFalse);
      final entry = await container
          .read(waterRepositoryProvider)
          .findById(outcome.entityId!);
      expect(entry!.amountMl, 250);
      expect(entry.occurredAtUtc, kit.harness.clock.nowUtc());
      expect(await totalMl(), 250);
      expect(await kit.harness.totalXp(), 5);
      expect(waterAddedMessage(250), '250 ml hinzugefügt');
    });

    test(
      'both quick amounts work and the undo removes exactly that entry',
      () async {
        await controller().add(waterQuickAmountsMl[0]);
        final second = await controller().add(waterQuickAmountsMl[1]);
        expect(await totalMl(), 750);
        await second.undo!.run(kit.newId());
        expect(await totalMl(), 250);
        expect(await kit.harness.totalXp(), 5);
      },
    );

    test(
      'every tap uses its own command id: two taps are two entries',
      () async {
        await controller().add(250);
        await controller().add(250);
        expect(await totalMl(), 500);
        final receipts = await kit.receipts();
        expect(receipts, hasLength(2));
        expect(
          receipts.map((r) => r.commandId).toSet(),
          hasLength(2),
          reason: 'two distinct command ids',
        );
      },
    );

    test('simultaneous taps are never dropped, each is one entry', () async {
      final outcomes = await Future.wait([
        controller().add(250),
        controller().add(250),
        controller().add(500),
        controller().add(500),
      ]);
      expect(outcomes.map((o) => o.entityId).toSet(), hasLength(4));
      expect(await totalMl(), 1500);
      expect(await kit.waterRows(), hasLength(4));
    });

    test(
      'an invalid amount is a validation failure and stores nothing',
      () async {
        for (final bad in [49, 2001]) {
          await expectLater(
            controller().add(bad),
            throwsA(isA<ValidationFailure>()),
            reason: '$bad',
          );
          expect(quickState().failure, isA<ValidationFailure>());
          expect(quickState().canRetry, isFalse, reason: 'a retry cannot help');
        }
        expect(await totalMl(), 0);
        expect(await kit.receipts(), isEmpty);
        expect(await controller().retry(), isNull);
      },
    );

    test('the amount limits of a quick add are 50 and 2000 ml', () async {
      await controller().add(50);
      await controller().add(2000);
      expect(await totalMl(), 2050);
    });
  });

  group('failures (AT27)', () {
    test(
      'a storage failure stores no amount and no XP and is published',
      () async {
        projection.failAfterSync = StateError('disk full');
        await expectLater(
          controller().add(250),
          throwsA(isA<StorageFailure>()),
        );
        expect(await totalMl(), 0);
        expect(await kit.harness.totalXp(), 0);
        expect(await kit.awards(), isEmpty);
        expect(quickState().failure, isA<StorageFailure>());
        expect(quickState().canRetry, isTrue);
        expect(quickState().retryAmountMl, 250);
        expect(
          quickState().failure!.userMessage,
          'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten, bitte versuche es erneut.',
        );
      },
    );

    test(
      'retry repeats the tap with the SAME command id and saves once',
      () async {
        projection.failAfterSync = StateError('disk full');
        await expectLater(
          controller().add(250),
          throwsA(isA<StorageFailure>()),
        );
        // Issued so far: the tap's command id, then the entry id of the rolled
        // back attempt.
        expect(ids.issued, hasLength(2));
        final tapId = ids.issued.first;

        projection.failAfterSync = null;
        final outcome = await controller().retry();
        expect(outcome, isNotNull);
        expect(outcome!.replayed, isFalse);
        expect(
          ids.issued,
          hasLength(3),
          reason: 'the retry created only the entry id, no new command id',
        );
        final receipts = await kit.receipts();
        expect(receipts.single.commandId, tapId, reason: 'the same command id');
        expect(await totalMl(), 250);
        expect(await kit.harness.totalXp(), 5);
        expect(quickState().failure, isNull);
        expect(quickState().canRetry, isFalse);
      },
    );

    test('a retry that commits twice cannot create a second entry', () async {
      projection.failAfterSync = StateError('disk full');
      await expectLater(controller().add(250), throwsA(isA<StorageFailure>()));
      projection.failAfterSync = null;
      await controller().retry();
      // The failure state is gone; a second retry has nothing to do.
      expect(await controller().retry(), isNull);
      expect(await totalMl(), 250);
    });

    test(
      'a NEW tap after a failure is a new action with a new command id',
      () async {
        projection.failAfterSync = StateError('disk full');
        await expectLater(
          controller().add(250),
          throwsA(isA<StorageFailure>()),
        );
        final failedTapId = ids.issued.first;
        projection.failAfterSync = null;
        await controller().add(250);
        final receipts = await kit.receipts();
        expect(receipts, hasLength(1));
        expect(receipts.single.commandId, isNot(failedTapId));
        expect(await totalMl(), 250);
        expect(quickState().failure, isNull, reason: 'the newest outcome wins');
      },
    );

    test(
      'failing taps keep failing visibly, the newest failure is kept',
      () async {
        projection.failAfterSync = StateError('disk full');
        await expectLater(
          controller().add(250),
          throwsA(isA<StorageFailure>()),
        );
        await expectLater(
          controller().add(500),
          throwsA(isA<StorageFailure>()),
        );
        expect(quickState().retryAmountMl, 500);
        projection.failAfterSync = null;
        await controller().retry();
        expect(
          await totalMl(),
          500,
          reason: 'only the latest failed tap is retried',
        );
      },
    );

    test('dismissing the failure forgets the retry', () async {
      projection.failAfterSync = StateError('disk full');
      await expectLater(controller().add(250), throwsA(isA<StorageFailure>()));
      controller().dismissFailure();
      expect(quickState().failure, isNull);
      expect(quickState().canRetry, isFalse);
      projection.failAfterSync = null;
      expect(await controller().retry(), isNull);
      expect(await totalMl(), 0);
    });

    test(
      'a failure before the body (nothing written yet) behaves the same',
      () async {
        projection.failBeforeBody = StateError('db locked');
        await expectLater(
          controller().add(250),
          throwsA(isA<StorageFailure>()),
        );
        projection.failBeforeBody = null;
        await controller().retry();
        expect(await totalMl(), 250);
        expect((await kit.receipts()).single.commandId, ids.issued.first);
      },
    );
  });

  group('reactive effect on the models', () {
    test('the today model follows quick adds and undo', () async {
      container.listen(waterTodayProvider, (_, _) {});
      await container.read(waterTodayProvider.future);
      final outcome = await controller().add(250);
      await pumpUntil(
        () => container.read(waterTodayProvider).value?.totalMl == 250,
        reason: 'model after add',
      );
      await outcome.undo!.run(kit.newId());
      await pumpUntil(
        () => container.read(waterTodayProvider).value?.totalMl == 0,
        reason: 'model after undo',
      );
    });
  });
}
