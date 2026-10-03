import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_importer.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/backup_fixtures.dart';

/// Performance sanity (no timing assertions, which would flake on busy
/// machines): large synthetic backups must validate, import and export
/// without hanging. The measured times are printed; a generous timeout only
/// guards against a hang or a quadratic regression.
void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  /// A base backup plus synthetic records so that the file has [total]
  /// records in realistic proportions.
  Future<Map<String, Object?>> syntheticBackup(int total) async {
    final root = await richBackupJson();
    final data = root['data']! as Map<String, Object?>;
    List<Object?> list(String table) => data[table]! as List<Object?>;
    Map<String, Object?> template(String table) =>
        Map<String, Object?>.of(list(table).first! as Map<String, Object?>);

    final present =
        2 +
        data.values.whereType<List<Object?>>().fold<int>(
          0,
          (a, l) => a + l.length,
        );
    final extra = total - present;
    // Proportions of a long-time user.
    final shares = <String, double>{
      'weight_entries': 0.30,
      'water_entries': 0.30,
      'meal_entries': 0.15,
      'step_days': 0.08,
      'tasks': 0.07,
      'habit_checks': 0.04,
      'workout_entries': 0.04,
      'focus_sessions': 0.02,
    };
    final start = DateTime.utc(2021, 1, 1, 6);
    var serial = 0x1000000;
    var remaining = extra;
    for (final (index, entry) in shares.entries.indexed) {
      // The last category takes the rounding remainder: the total is exact.
      final isLast = index == shares.length - 1;
      final count = isLast ? remaining : (extra * entry.value).round();
      remaining -= count;
      final records = list(entry.key);
      final base = template(entry.key);
      for (var i = 0; i < count; i++) {
        final day = LocalDate(2021, 1, 1).addDays(i % 1500);
        final instant = start.add(Duration(minutes: i * 7));
        final record = Map<String, Object?>.of(base)..['id'] = uuid(serial++);
        switch (entry.key) {
          case 'weight_entries':
            record['occurred_at_utc'] = BackupValues.formatInstant(instant);
            record['local_date'] = day.toIso();
          case 'water_entries':
          case 'meal_entries':
          case 'workout_entries':
            record['occurred_at_utc'] = BackupValues.formatInstant(instant);
            record['local_date'] = day.toIso();
          case 'step_days':
            record['local_date'] = LocalDate(2000, 1, 1).addDays(i).toIso();
          case 'tasks':
            record['title'] = 'Aufgabe $i';
          case 'habit_checks':
            record['habit_id'] = Ids.habitReading;
            record['local_date'] = LocalDate(2000, 1, 1).addDays(i).toIso();
          case 'focus_sessions':
            // Completed sessions: no open one besides the fixture's.
            record
              ..['status'] = 'completed'
              ..['completed_local_date'] = day.toIso();
        }
        records.add(record);
      }
    }
    return root;
  }

  Future<void> measure(String label, Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    await action();
    debugPrint('PERF $label: ${watch.elapsedMilliseconds} ms');
  }

  test('20,000 records: encode, validate, import, export', () async {
    late Map<String, Object?> root;
    late Uint8List bytes;
    await measure('build 20,000 synthetic records', () async {
      root = await syntheticBackup(20000);
    });
    await measure('encode to JSON', () async {
      bytes = Uint8List.fromList(utf8.encode(jsonEncode(root)));
    });
    debugPrint(
      'PERF file size: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MiB',
    );
    expect(bytes.length, lessThan(BackupFormat.maxFileBytes));

    late BackupValidationResult result;
    await measure('validateBytes (decode + parse + relations)', () async {
      result = const BackupValidator().validateBytes(bytes);
    });
    expect(result.report.problems, isEmpty);
    final document = result.document!;
    expect(document.data.recordCount, closeTo(20000, 5));

    final target = await DataHarness.create();
    addTearDown(target.dispose);
    final projection = RecordingProjectionSynchronizer();
    late ImportReplaceResult imported;
    await measure('replaceAll (delete, insert, projection call)', () async {
      imported = await BackupImporter(
        database: target.database,
        projections: projection,
      ).replaceAll(document);
    });
    expect(imported.recordCount, document.data.recordCount);
    expect(projection.syncs, hasLength(1));
    debugPrint('PERF days with facts: ${imported.recomputedDays}');

    late ExportedBackup exported;
    await measure('export (read, encode, self-check)', () async {
      exported = await BackupExporter(
        database: target.database,
        clock: target.clock,
      ).export();
    });
    expect(exported.isRestorable, isTrue);
    expect(exported.recordCount, document.data.recordCount);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('50,000 records (the limit): validate and import', () async {
    late Map<String, Object?> root;
    await measure('build 50,000 synthetic records', () async {
      root = await syntheticBackup(BackupFormat.maxRecords);
    });
    late BackupValidationResult result;
    await measure('validateDecoded', () async {
      result = const BackupValidator().validateDecoded(root);
    });
    expect(result.report.problems, isEmpty);
    expect(result.document!.data.recordCount, BackupFormat.maxRecords);

    final target = await DataHarness.create();
    addTearDown(target.dispose);
    await measure('replaceAll', () async {
      await BackupImporter(
        database: target.database,
        projections: RecordingProjectionSynchronizer(),
      ).replaceAll(result.document!);
    });
    expect(
      (await target.database.select(target.database.weightEntries).get())
          .length,
      result.document!.data.weightEntries.length,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
