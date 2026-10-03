import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
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

  MealDay today() => container.read(mealsTodayProvider).requireValue;

  Future<String> addMeal({
    String name = 'Haferflocken',
    int? kcal,
    DateTime? when,
  }) async {
    final outcome = await container
        .read(mealRepositoryProvider)
        .create(
          commandId: kit.newId(),
          draft: MealDraft(
            name: name,
            kcal: kcal,
            occurredAtUtc: when ?? at(6),
          ),
        );
    return outcome.entityId!;
  }

  group('mealsTodayProvider', () {
    test('starts empty: no meals, nothing to say about calories', () async {
      expect(container.read(mealsTodayProvider).isLoading, isTrue);
      await open(mealsTodayProvider);
      expect(today().date, LocalDate(2026, 10, 3));
      expect(today().isEmpty, isTrue);
      expect(today().summary.completeness, KcalCompleteness.none);
      expect(today().summary.knownKcal, isNull);
    });

    test('follows adds, edits, deletes and undo with the summary', () async {
      await open(mealsTodayProvider);
      final repository = container.read(mealRepositoryProvider);
      final id = await addMeal(kcal: 400, when: at(5));
      await addMeal(when: at(6));
      await pumpUntil(
        () => today().summary.mealCount == 2,
        reason: 'two meals',
      );
      expect(today().summary.knownKcal, 400);
      expect(today().summary.completeness, KcalCompleteness.incomplete);
      expect(today().entriesNewestFirst.map((m) => m.name), [
        'Haferflocken',
        'Haferflocken',
      ]);

      await repository.update(
        commandId: kit.newId(),
        id: id,
        draft: MealDraft(name: 'Haferflocken', kcal: 450, occurredAtUtc: at(5)),
        expectedRowVersion: 1,
      );
      await pumpUntil(() => today().summary.knownKcal == 450, reason: 'edit');

      final deleted = await repository.delete(commandId: kit.newId(), id: id);
      await pumpUntil(() => today().summary.mealCount == 1, reason: 'delete');
      expect(
        today().summary.knownKcal,
        isNull,
        reason: 'only the meal without calories is left',
      );
      await deleted.undo!.run(kit.newId());
      await pumpUntil(() => today().summary.mealCount == 2, reason: 'undo');
      expect(today().summary.knownKcal, 450);
    });

    test('all meals with calories: complete', () async {
      await open(mealsTodayProvider);
      await addMeal(kcal: 400, when: at(5));
      await addMeal(kcal: 0, when: at(6));
      await pumpUntil(
        () => today().summary.mealCount == 2,
        reason: 'two meals',
      );
      expect(today().summary.completeness, KcalCompleteness.complete);
      expect(today().summary.knownKcal, 400);
    });

    test('switches to the new day when the date changes', () async {
      await open(mealsTodayProvider);
      await addMeal();
      await pumpUntil(
        () => today().summary.mealCount == 1,
        reason: 'first day',
      );
      kit.harness.clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      await pumpUntil(
        () =>
            container.read(mealsTodayProvider).value?.date ==
            LocalDate(2026, 10, 4),
        reason: 'new day',
      );
      expect(today().isEmpty, isTrue);
    });
  });

  group('mealsDayProvider', () {
    test('shows any day by its stored local date', () async {
      await addMeal(when: DateTime.utc(2026, 10, 1, 9), kcal: 300);
      final oct1 = mealsDayProvider(LocalDate(2026, 10, 1));
      final oct2 = mealsDayProvider(LocalDate(2026, 10, 2));
      await open(oct1);
      await open(oct2);
      expect(container.read(oct1).requireValue.summary.mealCount, 1);
      expect(container.read(oct1).requireValue.summary.knownKcal, 300);
      expect(container.read(oct2).requireValue.isEmpty, isTrue);
    });

    test('Berlin day boundary: 22:30Z belongs to the next local day', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 4, 6));
      await addMeal(name: 'spät', when: DateTime.utc(2026, 10, 3, 21, 59));
      await addMeal(
        name: 'Mitternacht',
        when: DateTime.utc(2026, 10, 3, 22, 30),
      );
      final oct3 = mealsDayProvider(LocalDate(2026, 10, 3));
      final oct4 = mealsDayProvider(LocalDate(2026, 10, 4));
      await open(oct3);
      await open(oct4);
      expect(
        container.read(oct3).requireValue.entriesNewestFirst.map((m) => m.name),
        ['spät'],
      );
      expect(
        container.read(oct4).requireValue.entriesNewestFirst.map((m) => m.name),
        ['Mitternacht'],
      );
    });
  });

  group('mealHistoryProvider', () {
    test(
      'groups per day with a summary each, for the requested window',
      () async {
        await addMeal(kcal: 300, when: DateTime.utc(2026, 10, 2, 9));
        await addMeal(when: DateTime.utc(2026, 9, 29, 9));
        await addMeal(kcal: 100, when: at(5));
        final week = mealHistoryProvider(7);
        await open(week);
        var history = container.read(week).requireValue;
        expect(history.days, 7);
        expect(history.daysNewestFirst.map((d) => d.date), [
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 2),
          LocalDate(2026, 9, 29),
        ]);
        expect(
          history.daysNewestFirst.last.summary.completeness,
          KcalCompleteness.incomplete,
        );
        expect(history.daysNewestFirst.last.summary.knownKcal, isNull);

        final shorter = mealHistoryProvider(3);
        await open(shorter);
        history = container.read(shorter).requireValue;
        expect(history.daysNewestFirst.map((d) => d.date), [
          LocalDate(2026, 10, 3),
          LocalDate(2026, 10, 2),
        ]);
      },
    );

    test('a new meal appears in the history', () async {
      final window = mealHistoryProvider(14);
      await open(window);
      expect(container.read(window).requireValue.isEmpty, isTrue);
      await addMeal();
      await pumpUntil(
        () => !container.read(window).requireValue.isEmpty,
        reason: 'meal appears',
      );
    });
  });

  group('mealEntryProvider', () {
    test('emits the meal and then null after it was deleted', () async {
      final id = await addMeal(kcal: 0);
      final provider = mealEntryProvider(id);
      await open(provider);
      expect(container.read(provider).requireValue!.kcal, 0);
      await container
          .read(mealRepositoryProvider)
          .delete(commandId: kit.newId(), id: id);
      await pumpUntil(
        () => container.read(provider).value == null,
        reason: 'null after delete',
      );
    });

    test('an unknown id is null, not an error', () async {
      final provider = mealEntryProvider('does-not-exist');
      await open(provider);
      expect(container.read(provider).requireValue, isNull);
    });
  });
}
