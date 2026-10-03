import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;
  late ModuleStatusRepository repository;

  setUp(() {
    db = createTestDatabase();
    repository = ModuleStatusRepository(db);
  });
  tearDown(() => db.close());

  Future<void> change(
    String id,
    ModuleId module,
    bool enabled,
    DateTime at,
    LocalDate day,
  ) => db
      .into(db.moduleStatusHistory)
      .insert(
        ModuleStatusHistoryCompanion.insert(
          id: id,
          moduleId: module.key,
          effectiveAtUtc: at,
          localDate: day,
          enabled: enabled,
        ),
      );

  test('without history every module is enabled', () async {
    final statuses = await repository.statuses();
    expect(statuses.keys, ModuleId.values);
    expect(statuses.values.every((enabled) => enabled), isTrue);
    expect(await repository.isEnabled(ModuleId.focus), isTrue);
  });

  test('the latest change wins and other modules are unaffected', () async {
    await change(
      '1',
      ModuleId.body,
      false,
      DateTime.utc(2026, 10, 1, 8),
      LocalDate(2026, 10, 1),
    );
    await change(
      '2',
      ModuleId.body,
      true,
      DateTime.utc(2026, 10, 2, 8),
      LocalDate(2026, 10, 2),
    );
    await change(
      '3',
      ModuleId.focus,
      false,
      DateTime.utc(2026, 10, 2, 9),
      LocalDate(2026, 10, 2),
    );
    final statuses = await repository.statuses();
    expect(statuses[ModuleId.body], isTrue);
    expect(statuses[ModuleId.focus], isFalse);
    expect(statuses[ModuleId.nutrition], isTrue);
  });

  test('state as of a day ignores later changes', () async {
    await change(
      '1',
      ModuleId.body,
      false,
      DateTime.utc(2026, 10, 1, 8),
      LocalDate(2026, 10, 1),
    );
    await change(
      '2',
      ModuleId.body,
      true,
      DateTime.utc(2026, 10, 5, 8),
      LocalDate(2026, 10, 5),
    );
    expect(
      await repository.isEnabledOn(ModuleId.body, LocalDate(2026, 9, 30)),
      isTrue,
      reason: 'before any change',
    );
    expect(
      await repository.isEnabledOn(ModuleId.body, LocalDate(2026, 10, 1)),
      isFalse,
    );
    expect(
      await repository.isEnabledOn(ModuleId.body, LocalDate(2026, 10, 4)),
      isFalse,
    );
    expect(
      await repository.isEnabledOn(ModuleId.body, LocalDate(2026, 10, 5)),
      isTrue,
    );
  });

  test('several changes on one day resolve by time, then id', () async {
    final day = LocalDate(2026, 10, 3);
    await change('a', ModuleId.tasks, false, DateTime.utc(2026, 10, 3, 8), day);
    await change('b', ModuleId.tasks, true, DateTime.utc(2026, 10, 3, 9), day);
    await change('c', ModuleId.tasks, false, DateTime.utc(2026, 10, 3, 9), day);
    expect(
      await repository.isEnabled(ModuleId.tasks),
      isFalse,
      reason: 'same time: higher id wins',
    );
  });

  test('watchStatuses re-emits after a change', () async {
    final emissions = <Map<ModuleId, bool>>[];
    final subscription = repository.watchStatuses().listen(emissions.add);
    await Future<void>.delayed(Duration.zero);
    await change(
      '1',
      ModuleId.gamification,
      false,
      DateTime.utc(2026, 10, 1),
      LocalDate(2026, 10, 1),
    );
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    expect(emissions.first[ModuleId.gamification], isTrue);
    expect(emissions.last[ModuleId.gamification], isFalse);
  });

  test('the bundled registry has the five modules in canonical order', () {
    expect(bundledModules.map((m) => m.id).toList(), ModuleId.values);
    expect(moduleFor(ModuleId.nutrition).id, ModuleId.nutrition);
    for (final module in bundledModules) {
      expect(module.title, isNotEmpty);
      expect(module.description, isNotEmpty);
    }
  });
}
