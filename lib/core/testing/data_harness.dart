import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:self_improvement/core/bootstrap/app_bootstrap.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';

/// Wires an in-memory database, a fake clock, deterministic ids and a command
/// runner for repository tests. All pieces are real except the clock, ids and
/// (optionally) the projection.
///
/// ```dart
/// final harness = await DataHarness.create();
/// addTearDown(harness.dispose);
/// ```
class DataHarness {
  DataHarness._({
    required this.database,
    required this.clock,
    required this.ids,
    required this.events,
    required this.runner,
    required this.moduleStatus,
    required this.projections,
  });

  final AppDatabase database;
  final FakeClock clock;
  final SequentialIdGenerator ids;
  final CommandEvents events;
  final CommandRunner runner;
  final ModuleStatusRepository moduleStatus;
  final ProjectionSynchronizer projections;

  /// Creates the harness with the database bootstrapped (profile + settings
  /// singletons exist, onboarding not completed).
  ///
  /// [nowIso] is the fake clock start (UTC), default 2026-10-03 08:00Z which
  /// is 10:00 on 2026-10-03 in Europe/Berlin (summer time).
  static Future<DataHarness> create({
    String nowIso = '2026-10-03T08:00:00Z',
    String timeZoneId = 'Europe/Berlin',
    ProjectionSynchronizer projections = const NoopProjectionSynchronizer(),
  }) async {
    TimeZones.ensureInitialized();
    final database = createTestDatabase();
    final clock = FakeClock.at(nowIso, timeZoneId: timeZoneId);
    final ids = SequentialIdGenerator();
    final events = CommandEvents();
    final moduleStatus = ModuleStatusRepository(database);
    await AppBootstrap.run(database: database, clock: clock);
    final runner = CommandRunner(
      database: database,
      clock: clock,
      ids: ids,
      projections: projections,
      events: events,
      gamificationEnabled: () => moduleStatus.isEnabled(ModuleId.gamification),
    );
    return DataHarness._(
      database: database,
      clock: clock,
      ids: ids,
      events: events,
      runner: runner,
      moduleStatus: moduleStatus,
      projections: projections,
    );
  }

  /// A [ProviderContainer] wired to this harness (database, clock, ids,
  /// projection, events). Provider retry is disabled. Disposed with the
  /// harness.
  ProviderContainer createContainer({List<Override> overrides = const []}) {
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        clockProvider.overrideWithValue(clock),
        idGeneratorProvider.overrideWithValue(ids),
        commandEventsProvider.overrideWithValue(events),
        projectionSynchronizerProvider.overrideWithValue(projections),
        ...overrides,
      ],
    );
    _containers.add(container);
    return container;
  }

  final List<ProviderContainer> _containers = [];

  Future<void> dispose() async {
    for (final container in _containers) {
      container.dispose();
    }
    await events.dispose();
    await database.close();
  }
}
