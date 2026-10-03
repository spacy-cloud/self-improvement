import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';
import 'package:self_improvement/features/modules/application/module_toggle_controller.dart';

import '../../../app/support/fake_modules.dart';
import '../../../support/db_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late ProviderContainer container;

  Future<void> start({List<SelfImprovementModule>? modules}) async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    await harness.seedOnboarded();
    container = harness.createContainer(
      overrides: [
        if (modules != null) appModulesProvider.overrideWithValue(modules),
      ],
    );
  }

  tearDown(() => harness.dispose());

  ModuleToggleController controller() =>
      container.read(moduleToggleControllerProvider.notifier);
  Future<Map<ModuleId, bool>> statuses() => harness.moduleStatus.statuses();
  Future<int> historyRows() async =>
      (await harness.database
              .select(harness.database.moduleStatusHistory)
              .get())
          .length;

  group('switching modules (AT03)', () {
    test('off and on again is stored and deletes no data', () async {
      await start();
      await harness.database
          .into(harness.database.weightEntries)
          .insert(weightRow());

      final off = await controller().setEnabled(ModuleId.body, enabled: false);
      expect(off, isA<ModuleToggled>());
      expect((await statuses())[ModuleId.body], isFalse);
      expect(
        await harness.database.select(harness.database.weightEntries).get(),
        hasLength(1),
      );

      final on = await controller().setEnabled(ModuleId.body, enabled: true);
      expect(on, isA<ModuleToggled>());
      expect((await statuses())[ModuleId.body], isTrue);
      expect(
        await harness.database.select(harness.database.weightEntries).get(),
        hasLength(1),
      );
    });

    test(
      'the state survives a restart: a new container reads the same',
      () async {
        await start();
        await controller().setEnabled(ModuleId.nutrition, enabled: false);
        final restarted = harness.createContainer();
        restarted.listen(moduleStatusesProvider, (_, _) {});
        final value = await restarted.read(moduleStatusesProvider.future);
        expect(value[ModuleId.nutrition], isFalse);
        expect(value[ModuleId.body], isTrue);
      },
    );

    test('setting the current state again adds no history row', () async {
      await start();
      final before = await historyRows();
      await controller().setEnabled(ModuleId.tasks, enabled: true);
      expect(await historyRows(), before);
    });

    test('a running change locks the same module', () async {
      await start();
      final first = controller().setEnabled(ModuleId.body, enabled: false);
      expect(container.read(moduleToggleControllerProvider), {ModuleId.body});
      final second = await controller().setEnabled(
        ModuleId.body,
        enabled: false,
      );
      expect(second, isA<ModuleToggleBusy>());
      expect(await first, isA<ModuleToggled>());
      expect(container.read(moduleToggleControllerProvider), isEmpty);
    });

    test('enableAll switches on every module that is off (AT04)', () async {
      await start();
      for (final module in ModuleId.values) {
        await controller().setEnabled(module, enabled: false);
      }
      expect((await statuses()).values.every((on) => !on), isTrue);
      final results = await controller().enableAll();
      expect(results, hasLength(ModuleId.values.length));
      expect(results.every((r) => r is ModuleToggled), isTrue);
      expect((await statuses()).values.every((on) => on), isTrue);
    });
  });

  group('open focus session (AT19)', () {
    test(
      'blocks switching focus off, changes nothing and deletes nothing',
      () async {
        await start();
        await harness.database
            .into(harness.database.focusSessions)
            .insert(focusRow());
        final result = await controller().setEnabled(
          ModuleId.focus,
          enabled: false,
        );
        expect(result, isA<ModuleToggleBlocked>());
        final blocked = result as ModuleToggleBlocked;
        expect(blocked.module, ModuleId.focus);
        expect(blocked.check.message, contains('Fokus-Sitzung'));
        expect(blocked.check.resolveLabel, 'Sitzung zuerst beenden');
        expect((await statuses())[ModuleId.focus], isTrue);
        expect(
          await harness.database.select(harness.database.focusSessions).get(),
          hasLength(1),
        );
      },
    );

    test('works once the session is resolved', () async {
      await start();
      await harness.database
          .into(harness.database.focusSessions)
          .insert(focusRow());
      await controller().setEnabled(ModuleId.focus, enabled: false);
      await (harness.database.update(harness.database.focusSessions))
          .write(const FocusSessionsCompanion(status: Value('discarded')));
      final result = await controller().setEnabled(
        ModuleId.focus,
        enabled: false,
      );
      expect(result, isA<ModuleToggled>());
      expect((await statuses())[ModuleId.focus], isFalse);
    });

    test('other modules can be switched off meanwhile', () async {
      await start();
      await harness.database
          .into(harness.database.focusSessions)
          .insert(focusRow());
      final result = await controller().setEnabled(
        ModuleId.body,
        enabled: false,
      );
      expect(result, isA<ModuleToggled>());
    });

    test('the message and action of the module itself are used', () async {
      await start(
        modules: <SelfImprovementModule>[
          const FakeModule(
            ModuleId.tasks,
            check: MustResolveFirst(
              message: 'Erst fertig machen',
              resolveLabel: 'Fertig',
            ),
          ),
        ],
      );
      final result = await controller().setEnabled(
        ModuleId.tasks,
        enabled: false,
      );
      expect(result, isA<ModuleToggleBlocked>());
      expect(
        (result as ModuleToggleBlocked).check.message,
        'Erst fertig machen',
      );
      expect((await statuses())[ModuleId.tasks], isTrue);
    });
  });

  group('a failed save (AT27, C05)', () {
    test(
      'keeps the old state; the retry reuses the command id and saves once',
      () async {
        await start();
        projection.failure = StateError('disk full');
        final failed = await controller().setEnabled(
          ModuleId.body,
          enabled: false,
        );
        expect(failed, isA<ModuleToggleFailed>());
        expect((failed as ModuleToggleFailed).failure, isA<StorageFailure>());
        expect((await statuses())[ModuleId.body], isTrue);
        expect(container.read(moduleToggleControllerProvider), isEmpty);

        projection.failure = null;
        final saved = await controller().setEnabled(
          ModuleId.body,
          enabled: false,
        );
        expect(saved, isA<ModuleToggled>());
        expect((await statuses())[ModuleId.body], isFalse);
        final receipts = await harness.database
            .select(harness.database.commandReceipts)
            .get();
        final toggleReceipts = receipts.where(
          (r) => r.commandType == 'module.set_enabled',
        );
        expect(toggleReceipts, hasLength(1));
      },
    );
  });
}
