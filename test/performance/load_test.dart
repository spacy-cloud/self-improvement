@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/db_fixtures.dart';

/// Load test with synthetic data (BS-75, AT36/Q01/A01): more than ten thousand
/// records over three years are written straight into an in-memory SQLite
/// database, the shared projections are rebuilt once (the import scenario) and
/// the everyday operations are timed at that size.
///
/// The thresholds are deliberately generous regression guards for a CI runner;
/// the planning targets of the ticket (start about 3 s, simple commit 300 ms,
/// scrolling at 60 Hz) are judged on a device and are documented in the test
/// report together with the measured numbers. This host run is NOT a device
/// measurement.
void main() {
  final results = <String, num>{};
  late DataHarness harness;
  late ProviderContainer container;
  final today = LocalDate(2026, 10, 3);
  final firstDay = LocalDate(2023, 10, 4);
  var recordCount = 0;

  void log(String text) {
    // ignore: avoid_print
    print('LOAD $text');
  }

  Future<T> timed<T>(String name, Future<T> Function() action) async {
    final watch = Stopwatch()..start();
    final value = await action();
    watch.stop();
    results[name] = watch.elapsedMilliseconds;
    log('$name: ${watch.elapsedMilliseconds} ms');
    return value;
  }

  /// Times the first value of a provider; -1 marks "no value within 40 s".
  Future<void> firstValue(String name, Future<Object?> Function() read) async {
    final watch = Stopwatch()..start();
    try {
      await read().timeout(const Duration(seconds: 40));
      results[name] = watch.elapsedMilliseconds;
    } on TimeoutException {
      results[name] = -1;
    }
    log('$name: ${results[name]} ms');
  }

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: firstDay);
    container = harness.createContainer();
    recordCount = await timed(
      'insert_synthetic_records_ms',
      () => _insertSynthetic(harness.database, firstDay, today),
    );
    results['records'] = recordCount;
  });

  tearDownAll(() async {
    await harness.dispose();
    File('build/load-test-results.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'note':
              'Host run with an in-memory SQLite database; not a device '
              'measurement.',
          'results': results,
        }),
      );
  });

  test('the fixture holds more than ten thousand records over three years', () {
    expect(recordCount, greaterThanOrEqualTo(10000));
  });

  test(
    'a full rebuild of the projections over three years stays usable',
    () async {
      final days = {
        for (var d = firstDay; !d.isAfter(today); d = d.addDays(1)) d,
      };
      await timed(
        'projection_rebuild_all_days_ms',
        () => harness.projections.syncDays(days),
      );
      expect(results['projection_rebuild_all_days_ms'], lessThan(120000));
    },
  );

  test('a simple command commits fast at this size (target 300 ms)', () async {
    container.listen(weightEntriesProvider, (_, _) {});
    await container.read(weightEntriesProvider.future);
    final repository = container.read(weightRepositoryProvider);
    final times = <int>[];
    for (var i = 0; i < 20; i++) {
      harness.clock.advance(const Duration(minutes: 1));
      final watch = Stopwatch()..start();
      await repository.create(
        commandId: harness.ids.newId(),
        draft: WeightDraft(
          weightGrams: 75000 + i * 100,
          occurredAtUtc: harness.clock.nowUtc(),
        ),
      );
      watch.stop();
      times.add(watch.elapsedMilliseconds);
    }
    times.sort();
    results['weight_commit_median_ms'] = times[times.length ~/ 2];
    results['weight_commit_max_ms'] = times.last;
    log(
      'weight commit median ${times[times.length ~/ 2]} ms, '
      'max ${times.last} ms',
    );
    expect(times[times.length ~/ 2], lessThan(300));
    expect(times.last, lessThan(2000));
  });

  test(
    'the shared live projections answer quickly (start of the app)',
    () async {
      container
        ..listen(totalXpProvider, (_, _) {})
        ..listen(todayStatusProvider, (_, _) {})
        ..listen(stepsHistoryProvider(90), (_, _) {})
        ..listen(analysisReportProvider, (_, _) {})
        ..listen(streakProvider, (_, _) {});
      await firstValue(
        'first_total_xp_ms',
        () => container.read(totalXpProvider.future),
      );
      await firstValue(
        'first_today_status_ms',
        () => container.read(todayStatusProvider.future),
      );
      await firstValue(
        'first_steps_history_90_ms',
        () => container.read(stepsHistoryProvider(90).future),
      );
      await firstValue(
        'first_analysis_report_ms',
        () => container.read(analysisReportProvider.future),
      );
      await firstValue(
        'first_streak_ms',
        () => container.read(streakProvider.future),
      );
      for (final key in [
        'first_total_xp_ms',
        'first_today_status_ms',
        'first_steps_history_90_ms',
        'first_analysis_report_ms',
        'first_streak_ms',
      ]) {
        expect(results[key], inInclusiveRange(0, 5000), reason: key);
      }
    },
  );

  test('the screens read correct data at this size', () async {
    final entries = await container.read(weightEntriesProvider.future);
    expect(entries.length, greaterThan(900));
    final history = await container.read(stepsHistoryProvider(90).future);
    expect(history, hasLength(90));
    expect(history.where((d) => d.recorded).length, greaterThan(50));
  });

  test('a full backup of the records stays below the file limit', () async {
    final exporter = BackupExporter(
      database: harness.database,
      clock: harness.clock,
    );
    final backup = await timed(
      'backup_export_and_selfcheck_ms',
      exporter.export,
    );
    results['backup_bytes'] = backup.bytes.length;
    log('backup size: ${backup.bytes.length} bytes');
    expect(backup.bytes.length, lessThan(10 * 1024 * 1024));
  });
}

/// Writes deterministic synthetic records and returns how many rows were
/// inserted.
Future<int> _insertSynthetic(
  AppDatabase database,
  LocalDate first,
  LocalDate last,
) async {
  final random = math.Random(42);
  var count = 0;
  var id = 0;
  String next(String prefix) => 'load-$prefix-${id++}';
  final days = <LocalDate>[
    for (var d = first; !d.isAfter(last); d = d.addDays(1)) d,
  ];
  DateTime at(LocalDate date, int hour) =>
      DateTime.utc(date.year, date.month, date.day, hour);

  await database.batch((batch) {
    for (var h = 0; h < 3; h++) {
      batch.insert(
        database.habits,
        habitRow(
          id: 'load-habit-$h',
          title: 'Gewohnheit ${h + 1}',
        ).copyWith(startedLocalDate: Value(first)),
      );
      count++;
    }
    for (final day in days) {
      if (random.nextInt(10) != 0) {
        batch.insert(
          database.weightEntries,
          weightRow(
            id: next('w'),
            grams:
                78000 -
                ((day.year * 365 + day.month * 30 + day.day) % 90) * 100,
            at: at(day, 6),
          ).copyWith(localDate: Value(day)),
        );
        count++;
      }
      if (random.nextInt(100) < 85) {
        batch.insert(
          database.stepDays,
          stepRow(
            id: next('s'),
            steps: 2000 + random.nextInt(14000),
            date: day,
          ),
        );
        count++;
      }
      if (random.nextInt(100) < 80) {
        for (var i = 0; i < 4; i++) {
          batch.insert(
            database.waterEntries,
            waterRow(id: next('wa'), ml: i == 0 ? 500 : 250).copyWith(
              occurredAtUtc: Value(at(day, 8 + i * 3)),
              localDate: Value(day),
            ),
          );
          count++;
        }
      }
      if (random.nextInt(100) < 60) {
        for (var i = 0; i < 3; i++) {
          batch.insert(
            database.mealEntries,
            mealRow(id: next('m'), name: 'Mahlzeit ${i + 1}').copyWith(
              occurredAtUtc: Value(at(day, 7 + i * 5)),
              localDate: Value(day),
            ),
          );
          count++;
        }
      }
      if (day.weekday == 2 || day.weekday == 5) {
        batch.insert(
          database.workoutEntries,
          workoutRow(
            id: next('wo'),
            minutes: 30 + random.nextInt(60),
          ).copyWith(occurredAtUtc: Value(at(day, 17)), localDate: Value(day)),
        );
        count++;
      }
      if (random.nextInt(100) < 50) {
        batch.insert(
          database.focusSessions,
          focusRow(
            id: next('f'),
            status: 'completed',
            accumulated: 1500,
            completedDate: Value(day),
          ).copyWith(startedAtUtc: Value(at(day, 9))),
        );
        count++;
      }
      if (random.nextInt(100) < 40) {
        batch.insert(
          database.tasks,
          taskRow(
            id: next('t'),
            title: 'Aufgabe $count',
            completedAt: Value(at(day, 12)),
            completedDate: Value(day),
            eligibility: const Value(true),
          ).copyWith(createdAtUtc: Value(at(day, 8))),
        );
        count++;
      }
      for (var h = 0; h < 3; h++) {
        if (random.nextInt(100) < 55) {
          batch.insert(
            database.habitChecks,
            habitCheckRow(id: next('hc'), habitId: 'load-habit-$h', date: day),
          );
          count++;
        }
      }
    }
  });
  return count;
}
