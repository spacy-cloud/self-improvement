import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late ProviderContainer container;

  setUp(() async {
    kit = await NutritionKit.create(realProjection: true, onboarded: true);
    container = containerFor(kit);
  });
  tearDown(() => kit.dispose());

  /// Keeps [provider] alive and waits for its first value.
  Future<void> open<T>(StreamProvider<T> provider) async {
    container.listen(provider, (_, _) {});
    await container.read(provider.future);
  }

  WaterToday today() => container.read(waterTodayProvider).requireValue;

  Future<void> quickAdd(int ml) async {
    await container
        .read(waterRepositoryProvider)
        .quickAdd(commandId: kit.newId(), amountMl: ml);
  }

  group('waterTodayProvider', () {
    test('starts with an empty day and the default target', () async {
      expect(container.read(waterTodayProvider).isLoading, isTrue);
      await open(waterTodayProvider);
      expect(today().date, LocalDate(2026, 10, 3));
      expect(today().totalMl, 0);
      expect(today().targetMl, 2500);
      expect(today().percent, 0);
      expect(today().entriesNewestFirst, isEmpty);
    });

    test(
      'follows quick adds, including real percent above the target',
      () async {
        await open(waterTodayProvider);
        await quickAdd(250);
        await pumpUntil(() => today().totalMl == 250, reason: 'after 250');
        expect(today().percent, 10);
        expect(today().fraction, closeTo(0.1, 1e-12));

        for (var i = 0; i < 6; i++) {
          kit.harness.clock.advance(const Duration(minutes: 1));
          await quickAdd(500);
        }
        await pumpUntil(() => today().totalMl == 3250, reason: 'after 3250');
        expect(today().goalReached, isTrue);
        expect(today().fraction, 1.0);
        expect(today().percent, 130);
        expect(today().entryCount, 7);
      },
    );

    test('lists the entries newest first and drops deleted ones', () async {
      await open(waterTodayProvider);
      final repository = container.read(waterRepositoryProvider);
      final a = await repository.create(
        commandId: kit.newId(),
        draft: WaterDraft(amountMl: 100, occurredAtUtc: at(5)),
      );
      await repository.create(
        commandId: kit.newId(),
        draft: WaterDraft(amountMl: 200, occurredAtUtc: at(6)),
      );
      await pumpUntil(() => today().entryCount == 2, reason: 'two entries');
      expect(today().entriesNewestFirst.map((e) => e.amountMl), [200, 100]);
      await repository.delete(commandId: kit.newId(), id: a.entityId!);
      await pumpUntil(() => today().entryCount == 1, reason: 'one entry');
      expect(today().totalMl, 200);
    });

    test('switches to the new day when the date changes', () async {
      await open(waterTodayProvider);
      await quickAdd(250);
      await pumpUntil(() => today().totalMl == 250, reason: 'first day');

      kit.harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      await pumpUntil(
        () =>
            container.read(waterTodayProvider).value?.date ==
            LocalDate(2026, 10, 4),
        reason: 'new day',
      );
      expect(today().totalMl, 0, reason: 'yesterday\'s water is not today\'s');
      expect(today().entriesNewestFirst, isEmpty);
    });

    test(
      'a goal switched off applies from tomorrow: no target, the total stays',
      () async {
        await open(waterTodayProvider);
        await quickAdd(250);
        await container
            .read(goalsCommandsProvider)
            .update(
              commandId: kit.newId(),
              changes: const {
                GoalType.water: GoalSetting(target: 2500, enabled: false),
              },
            );
        await pumpUntil(() => today().totalMl == 250, reason: 'first day');
        expect(today().targetMl, 2500, reason: 'today keeps its threshold');

        kit.harness.clock.advance(const Duration(days: 1));
        container.read(todayProvider.notifier).refresh();
        await pumpUntil(
          () =>
              container.read(waterTodayProvider).value?.date ==
                  LocalDate(2026, 10, 4) &&
              container.read(waterTodayProvider).value?.targetMl == null,
          reason: 'no target on the new day',
        );
        expect(today().fraction, isNull);
        expect(today().percent, isNull);
        expect(today().remainingMl, isNull);
        expect(today().goalReached, isFalse);

        // Drinking is still recorded; the frozen snapshot of the new day says
        // "not applicable", so there is still no target.
        await quickAdd(500);
        await pumpUntil(
          () => today().totalMl == 500,
          reason: 'entry on new day',
        );
        expect(today().targetMl, isNull);
        expect(today().hasTarget, isFalse);
      },
    );
  });

  group('waterHistoryProvider', () {
    test('groups per day for the requested window', () async {
      final repository = container.read(waterRepositoryProvider);
      await repository.create(
        commandId: kit.newId(),
        draft: WaterDraft(
          amountMl: 300,
          occurredAtUtc: DateTime.utc(2026, 10, 2, 8),
        ),
      );
      await repository.create(
        commandId: kit.newId(),
        draft: WaterDraft(
          amountMl: 400,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 8),
        ),
      );
      await quickAdd(250);
      final week = waterHistoryProvider(7);
      await open(week);
      var history = container.read(week).requireValue;
      expect(history.days, 7);
      expect(history.daysNewestFirst.map((d) => d.totalMl), [250, 300, 400]);

      final shorter = waterHistoryProvider(3);
      await open(shorter);
      history = container.read(shorter).requireValue;
      expect(history.daysNewestFirst.map((d) => d.totalMl), [250, 300]);
    });

    test(
      'a new entry appears and the day rollover shifts the window',
      () async {
        final window = waterHistoryProvider(2);
        await open(window);
        expect(container.read(window).requireValue.isEmpty, isTrue);
        await quickAdd(250);
        await pumpUntil(
          () => !container.read(window).requireValue.isEmpty,
          reason: 'entry appears',
        );
        kit.harness.clock.advance(const Duration(days: 2));
        container.read(todayProvider.notifier).refresh();
        await pumpUntil(
          () => container.read(window).value?.isEmpty ?? false,
          reason: 'the entry left the two day window',
        );
      },
    );
  });

  group('waterEntryProvider', () {
    test('emits the entry and then null after it was deleted', () async {
      final repository = container.read(waterRepositoryProvider);
      final created = await repository.quickAdd(
        commandId: kit.newId(),
        amountMl: 250,
      );
      final provider = waterEntryProvider(created.entityId!);
      await open(provider);
      expect(container.read(provider).requireValue!.amountMl, 250);
      await repository.delete(commandId: kit.newId(), id: created.entityId!);
      await pumpUntil(
        () => container.read(provider).value == null,
        reason: 'null after delete',
      );
    });

    test('an unknown id is null, not an error', () async {
      final provider = waterEntryProvider('does-not-exist');
      await open(provider);
      expect(container.read(provider).requireValue, isNull);
    });
  });

  group('waterGoalSettingsProvider', () {
    test('combines the goal versions with today\'s target', () async {
      container.listen(waterGoalSettingsProvider, (_, _) {});
      await pumpUntil(
        () => container.read(waterGoalSettingsProvider).hasValue,
        reason: 'settings loaded',
      );
      final settings = container.read(waterGoalSettingsProvider).requireValue;
      expect(settings.effectiveFrom, LocalDate(2026, 10, 4));
      expect(settings.todayTargetMl, 2500);
      expect(settings.tomorrowTargetMl, 2500);
      expect(settings.tomorrowEnabled, isTrue);
      expect(settings.hasPendingChange, isFalse);
    });

    test('shows a change made today as pending', () async {
      container.listen(waterGoalSettingsProvider, (_, _) {});
      await container
          .read(goalsCommandsProvider)
          .update(
            commandId: kit.newId(),
            changes: const {GoalType.water: GoalSetting(target: 3000)},
          );
      await pumpUntil(
        () =>
            container.read(waterGoalSettingsProvider).value?.tomorrowTargetMl ==
            3000,
        reason: 'pending change visible',
      );
      final settings = container.read(waterGoalSettingsProvider).requireValue;
      expect(settings.todayTargetMl, 2500);
      expect(settings.hasPendingChange, isTrue);
      expect(
        (await container.read(goalVersionRepositoryProvider).all()).any(
          (v) => v.type == GoalType.water && v.target == 3000,
        ),
        isTrue,
      );
    });
  });
}
