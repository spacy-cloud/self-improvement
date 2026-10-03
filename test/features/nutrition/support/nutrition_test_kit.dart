import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/nutrition/data/meal_repository.dart';
import 'package:self_improvement/features/nutrition/data/water_repository.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The profile start used by tests that seed the onboarded state.
final LocalDate kitStart = LocalDate(2026, 9, 1);

/// "Today" of the default harness clock (10:00 in Berlin).
final LocalDate kitToday = LocalDate(2026, 10, 3);

/// A water repository over the harness database (real snapshot service and
/// goal versions). Uses [runner] when given, otherwise the harness runner.
WaterRepository buildWaterRepository(
  DataHarness harness, {
  CommandRunner? runner,
}) => WaterRepository(
  database: harness.database,
  runner: runner ?? harness.runner,
  snapshots: GoalSnapshotService(
    database: harness.database,
    clock: harness.clock,
    ids: harness.ids,
  ),
  goalVersions: GoalVersionRepository(harness.database),
);

/// A command runner over the harness with a different projection (for example
/// one that fails after the real synchronisation).
CommandRunner buildRunner(
  DataHarness harness,
  ProjectionSynchronizer projections,
) => CommandRunner(
  database: harness.database,
  clock: harness.clock,
  ids: harness.ids,
  projections: projections,
  events: harness.events,
  gamificationEnabled: () =>
      harness.moduleStatus.isEnabled(ModuleId.gamification),
);

/// Real in-memory data stack for the nutrition tests.
class NutritionKit {
  NutritionKit._(this.harness, this.water, this.meals);

  final DataHarness harness;
  final WaterRepository water;
  final MealRepository meals;

  AppDatabase get database => harness.database;

  /// Creates the kit. [realProjection] runs snapshots and XP like the app;
  /// [onboarded] seeds the state after onboarding (all modules, default goal
  /// versions) from [startedOn] (default: [kitStart]).
  static Future<NutritionKit> create({
    bool realProjection = false,
    ProjectionSynchronizer? projections,
    String nowIso = '2026-10-03T08:00:00Z',
    bool onboarded = false,
    LocalDate? startedOn,
  }) async {
    final harness = await DataHarness.create(
      nowIso: nowIso,
      projections: projections,
      realProjection: realProjection,
    );
    if (onboarded) {
      await harness.seedOnboarded(startedOn: startedOn ?? kitStart);
    }
    return NutritionKit._(
      harness,
      buildWaterRepository(harness),
      MealRepository(database: harness.database, runner: harness.runner),
    );
  }

  Future<void> dispose() => harness.dispose();

  /// A new command id.
  String newId() => harness.ids.newId();

  /// All XP award rows.
  Future<List<XpAwardRow>> awards() => database.select(database.xpAwards).get();

  /// The XP award rows of one source kind, ordered by key.
  Future<List<String>> awardKeys(String sourceKind) async => [
    for (final award in await awards())
      if (award.sourceKind == sourceKind) award.awardKey,
  ]..sort();

  /// Every command receipt.
  Future<List<CommandReceiptRow>> receipts() =>
      database.select(database.commandReceipts).get();

  /// Every water row including soft-deleted ones.
  Future<List<WaterEntryRow>> waterRows() =>
      database.select(database.waterEntries).get();

  /// Every meal row including soft-deleted ones.
  Future<List<MealEntryRow>> mealRows() =>
      database.select(database.mealEntries).get();
}

/// Delegates to a projection and fails on demand.
///
/// - [failAfterSync]: thrown AFTER the delegate wrote its rows, so everything
///   the projection wrote inside the transaction (snapshots, XP) must be rolled
///   back together with the entry.
/// - [failBeforeBody]: thrown by `totalXp()`, which the runner calls at the very
///   start of EVERY command (also commands that report no affected day, such
///   as goal changes).
final class FlakyProjection implements ProjectionSynchronizer {
  FlakyProjection(this.delegate);

  final ProjectionSynchronizer delegate;

  Object? failAfterSync;
  Object? failBeforeBody;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    await delegate.syncDays(days);
    final error = failAfterSync;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<int> totalXp() async {
    final error = failBeforeBody;
    if (error != null) {
      throw error;
    }
    return delegate.totalXp();
  }
}

/// A clock that jumps after a number of `nowUtc()` calls, to test input that
/// was valid when the form checked it but not any more when the command runs
/// (a manual clock change or a time correction in between).
final class SteppingClock implements ClockService {
  SteppingClock(this._inner);

  final ClockService _inner;

  /// Number of `nowUtc()` calls so far.
  int calls = 0;

  /// After this many calls `nowUtc()` is shifted by [jump]; null: never.
  int? jumpAfterCall;

  /// The shift applied once [jumpAfterCall] calls happened.
  Duration jump = Duration.zero;

  @override
  DateTime nowUtc() {
    calls++;
    final base = _inner.nowUtc();
    final after = jumpAfterCall;
    return after != null && calls > after ? base.add(jump) : base;
  }

  @override
  String get timeZoneId => _inner.timeZoneId;

  @override
  LocalDate today() => _inner.today();

  @override
  LocalDate localDateOf(DateTime utc, {String? timeZoneId}) =>
      _inner.localDateOf(utc, timeZoneId: timeZoneId);

  @override
  LocalDateTime toLocal(DateTime utc, {String? timeZoneId}) =>
      _inner.toLocal(utc, timeZoneId: timeZoneId);

  @override
  ZonedResolution toUtc(LocalDate date, LocalTime time, {String? timeZoneId}) =>
      _inner.toUtc(date, time, timeZoneId: timeZoneId);
}

/// Records every id that is handed out, to prove which command ids a
/// controller used.
final class RecordingIdGenerator implements IdGenerator {
  RecordingIdGenerator(this._inner);

  final IdGenerator _inner;

  /// All ids in the order they were issued.
  final List<String> issued = [];

  @override
  String newId() {
    final id = _inner.newId();
    issued.add(id);
    return id;
  }
}

/// A provider container wired to [kit] like the app: the same database, clock,
/// events and projection; optionally with another id source (to see which
/// command ids a controller used), another projection (to inject failures) or
/// another clock (to script time jumps).
ProviderContainer containerFor(
  NutritionKit kit, {
  IdGenerator? ids,
  ProjectionSynchronizer? projection,
  ClockService? clock,
}) {
  final harness = kit.harness;
  final container = ProviderContainer(
    retry: (retryCount, error) => null,
    overrides: [
      appDatabaseProvider.overrideWithValue(harness.database),
      clockProvider.overrideWithValue(clock ?? harness.clock),
      idGeneratorProvider.overrideWithValue(ids ?? harness.ids),
      commandEventsProvider.overrideWithValue(harness.events),
      projectionSynchronizerProvider.overrideWithValue(
        projection ?? harness.projections,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Lets the event loop run (stream emissions, coalesced recomputations)
/// until [condition] holds. Deterministic: it spins event-loop turns and does
/// not depend on wall-clock delays.
Future<void> pumpUntil(
  bool Function() condition, {
  String reason = 'condition',
}) async {
  for (var turn = 0; turn < 5000; turn++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('Timed out waiting for: $reason');
}

/// Lets the event loop run a fixed number of turns (to show that NOTHING
/// happens, for example that an unrelated change causes no new emission).
Future<void> pumpTurns([int turns = 200]) async {
  for (var turn = 0; turn < turns; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A UTC instant on 2026-10-03 (clock "now" is 08:00Z = 10:00 in Berlin).
DateTime at(int hour, [int minute = 0, int day = 3]) =>
    DateTime.utc(2026, 10, day, hour, minute);
