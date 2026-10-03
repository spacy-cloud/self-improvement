import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/modules/application/module_lifecycle.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';

import '../../../support/db_fixtures.dart';

/// Counts the lifecycle calls it receives.
final class _CountingModule extends SelfImprovementModule {
  _CountingModule(this.id, {this.failToInitialize = false});

  @override
  final ModuleId id;
  final bool failToInitialize;
  int initialized = 0;
  int disposed = 0;
  int running = 0;
  int maxRunning = 0;

  @override
  String get title => 'Modul ${id.key}';
  @override
  String get description => 'Test';
  @override
  IconData get icon => Icons.circle_outlined;
  @override
  List<RouteBase> get routes => const <RouteBase>[];
  @override
  List<DashboardCardDescriptor> get dashboardCards => const [];
  @override
  List<QuickAction> get quickActions => const [];

  @override
  Future<void> initialize(Ref ref) async {
    running++;
    if (running > maxRunning) {
      maxRunning = running;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    initialized++;
    running--;
    if (failToInitialize) {
      throw StateError('init failed');
    }
  }

  @override
  void dispose() => disposed++;
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(condition(), isTrue, reason: 'the condition was not reached');
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late List<_CountingModule> modules;
  late ProviderContainer container;

  Future<void> start({Set<String>? enabled, bool failFocus = false}) async {
    harness = await DataHarness.create();
    await harness.seedOnboarded(enabledModules: enabled);
    modules = <_CountingModule>[
      for (final id in ModuleId.values)
        _CountingModule(
          id,
          failToInitialize: failFocus && id == ModuleId.focus,
        ),
    ];
    container = harness.createContainer(
      overrides: [appModulesProvider.overrideWithValue(modules)],
    );
    container.listen(moduleStatusesProvider, (_, _) {});
    await container.read(moduleStatusesProvider.future);
    container.read(moduleLifecycleProvider);
  }

  tearDown(() => harness.dispose());

  _CountingModule module(ModuleId id) => modules.singleWhere((m) => m.id == id);

  test(
    'initializes every active module once and none that is off (BS-58)',
    () async {
      await start(enabled: <String>{'body', 'focus', 'tasks'});
      await _until(() => module(ModuleId.tasks).initialized == 1);
      expect(module(ModuleId.body).initialized, 1);
      expect(module(ModuleId.focus).initialized, 1);
      expect(module(ModuleId.nutrition).initialized, 0);
      expect(module(ModuleId.gamification).initialized, 0);
      expect(modules.every((m) => m.disposed == 0), isTrue);
    },
  );

  test(
    'switching a module off disposes it, switching it on initializes it again',
    () async {
      await start();
      await _until(() => module(ModuleId.body).initialized == 1);
      await container
          .read(moduleManagerProvider)
          .setEnabled(
            commandId: harness.ids.newId(),
            module: ModuleId.body,
            enabled: false,
          );
      await _until(() => module(ModuleId.body).disposed == 1);
      expect(module(ModuleId.nutrition).disposed, 0);
      await container
          .read(moduleManagerProvider)
          .setEnabled(
            commandId: harness.ids.newId(),
            module: ModuleId.body,
            enabled: true,
          );
      await _until(() => module(ModuleId.body).initialized == 2);
      expect(module(ModuleId.body).disposed, 1);
    },
  );

  test('deactivation deletes no data (AT03)', () async {
    await start();
    await harness.database
        .into(harness.database.weightEntries)
        .insert(weightRow());
    await container
        .read(moduleManagerProvider)
        .setEnabled(
          commandId: harness.ids.newId(),
          module: ModuleId.body,
          enabled: false,
        );
    await _until(() => module(ModuleId.body).disposed == 1);
    expect(
      await harness.database.select(harness.database.weightEntries).get(),
      hasLength(1),
    );
  });

  test(
    'a status that does not change initializes nothing twice (idempotent)',
    () async {
      await start();
      await _until(() => module(ModuleId.body).initialized == 1);
      // Another module changes: the statuses stream emits again.
      await container
          .read(moduleManagerProvider)
          .setEnabled(
            commandId: harness.ids.newId(),
            module: ModuleId.tasks,
            enabled: false,
          );
      await _until(() => module(ModuleId.tasks).disposed == 1);
      expect(module(ModuleId.body).initialized, 1);
      expect(module(ModuleId.body).disposed, 0);
    },
  );

  test(
    'calls are serialized and a failing module does not stop the others',
    () async {
      await start(failFocus: true);
      await _until(() => module(ModuleId.gamification).initialized == 1);
      expect(module(ModuleId.focus).initialized, 1);
      expect(modules.every((m) => m.maxRunning == 1), isTrue);
      // The failing module counts as active: switching it off disposes it.
      await container
          .read(moduleManagerProvider)
          .setEnabled(
            commandId: harness.ids.newId(),
            module: ModuleId.focus,
            enabled: false,
          );
      await _until(() => module(ModuleId.focus).disposed == 1);
    },
  );

  test('ending the app disposes the active modules only', () async {
    await start(enabled: <String>{'body', 'tasks'});
    await _until(() => module(ModuleId.tasks).initialized == 1);
    container.dispose();
    expect(module(ModuleId.body).disposed, 1);
    expect(module(ModuleId.tasks).disposed, 1);
    expect(module(ModuleId.focus).disposed, 0);
  });
}
