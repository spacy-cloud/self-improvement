import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_service.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/testing/in_memory_backup_adapters.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../core/backup/support/backup_fixtures.dart';
import '../support/synthetic_records.dart';

/// Demo data for the manual first tests (not a behaviour test of its own).
///
/// Builds 90 days of synthetic records over all modules, exports them with the
/// app's own exporter to `build/demo-backup/demo-daten-90-tage.json` and proves
/// that this very file can be imported into an empty app (the real
/// `BackupService` with the real validator and importer). On a device the file
/// is imported through "Profil, Einstellungen, Daten, Import", so the demo data
/// also exercises the restore path.
///
/// The days end on the current date (or on `DEMO_TODAY=YYYY-MM-DD`), so the
/// analysis periods are filled when the file is imported on the day it was made.
const _tables = <String>[
  'weight_entries',
  'step_days',
  'water_entries',
  'meal_entries',
  'workout_entries',
  'focus_sessions',
  'tasks',
  'habits',
  'habit_checks',
  'goal_versions',
  'module_status_history',
  'daily_goal_snapshots',
];

LocalDate _demoToday() {
  final fixed = Platform.environment['DEMO_TODAY'];
  if (fixed != null && fixed.isNotEmpty) {
    return LocalDate.parse(fixed);
  }
  final now = DateTime.now();
  return LocalDate(now.year, now.month, now.day);
}

void main() {
  test('the 90 day demo backup is valid and can be imported', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final today = _demoToday();
    final first = today.addDays(-89);
    final source = await DataHarness.create(
      nowIso: '${today.toIso()}T10:00:00Z',
      realProjection: true,
    );
    final target = await DataHarness.create(
      nowIso: '${today.toIso()}T10:00:00Z',
      realProjection: true,
    );
    addTearDown(() async {
      await source.dispose();
      await target.dispose();
    });

    await source.seedOnboarded(startedOn: first);
    await (source.database.update(source.database.profile)).write(
      ProfileCompanion(
        displayName: const Value('Demo'),
        heightCm: const Value(178),
        ageYears: const Value(28),
        startWeightGrams: const Value(78000),
        targetWeightGrams: const Value(72000),
      ),
    );
    final records = await insertSyntheticRecords(
      source.database,
      source.ids,
      first,
      today,
      data: const SyntheticData(
        habitTitles: <String>['Lesen', 'Dehnen', 'Spazieren'],
        mealNames: <String>['Frühstück', 'Mittagessen', 'Abendessen'],
        varied: true,
      ),
    );
    expect(records, greaterThan(500));
    await source.projections.syncDays(<LocalDate>{
      for (var d = first; !d.isAfter(today); d = d.addDays(1)) d,
    });

    final backup = await BackupExporter(
      database: source.database,
      clock: source.clock,
    ).export();
    expect(
      backup.isRestorable,
      isTrue,
      reason: backup.importCheck.problems.take(3).join('; '),
    );

    final directory = Directory('build/demo-backup')
      ..createSync(recursive: true);
    File('${directory.path}/demo-daten-90-tage.json')
        .writeAsBytesSync(backup.bytes);

    // Import into an empty app, like on a fresh install.
    final service = BackupService(
      database: target.database,
      clock: target.clock,
      files: InMemoryBackupFileGateway(),
      projections: target.projections,
    );
    final prepared = await service.prepareImport(backup.bytes);
    expect(prepared, isA<ImportReady>());
    final outcome = await service.confirmImport(
      (prepared as ImportReady).prepared,
    );
    expect(outcome.recordCount, greaterThan(records));

    final original = await backupTablesDump(source.database);
    final imported = await backupTablesDump(target.database);
    for (final table in _tables) {
      expect(imported[table], original[table], reason: table);
    }
    // The file is plain JSON with the documented marker.
    final json = jsonDecode(utf8.decode(backup.bytes)) as Map<String, Object?>;
    expect(json.keys, contains('format'));
  });
}
