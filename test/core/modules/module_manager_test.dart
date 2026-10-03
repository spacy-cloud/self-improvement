import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_manager.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../support/db_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ModuleManager manager;

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    manager = ModuleManager(
      database: harness.database,
      runner: harness.runner,
      status: harness.moduleStatus,
    );
  });
  tearDown(() => harness.dispose());

  Future<void> toggle(ModuleId module, bool enabled) async {
    harness.clock.advance(const Duration(minutes: 1));
    await manager.setEnabled(
      commandId: harness.ids.newId(),
      module: module,
      enabled: enabled,
    );
  }

  test('deactivating hides the module but deletes no data (AT03)', () async {
    final weights = WeightRepository(
      database: harness.database,
      runner: harness.runner,
    );
    await weights.create(
      commandId: harness.ids.newId(),
      draft: WeightDraft(
        weightGrams: 71500,
        occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
      ),
    );
    await toggle(ModuleId.body, false);
    expect(await harness.moduleStatus.isEnabled(ModuleId.body), isFalse);
    expect(
      await weights.watchActive().first,
      hasLength(1),
      reason: 'data stays',
    );
    await toggle(ModuleId.body, true);
    expect(await harness.moduleStatus.isEnabled(ModuleId.body), isTrue);
    expect(await weights.watchActive().first, hasLength(1));
  });

  test('setting the current state is a no-op without a history row', () async {
    final before = await harness.database
        .select(harness.database.moduleStatusHistory)
        .get();
    await manager.setEnabled(
      commandId: 'x',
      module: ModuleId.tasks,
      enabled: true,
    );
    expect(
      await harness.database.select(harness.database.moduleStatusHistory).get(),
      hasLength(before.length),
    );
  });

  test('a module change masks today and a replay does not add rows', () async {
    await manager.setEnabled(
      commandId: 'c1',
      module: ModuleId.nutrition,
      enabled: false,
    );
    await manager.setEnabled(
      commandId: 'c1',
      module: ModuleId.nutrition,
      enabled: false,
    );
    final history = await (harness.database.select(
      harness.database.moduleStatusHistory,
    )..where((r) => r.moduleId.equals('nutrition'))).get();
    expect(history, hasLength(2), reason: 'seed row plus one change');
    final status = (await harness.dayStatusRepository().statusFor(
      LocalDate(2026, 10, 3),
    ))!;
    expect(
      status.goals.singleWhere((g) => g.goalKey == 'water').applicable,
      isFalse,
    );
    expect(status.applicableCount, 4);
  });

  test('the change is published as ModulesChanged after commit', () async {
    final events = <AppEvent>[];
    final subscription = harness.events.stream.listen(events.add);
    addTearDown(subscription.cancel);
    await manager.setEnabled(
      commandId: 'e',
      module: ModuleId.focus,
      enabled: false,
    );
    await Future<void>.delayed(Duration.zero);
    final changed = events.whereType<ModulesChanged>().single;
    expect(changed.module, ModuleId.focus);
    expect(changed.enabled, isFalse);
  });

  group('focus guard (AT19)', () {
    for (final status in ['running', 'paused', 'awaiting_confirmation']) {
      test('an open $status session blocks deactivation', () async {
        await harness.database
            .into(harness.database.focusSessions)
            .insert(
              focusRow(
                status: status,
                segmentStartedAt: status == 'running'
                    ? Value(fixtureNow)
                    : const Value.absent(),
              ),
            );
        expect(await manager.hasOpenFocusSession(), isTrue);
        await expectLater(
          manager.setEnabled(
            commandId: harness.ids.newId(),
            module: ModuleId.focus,
            enabled: false,
          ),
          throwsA(
            isA<ConflictFailure>().having(
              (f) => f.kind,
              'kind',
              ConflictKind.openFocusSession,
            ),
          ),
        );
        expect(await harness.moduleStatus.isEnabled(ModuleId.focus), isTrue);
      });
    }

    test('completed and discarded sessions do not block', () async {
      await harness.database
          .into(harness.database.focusSessions)
          .insert(
            focusRow(
              id: 'c',
              status: 'completed',
              completedDate: Value(fixtureDate),
            ),
          );
      await harness.database
          .into(harness.database.focusSessions)
          .insert(focusRow(id: 'd', status: 'discarded'));
      expect(await manager.hasOpenFocusSession(), isFalse);
      await toggle(ModuleId.focus, false);
      expect(await harness.moduleStatus.isEnabled(ModuleId.focus), isFalse);
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        hasLength(2),
        reason: 'no session is deleted',
      );
    });

    test('other modules can be deactivated while a session is open', () async {
      await harness.database
          .into(harness.database.focusSessions)
          .insert(focusRow());
      await toggle(ModuleId.tasks, false);
      expect(await harness.moduleStatus.isEnabled(ModuleId.tasks), isFalse);
    });
  });

  test(
    'history stays ordered even if the device clock went backwards',
    () async {
      await toggle(ModuleId.tasks, false);
      harness.clock.setNow(DateTime.utc(2026, 10, 2, 8));
      await manager.setEnabled(
        commandId: harness.ids.newId(),
        module: ModuleId.tasks,
        enabled: true,
      );
      expect(
        await harness.moduleStatus.isEnabled(ModuleId.tasks),
        isTrue,
        reason: 'the newest decision wins',
      );
      final history =
          await (harness.database.select(harness.database.moduleStatusHistory)
                ..where((r) => r.moduleId.equals('tasks'))
                ..orderBy([(r) => OrderingTerm.asc(r.effectiveAtUtc)]))
              .get();
      expect(history.last.enabled, isTrue);
    },
  );
}
