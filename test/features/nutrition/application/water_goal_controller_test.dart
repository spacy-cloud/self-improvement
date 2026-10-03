import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_goal_controller.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

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
    container.listen(waterGoalSettingsProvider, (_, _) {});
    container.listen(waterTodayProvider, (_, _) {});
    container.listen(goalVersionsProvider, (_, _) {});
    await container.read(waterTodayProvider.future);
    await container.read(goalVersionsProvider.future);
    await pumpUntil(
      () => container.read(waterGoalSettingsProvider).hasValue,
      reason: 'goal settings loaded',
    );
  });
  tearDown(() => kit.dispose());

  WaterGoalController controller([int initial = 2500]) {
    container.listen(waterGoalControllerProvider(initial), (_, _) {});
    return container.read(waterGoalControllerProvider(initial).notifier);
  }

  WaterGoalFormState formState([int initial = 2500]) =>
      container.read(waterGoalControllerProvider(initial));

  WaterGoalSettings settings() =>
      container.read(waterGoalSettingsProvider).requireValue;

  Future<List<GoalVersion>> waterVersions() async =>
      (await container.read(goalVersionRepositoryProvider).all())
          .where((v) => v.type == GoalType.water)
          .toList();

  group('the form', () {
    test('starts with the value it was given, clean', () {
      final s = formState(3000);
      expect(s.targetText, '3000');
      expect(s.dirty, isFalse);
      expect(s.fieldError, isNull);
      expect(s.submitting, isFalse);
      expect(s.submitFailure, isNull);
    });

    test('plus and minus step by 50 ml and clamp to 250 to 10000', () {
      controller().step(1);
      expect(formState().targetText, '2550');
      controller().step(-1);
      controller().step(-1);
      expect(formState().targetText, '2450');
      expect(formState().dirty, isTrue);

      controller(10000).step(1);
      expect(formState(10000).targetText, '10000');
      controller(250).step(-1);
      expect(formState(250).targetText, '250');
    });

    test('stepping from an unusable text starts at the given value', () {
      controller(3000).setTargetText('abc');
      controller(3000).step(1);
      expect(formState(3000).targetText, '3050');
      controller(2000).setTargetText('2025');
      controller(2000).step(-1);
      expect(formState(2000).targetText, '1950');
    });

    test('typing clears the hint', () async {
      controller().setTargetText('2525');
      await controller().submit();
      expect(formState().fieldError, isNotNull);
      controller().setTargetText('2500');
      expect(formState().fieldError, isNull);
    });
  });

  group('validation', () {
    test('invalid targets give a German hint and save nothing', () async {
      const messages = {
        '': 'Bitte gib dein Tagesziel in Millilitern ein.',
        'abc':
            'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 2500.',
        '2,5':
            'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 2500.',
        '249': 'Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.',
        '10050': 'Bitte gib ein Tagesziel zwischen 250 und 10.000 ml ein.',
        '2525': 'Das Tagesziel geht in 50-ml-Schritten, zum Beispiel 2.500 ml.',
      };
      final before = (await waterVersions()).length;
      for (final entry in messages.entries) {
        container.invalidate(waterGoalControllerProvider(2500));
        controller().setTargetText(entry.key);
        final result = await controller().submit();
        expect(result, isA<WaterGoalRejected>(), reason: '"${entry.key}"');
        expect(formState().fieldError, entry.value, reason: '"${entry.key}"');
      }
      expect((await waterVersions()).length, before);
      expect(await kit.receipts(), isEmpty);
    });

    test('both ends of the range and the step are accepted', () async {
      for (final ml in [250, 300, 2550, 10000]) {
        container.invalidate(waterGoalControllerProvider(2500));
        controller().setTargetText('$ml');
        final result = await controller().submit();
        expect(result, isA<WaterGoalSaved>(), reason: '$ml');
      }
    });
  });

  group('saving (AT24)', () {
    test(
      'a change applies from tomorrow: message, date and the stored version',
      () async {
        controller().setTargetText('3000');
        final result = await controller().submit();
        expect(result, isA<WaterGoalSaved>());
        final saved = result as WaterGoalSaved;
        expect(saved.targetMl, 3000);
        expect(saved.effectiveFrom, LocalDate(2026, 10, 4));
        expect(saved.message, 'Tagesziel auf 3 l gesetzt. Es gilt ab morgen.');
        expect(formState().dirty, isFalse);

        final versions = await waterVersions();
        final tomorrow = versions.singleWhere(
          (v) => v.effectiveFrom == LocalDate(2026, 10, 4),
        );
        expect(tomorrow.target, 3000);
        expect(tomorrow.enabled, isTrue);
      },
    );

    test('today keeps its threshold, tomorrow uses the new target', () async {
      controller().setTargetText('3000');
      await controller().submit();
      await pumpUntil(
        () => settings().tomorrowTargetMl == 3000,
        reason: 'settings show the pending change',
      );
      expect(container.read(waterTodayProvider).requireValue.targetMl, 2500);
      expect(settings().todayTargetMl, 2500);
      expect(settings().hasPendingChange, isTrue);

      // The next day.
      kit.harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      await pumpUntil(
        () =>
            container.read(waterTodayProvider).value?.date ==
                LocalDate(2026, 10, 4) &&
            container.read(waterTodayProvider).value?.targetMl == 3000,
        reason: 'the new day uses the new target',
      );
      expect(settings().hasPendingChange, isFalse);
    });

    test('several edits made today replace one another', () async {
      for (final ml in [3000, 3500, 4000]) {
        container.invalidate(waterGoalControllerProvider(2500));
        controller().setTargetText('$ml');
        await controller().submit();
      }
      final tomorrow = (await waterVersions()).where(
        (v) => v.effectiveFrom == LocalDate(2026, 10, 4),
      );
      expect(tomorrow.single.target, 4000);
    });

    test('saving the current value creates no new version', () async {
      final before = (await waterVersions()).length;
      controller().setTargetText('2500');
      expect(await controller().submit(), isA<WaterGoalSaved>());
      expect((await waterVersions()).length, before);
    });

    test(
      'saving a target switches a goal that was off back on from tomorrow',
      () async {
        await container
            .read(goalsCommandsProvider)
            .update(
              commandId: kit.newId(),
              changes: const {
                GoalType.water: GoalSetting(target: 2500, enabled: false),
              },
            );
        await pumpUntil(
          () => !settings().tomorrowEnabled,
          reason: 'goal switched off for tomorrow',
        );
        expect(
          container.read(waterTodayProvider).requireValue.hasTarget,
          isTrue,
        );

        container.invalidate(waterGoalControllerProvider(2500));
        controller().setTargetText('2750');
        expect(await controller().submit(), isA<WaterGoalSaved>());
        await pumpUntil(
          () => settings().tomorrowEnabled,
          reason: 'goal switched on again',
        );
        expect(settings().tomorrowTargetMl, 2750);
      },
    );

    test('a double tap saves once', () async {
      controller().setTargetText('3000');
      final first = controller().submit();
      final second = controller().submit();
      final results = await Future.wait([first, second]);
      expect(results.whereType<WaterGoalSaved>(), hasLength(1));
      expect(results.whereType<WaterGoalRejected>(), hasLength(1));
      expect(await kit.receipts(), hasLength(1));
    });
  });

  group('failures', () {
    test(
      'a storage failure keeps the input and retries with the SAME command id',
      () async {
        controller().setTargetText('3000');
        projection.failBeforeBody = StateError('db locked');
        final failed = await controller().submit();
        expect(failed, isA<WaterGoalRejected>());
        final s = formState();
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.targetText, '3000');
        expect(await kit.receipts(), isEmpty);
        expect(
          (await waterVersions()).any((v) => v.target == 3000),
          isFalse,
          reason: 'nothing was stored',
        );
        // The first id handed out is the command id of the attempt.
        final commandId = ids.issued.first;

        projection.failBeforeBody = null;
        expect(await controller().submit(), isA<WaterGoalSaved>());
        expect(formState().submitFailure, isNull);
        expect(
          (await kit.receipts()).single.commandId,
          commandId,
          reason: 'the retry reused the command id of the failed attempt',
        );
      },
    );

    test('changed input after a failure is a new command id', () async {
      controller().setTargetText('3000');
      projection.failBeforeBody = StateError('db locked');
      await controller().submit();
      controller().setTargetText('3500');
      projection.failBeforeBody = null;
      await controller().submit();
      final receipt = (await kit.receipts()).single;
      expect(ids.issued, contains(receipt.commandId));
      expect(
        receipt.commandId,
        isNot(ids.issued.first),
        reason: 'changed content is a new action with a new command id',
      );
    });
  });
}
