import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  setUp(() async {
    harness = await DataHarness.create();
    container = harness.createContainer();
    container.listen(weightOverviewProvider, (_, _) {});
    container.listen(profileProvider, (_, _) {});
    container.listen(weightEntriesProvider, (_, _) {});
  });
  tearDown(() => harness.dispose());

  Future<WeightOverview> overview() async {
    await container.read(weightEntriesProvider.future);
    await container.read(profileProvider.future);
    await Future<void>.delayed(Duration.zero);
    return container.read(weightOverviewProvider).requireValue;
  }

  Future<void> add(String isoDate, int hour, int grams) async {
    final date = LocalDate.parse(isoDate);
    await container
        .read(weightRepositoryProvider)
        .create(
          commandId: harness.ids.newId(),
          draft: WeightDraft(
            weightGrams: grams,
            occurredAtUtc: DateTime.utc(date.year, date.month, date.day, hour),
          ),
        );
  }

  test('no measurements: empty overview without goal or BMI', () async {
    final result = await overview();
    expect(result.isEmpty, isTrue);
    expect(result.current, isNull);
    expect(result.points, isEmpty);
    expect(result.deltaToPreviousGrams, isNull);
    expect(result.weekDeltaGrams, isNull);
    expect(result.goal, isNull);
    expect(result.bmi, isNull);
    expect(result.periodDays, 7);
  });

  test(
    'current, delta to previous (reference -0,3 kg) and week comparison',
    () async {
      await add('2026-09-26', 7, 72500);
      await add('2026-10-02', 7, 71800);
      await add('2026-10-03', 7, 71500);
      final result = await overview();
      expect(result.current!.weightGrams, 71500);
      expect(result.deltaToPreviousGrams, -300);
      expect(
        result.weekDeltaGrams,
        -1000,
        reason: '71,5 - 72,5 (anchor 2026-09-26)',
      );
      expect(result.entriesNewestFirst.map((e) => e.weightGrams), [
        71500,
        71800,
        72500,
      ]);
    },
  );

  test('the period selection changes the chart window only', () async {
    await add('2026-08-01', 7, 74000);
    await add('2026-10-03', 7, 71500);
    expect((await overview()).points, hasLength(1));
    container.read(weightPeriodProvider.notifier).select(90);
    final ninety = await overview();
    expect(ninety.periodDays, 90);
    expect(ninety.points, hasLength(2));
    expect(ninety.entriesNewestFirst, hasLength(2));
  });

  test('goal and BMI appear only with their voluntary prerequisites', () async {
    await add('2026-10-03', 7, 71500);
    expect((await overview()).goal, isNull);

    await (harness.database.update(harness.database.profile)).write(
      const ProfileCompanion(
        startWeightGrams: Value(74000),
        targetWeightGrams: Value(68000),
      ),
    );
    final withGoal = await overview();
    await Future<void>.delayed(Duration.zero);
    final goal = container.read(weightOverviewProvider).requireValue.goal;
    expect(withGoal.bmi, isNull, reason: 'height and age are missing');
    expect(goal, isNotNull);
    expect(goal!.remainingGrams, 3500);
    expect(goal.reached, isFalse);

    await (harness.database.update(
      harness.database.profile,
    )).write(const ProfileCompanion(heightCm: Value(175), ageYears: Value(30)));
    await Future<void>.delayed(Duration.zero);
    final bmi = container.read(weightOverviewProvider).requireValue.bmi;
    expect(bmi!.tenths, 233);
  });

  test('a new day moves the window (today provider)', () async {
    await add('2026-09-28', 7, 72000);
    expect((await overview()).points, hasLength(1));
    harness.clock.advance(const Duration(days: 8));
    container.read(todayProvider.notifier).refresh();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(weightOverviewProvider).requireValue.points, isEmpty);
  });

  test('a deleted measurement leaves the overview', () async {
    await add('2026-10-03', 7, 71500);
    final id = (await overview()).current!.id;
    await container
        .read(weightRepositoryProvider)
        .delete(commandId: harness.ids.newId(), id: id);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(weightOverviewProvider).requireValue.isEmpty, isTrue);
  });
}
