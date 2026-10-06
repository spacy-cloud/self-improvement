import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/bootstrap/app_runtime.dart';
import 'package:self_improvement/core/bootstrap/device_time_zone.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/database/database_connection.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/day_facts_source.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/data/goal_snapshot_service.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../database/support/migration_support.dart';

/// The start of the app on the database FILE of v0.1.0 (BS-98, AT02).
///
/// The production start (`AppRuntime.create()` with the production connection
/// `openAppConnection`, which resolves the file through `path_provider`) opens
/// a schema 1 file that the unchanged v0.1.0 code wrote
/// (`test/fixtures/v1/v1-database.sql`): it is migrated, nothing is lost, and
/// a second start finds a database of the current version.
///
/// Only the native side of `path_provider` is replaced (its platform channel
/// answers with a temporary directory), as in the production start flows. This
/// is a host test: it proves the code path, not the behaviour of a device.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late File databaseFile;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    root = Directory.systemTemp.createTempSync('v1_app_start_');
    final support = Directory('${root.path}/support')..createSync();
    final cache = Directory('${root.path}/cache')..createSync();
    databaseFile = File('${support.path}/$appDatabaseName.sqlite');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationSupportDirectory' => support.path,
        _ => cache.path,
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // A leftover temporary directory is not a test failure.
    }
  });

  /// What the schema 1 fixture holds, read from a copy that is not upgraded.
  Future<({Map<String, List<String>> columns, Map<String, List<String>> rows})>
  fixtureContent() async {
    final v1 = V1FixtureDatabase(v1FixtureExecutor());
    try {
      final columns = await columnsOfAllTables(v1);
      return (columns: columns, rows: await rowsOfAllTables(v1, columns));
    } finally {
      await v1.close();
    }
  }

  Future<AppRuntime> start() =>
      AppRuntime.create(zoneSource: _FixedZone('Europe/Berlin'));

  test('the production start migrates a v0.1.0 file and keeps all data (AT02, BS-98)', () async {
    await writeV1DatabaseFile(databaseFile.path);
    final fixture = await fixtureContent();

    final runtime = await start();
    addTearDown(runtime.dispose);
    final db = runtime.database;

    expect(await userVersion(db), 2);
    expect(await rowsOfAllTables(db, fixture.columns), fixture.rows);
    expect(await integrityCheck(db), ['ok']);
    expect(await foreignKeyViolations(db), isEmpty);
    expect(
      (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
        'foreign_keys',
      ),
      1,
    );
    // The new parts exist with their defaults.
    expect((await rowCounts(db))['workout_day_marks'], 0);
    final steps = await db.select(db.stepDays).get();
    expect(steps, hasLength(10));
    expect(steps.map((s) => s.source).toSet(), {'manual'});
    final settings = await db.select(db.appSettings).getSingle();
    expect(settings.healthStepsSyncEnabled, isFalse);
    expect(settings.healthStepsLastSyncAtUtc, isNull);
    expect(settings.themeMode, 'oled', reason: 'the stored setting is kept');
  });

  test('the technical questions of the app are answered from the migrated file (AT02, BS-98)', () async {
    await writeV1DatabaseFile(databaseFile.path);
    final fixture = await fixtureContent();
    final runtime = await start();
    addTearDown(runtime.dispose);
    final db = runtime.database;
    final clock = FakeClock.at('2026-04-08T07:20:00Z');

    // The profile of the file.
    final profile = await ProfileRepository(db).get();
    expect(profile!.displayName, 'Mia Muster');
    expect(profile.onboardingCompleted, isTrue);

    // The goal versions (the domain reads all eight of them).
    final goals = await GoalVersionRepository(db).all();
    expect(goals, hasLength(fixture.rows['goal_versions']!.length));

    // The stored snapshot of a day: which goals applied, with frozen targets.
    final ids = SequentialIdGenerator(100000);
    final snapshots = GoalSnapshotService(database: db, clock: clock, ids: ids);
    final snapshot = await snapshots.snapshotFor(LocalDate(2026, 4, 7));
    expect(snapshot, isNotNull);
    final targets = {
      for (final item in snapshot!.items) item.goalKey: item.target,
    };
    expect(targets['water'], 2500);
    expect(targets['steps'], 8000);
    expect(targets['focus_minutes'], 30);
    expect(targets.keys, containsAll(['weight_entry', 'task_completion']));

    // The day status of a day with facts, from the stored snapshot.
    final status = await DayStatusRepository(
      database: db,
      clock: clock,
      snapshots: snapshots,
      facts: DayFactsSource(db),
    ).statusFor(LocalDate(2026, 4, 7));
    expect(status, isNotNull);
    expect(status!.goals, isNotEmpty);
    expect(status.isActive, isTrue, reason: 'facts of that day are counted');

    // XP: the stored awards of v0.1.0 are the sum the projector reports.
    final stored = await db
        .customSelect('SELECT SUM(points) AS s FROM xp_awards')
        .getSingle();
    expect(await XpProjector(db).totalXp(), stored.read<int>('s'));
    expect(stored.read<int>('s'), greaterThan(0));
  });

  test('commands work on the migrated file and write the defaults of schema 2 (BS-98)', () async {
    await writeV1DatabaseFile(databaseFile.path);
    final runtime = await start();
    addTearDown(runtime.dispose);
    final db = runtime.database;
    final clock = FakeClock.at('2026-04-08T08:00:00Z');
    final container = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(clock),
        idGeneratorProvider.overrideWithValue(SequentialIdGenerator(200000)),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(stepsRepositoryProvider)
        .setSteps(
          commandId: container.read(idGeneratorProvider).newId(),
          date: LocalDate(2026, 4, 8),
          steps: 4321,
        );
    await container
        .read(taskRepositoryProvider)
        .create(
          commandId: container.read(idGeneratorProvider).newId(),
          draft: const TaskDraft(title: 'Nach dem Update angelegt'),
        );

    final today =
        await (db.select(db.stepDays)
              ..where((s) => s.localDate.equalsValue(LocalDate(2026, 4, 8))))
            .getSingle();
    expect(today.steps, 4321);
    expect(today.source, 'manual', reason: 'the default of schema 2');
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.title.equals('Nach dem Update angelegt'))).getSingle();
    expect(task.reminderAtUtc, isNull);
    expect(task.reminderLocalDate, isNull);
    expect(task.reminderTimezoneId, isNull);
  });

  test(
    'a second start of the migrated file changes nothing (AT02, BS-98)',
    () async {
      await writeV1DatabaseFile(databaseFile.path);
      final fixture = await fixtureContent();

      final first = await start();
      final afterFirst = await rowsOfAllTables(first.database, fixture.columns);
      final schemaFirst = await schemaLines(first.database);
      await first.dispose();

      final second = await start();
      addTearDown(second.dispose);
      expect(await userVersion(second.database), 2);
      expect(
        await rowsOfAllTables(second.database, fixture.columns),
        afterFirst,
      );
      expect(await schemaLines(second.database), schemaFirst);
      expect(afterFirst, fixture.rows);
    },
  );

  test(
    'a file of a newer schema is not opened and not changed (BS-98)',
    () async {
      await writeV1DatabaseFile(databaseFile.path);
      // Another app version of the future raised the version of the file.
      final raw = V1FixtureDatabase(NativeDatabase(databaseFile));
      await raw.customStatement('PRAGMA user_version = 3');
      await raw.close();
      final before = databaseFile.readAsBytesSync();

      await expectLater(start(), throwsA(isA<MigrationFailure>()));

      expect(databaseFile.existsSync(), isTrue, reason: 'nothing is deleted');
      expect(
        databaseFile.readAsBytesSync(),
        before,
        reason: 'nothing is changed',
      );
    },
  );
}

final class _FixedZone implements TimeZoneSource {
  _FixedZone(this.id);

  final String id;

  @override
  Future<String> currentZoneId() async => id;
}
