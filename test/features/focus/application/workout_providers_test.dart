import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';

import '../support/manual_tick_source.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  setUp(() async {
    harness = await DataHarness.create();
    container = harness.createContainer();
  });
  tearDown(() => harness.dispose());

  Future<String> log(int hour, {int minutes = 30}) async {
    final outcome = await container
        .read(workoutRepositoryProvider)
        .create(
          commandId: harness.ids.newId(),
          draft: WorkoutDraft(
            category: TrainingCategory.strength,
            durationMinutes: minutes,
            occurredAtUtc: DateTime.utc(2026, 10, 3, hour),
          ),
        );
    return outcome.entityId!;
  }

  test('the list is newest first and follows deletes', () async {
    container.listen(workoutEntriesProvider, (_, _) {});
    final a = await log(5, minutes: 10);
    final b = await log(6, minutes: 20);
    await settle();
    expect(container.read(workoutEntriesProvider).value!.map((e) => e.id), [
      b,
      a,
    ]);
    await container
        .read(workoutRepositoryProvider)
        .delete(commandId: harness.ids.newId(), id: b);
    await settle();
    expect(container.read(workoutEntriesProvider).value!.map((e) => e.id), [a]);
  });

  test('the paged list returns only the newest entries', () async {
    final ids = <String>[];
    for (var hour = 0; hour < 5; hour++) {
      ids.add(await log(hour));
    }
    container.listen(workoutEntriesPageProvider(2), (_, _) {});
    final page = await container.read(workoutEntriesPageProvider(2).future);
    expect(page.map((e) => e.id), ids.reversed.take(2));
    container.listen(workoutEntriesPageProvider(50), (_, _) {});
    expect(
      (await container.read(workoutEntriesPageProvider(50).future)).length,
      5,
    );
  });

  test('a workout by id emits null once it is deleted', () async {
    final id = await log(7);
    container.listen(workoutEntryProvider(id), (_, _) {});
    expect((await container.read(workoutEntryProvider(id).future))!.id, id);
    await container
        .read(workoutRepositoryProvider)
        .delete(commandId: harness.ids.newId(), id: id);
    await settle();
    expect(container.read(workoutEntryProvider(id)).value, isNull);
  });

  test(
    'the week entries are the current week only (Monday to Sunday)',
    () async {
      // Saturday 2026-10-03: the week is 09-28 to 10-04.
      await container
          .read(workoutRepositoryProvider)
          .create(
            commandId: harness.ids.newId(),
            draft: WorkoutDraft(
              category: TrainingCategory.cardio,
              durationMinutes: 20,
              occurredAtUtc: DateTime.utc(2026, 9, 27, 10),
            ),
          );
      final inWeek = await log(6);
      container.listen(workoutWeekEntriesProvider, (_, _) {});
      final week = await container.read(workoutWeekEntriesProvider.future);
      expect(week.map((e) => e.id), [inWeek]);
    },
  );
}
