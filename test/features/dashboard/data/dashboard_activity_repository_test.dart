import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/data/dashboard_activity_repository.dart';

import '../../../support/db_fixtures.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late AppDatabase db;
  late DashboardActivityRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    await harness.seedOnboarded();
    db = harness.database;
    repository = DashboardActivityRepository(db);
  });
  tearDown(() => harness.dispose());

  final inserts = <String, Future<void> Function(AppDatabase)>{
    'water_entries': (db) => db.into(db.waterEntries).insert(waterRow()),
    'weight_entries': (db) => db.into(db.weightEntries).insert(weightRow()),
    'step_days': (db) => db.into(db.stepDays).insert(stepRow()),
    'meal_entries': (db) => db.into(db.mealEntries).insert(mealRow()),
    'workout_entries': (db) => db.into(db.workoutEntries).insert(workoutRow()),
    'focus_sessions': (db) => db.into(db.focusSessions).insert(focusRow()),
    'tasks': (db) => db.into(db.tasks).insert(taskRow()),
    'habits': (db) => db.into(db.habits).insert(habitRow()),
  };

  test('a fresh installation has no entry (AT01)', () async {
    expect(await repository.hasAnyEntry(), isFalse);
  });

  for (final entry in inserts.entries) {
    test('a record in ${entry.key} counts, once deleted it does not', () async {
      await entry.value(db);
      expect(await repository.hasAnyEntry(), isTrue);
      await db.customStatement('UPDATE ${entry.key} SET deleted_at_utc = 1000');
      expect(await repository.hasAnyEntry(), isFalse);
    });
  }

  test('a discarded focus session is not an entry', () async {
    await db.into(db.focusSessions).insert(focusRow(status: 'discarded'));
    expect(await repository.hasAnyEntry(), isFalse);
    await db.into(db.focusSessions).insert(focusRow(id: 'f2'));
    expect(await repository.hasAnyEntry(), isTrue);
  });

  test('the stream follows inserts and deletions', () async {
    final seen = <bool>[];
    final subscription = repository.watchHasAnyEntry().listen(seen.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    await db.into(db.weightEntries).insert(weightRow());
    await pumpEventQueue();
    await db.customUpdate(
      'UPDATE weight_entries SET deleted_at_utc = 1',
      updates: {db.weightEntries},
    );
    await pumpEventQueue();
    expect(seen, [false, true, false]);
  });
}
