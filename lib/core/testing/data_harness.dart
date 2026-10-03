import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:self_improvement/core/bootstrap/app_bootstrap.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/projection_synchronizer_impl.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/shared/local_date.dart';

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
    ProjectionSynchronizer? projections,
    bool realProjection = false,
  }) async {
    TimeZones.ensureInitialized();
    final database = createTestDatabase();
    final clock = FakeClock.at(nowIso, timeZoneId: timeZoneId);
    final ids = SequentialIdGenerator();
    final events = CommandEvents();
    final moduleStatus = ModuleStatusRepository(database);
    await AppBootstrap.run(database: database, clock: clock);
    final ProjectionSynchronizer projection =
        projections ??
        (realProjection
            ? ProjectionSynchronizerImpl(
                database: database,
                snapshots: GoalSnapshotService(
                  database: database,
                  clock: clock,
                  ids: ids,
                ),
                xp: XpProjector(database),
              )
            : const NoopProjectionSynchronizer());
    final runner = CommandRunner(
      database: database,
      clock: clock,
      ids: ids,
      projections: projection,
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
      projections: projection,
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

  /// Test setup helper: marks onboarding as completed like the real flow
  /// would: all five modules enabled (or only [enabledModules]), default goal
  /// versions effective from the profile start, default dashboard cards, and
  /// optionally another profile start date.
  ///
  /// This writes rows directly (no commands) and is meant for test fixtures.
  Future<void> seedOnboarded({
    Set<String>? enabledModules,
    LocalDate? startedOn,
  }) async {
    final now = clock.nowUtc();
    final start = startedOn ?? clock.localDateOf(now);
    await database.transaction(() async {
      await (database.update(database.profile)).write(
        ProfileCompanion(
          startedLocalDate: Value(start),
          onboardingCompleted: const Value(true),
        ),
      );
      for (final module in SchemaKeys.modules) {
        await database
            .into(database.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: ids.newId(),
                moduleId: module,
                effectiveAtUtc: now,
                localDate: start,
                enabled: enabledModules?.contains(module) ?? true,
              ),
            );
      }
      for (final type in GoalType.values) {
        await database
            .into(database.goalVersions)
            .insert(
              GoalVersionsCompanion.insert(
                id: ids.newId(),
                goalType: type.key,
                targetInteger: Value(type.defaultTarget),
                enabled: true,
                effectiveFromDate: start,
                createdAtUtc: now,
              ),
            );
      }
      var index = 0;
      for (final card in SchemaKeys.defaultCardOrder) {
        await database
            .into(database.dashboardCards)
            .insert(
              DashboardCardsCompanion.insert(
                cardId: card,
                moduleId: SchemaKeys.dashboardCardModule[card]!,
                sortIndex: index++,
              ),
            );
      }
    });
  }

  /// A [DayStatusRepository] over the harness database (real snapshot service
  /// and facts source).
  DayStatusRepository dayStatusRepository() => DayStatusRepository(
    database: database,
    clock: clock,
    snapshots: GoalSnapshotService(database: database, clock: clock, ids: ids),
    facts: DayFactsSource(database),
  );

  /// Total XP (sum of awards) read directly.
  Future<int> totalXp() => XpProjector(database).totalXp();

  Future<void> dispose() async {
    for (final container in _containers) {
      container.dispose();
    }
    await events.dispose();
    await database.close();
  }
}
