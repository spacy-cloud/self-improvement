import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/dto/body_nutrition_dtos.dart';
import 'package:self_improvement/core/backup/dto/core_dtos.dart';
import 'package:self_improvement/core/backup/dto/focus_dtos.dart';
import 'package:self_improvement/core/backup/dto/task_dtos.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/backup_fixtures.dart';

/// Parses a record with the strict `fromJson` of its DTO and serialises it
/// again.
typedef RoundTrip = Map<String, Object?> Function(Map<String, Object?> json);

final Map<BackupTable, RoundTrip> roundTrips = {
  BackupTable.profile: (j) => ProfileDto.fromJson(j).toJson(),
  BackupTable.appSettings: (j) => AppSettingsDto.fromJson(j).toJson(),
  BackupTable.moduleStatusHistory: (j) => ModuleStatusDto.fromJson(j).toJson(),
  BackupTable.dashboardCards: (j) => DashboardCardDto.fromJson(j).toJson(),
  BackupTable.goalVersions: (j) => GoalVersionDto.fromJson(j).toJson(),
  BackupTable.dailyGoalSnapshots: (j) =>
      DailyGoalSnapshotDto.fromJson(j).toJson(),
  BackupTable.weightEntries: (j) => WeightEntryDto.fromJson(j).toJson(),
  BackupTable.stepDays: (j) => StepDayDto.fromJson(j).toJson(),
  BackupTable.waterEntries: (j) => WaterEntryDto.fromJson(j).toJson(),
  BackupTable.mealEntries: (j) => MealEntryDto.fromJson(j).toJson(),
  BackupTable.focusSessions: (j) => FocusSessionDto.fromJson(j).toJson(),
  BackupTable.workoutEntries: (j) => WorkoutEntryDto.fromJson(j).toJson(),
  BackupTable.tasks: (j) => TaskDto.fromJson(j).toJson(),
  BackupTable.habits: (j) => HabitDto.fromJson(j).toJson(),
  BackupTable.habitChecks: (j) => HabitCheckDto.fromJson(j).toJson(),
  BackupTable.reminderRules: (j) => ReminderRuleDto.fromJson(j).toJson(),
};

/// The records of [table] in the backup [json].
List<Map<String, Object?>> recordsOf(
  Map<String, Object?> json,
  BackupTable table,
) {
  final data = json['data']! as Map<String, Object?>;
  final section = data[table.key];
  if (table.isSingleton) {
    return [section! as Map<String, Object?>];
  }
  return (section! as List<Object?>).cast<Map<String, Object?>>();
}

/// The problems of the [BackupFormatException] [action] throws.
List<ImportProblem> problemsOf(void Function() action) {
  try {
    action();
  } on BackupFormatException catch (e) {
    return e.report.problems;
  }
  fail('expected a BackupFormatException');
}

Map<String, Object?> copyOf(Map<String, Object?> record) =>
    Map<String, Object?>.of(record);

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Map<String, Object?> backup;
  setUpAll(() async => backup = await richBackupJson());

  group('every DTO round trips every record of a real export', () {
    for (final table in BackupTable.values) {
      test(table.key, () {
        final records = recordsOf(backup, table);
        expect(records, isNotEmpty, reason: 'the rich fixture covers it');
        for (final record in records) {
          expect(roundTrips[table]!(record), equals(record));
        }
      });
    }
  });

  group('strict fromJson', () {
    for (final table in BackupTable.values) {
      test('${table.key}: an unknown field is rejected, without echo', () {
        final record = copyOf(recordsOf(backup, table).first)
          ..['secret_nickname'] = 1;
        final problems = problemsOf(() => roundTrips[table]!(record));
        expect(problems, hasLength(1));
        expect(problems.single.message, 'Unbekanntes Zusatzfeld');
        expect(problems.single.displayText, isNot(contains('secret_nickname')));
      });

      test('${table.key}: every missing field is reported by name', () {
        final first = recordsOf(backup, table).first;
        for (final key in first.keys) {
          final record = copyOf(first)..remove(key);
          final problems = problemsOf(() => roundTrips[table]!(record));
          expect(
            problems.map((p) => p.field),
            contains(key),
            reason: 'removing $key',
          );
          expect(
            problems.first.message,
            startsWith('Pflichtfeld fehlt'),
            reason: 'removing $key',
          );
        }
      });

      test('${table.key}: a value of the wrong JSON type is rejected', () {
        final first = recordsOf(backup, table).first;
        for (final entry in first.entries) {
          final Object? wrong = switch (entry.value) {
            bool() => 1,
            int() => '1',
            String() => 7,
            List<Object?>() => 'text',
            _ => null,
          };
          if (wrong == null) {
            continue;
          }
          final record = copyOf(first)..[entry.key] = wrong;
          final problems = problemsOf(() => roundTrips[table]!(record));
          expect(
            problems.map((p) => p.field),
            contains(entry.key),
            reason: 'wrong type for ${entry.key}',
          );
        }
      });
    }

    test('a double that looks like an integer is not an integer', () {
      final record = copyOf(recordsOf(backup, BackupTable.weightEntries).first)
        ..['weight_grams'] = 71500.0;
      final problems = problemsOf(() => WeightEntryDto.fromJson(record));
      expect(problems.single.field, 'weight_grams');
      expect(problems.single.message, contains('Datentyp'));
    });

    test('several problems of one record are all reported', () {
      final record = copyOf(recordsOf(backup, BackupTable.weightEntries).first)
        ..['weight_grams'] = 19900
        ..['local_date'] = '2026-02-30'
        ..['extra'] = true;
      final problems = problemsOf(() => WeightEntryDto.fromJson(record));
      expect(problems.map((p) => p.field), [
        'weight_grams',
        'local_date',
        null,
      ]);
      expect(problems.map((p) => p.location).toSet(), {'weight_entries[0]'});
    });

    test('messages are German and contain no value of the file', () {
      final record = copyOf(recordsOf(backup, BackupTable.weightEntries).first)
        ..['note'] = 'Geheimnis ${'x' * 600}'
        ..['timezone_id'] = 'Geheimstadt/Niemandsland';
      final problems = problemsOf(() => WeightEntryDto.fromJson(record));
      expect(problems, hasLength(2));
      for (final problem in problems) {
        expect(problem.displayText, isNot(contains('Geheim')));
        expect(problem.displayText, matches(RegExp('[A-Za-zäöüß]')));
      }
      expect(problems.first.displayText, startsWith('weight_entries[0]: '));
    });
  });

  group('schema parity (the DTOs mirror the drift schema)', () {
    late DataHarness harness;
    setUp(() async => harness = await DataHarness.create());
    tearDown(() => harness.dispose());

    Future<List<QueryRow>> columns(String table) =>
        harness.database.customSelect("PRAGMA table_info('$table')").get();

    for (final table in BackupTable.values) {
      test(
        '${table.key}: fields are exactly the columns (without deleted_at_utc)',
        () async {
          final names = (await columns(table.key))
              .map((r) => r.read<String>('name'))
              .where((n) => n != 'deleted_at_utc')
              .toList();
          expect(
            recordsOf(backup, table).first.keys.toList()..sort(),
            equals(names..sort()),
          );
        },
      );

      test(
        '${table.key}: null is allowed exactly for nullable columns',
        () async {
          final nullableByColumn = {
            for (final r in await columns(table.key))
              r.read<String>('name'): r.read<int>('notnull') == 0,
          };
          final first = recordsOf(backup, table).first;
          for (final key in first.keys) {
            // The paired step fields and the completion triple are covered by
            // their own tests; nulling one alone violates a pairing rule.
            final isPaired = const {
              'reached_goal_eligible',
              'xp_goal_target_steps',
              'completed_at_utc',
              'completed_local_date',
              'completion_eligibility',
              'segment_started_at_utc',
            }.contains(key);
            if (isPaired || first[key] == null) {
              continue;
            }
            final record = copyOf(first)..[key] = null;
            if (nullableByColumn[key]!) {
              expect(
                () => roundTrips[table]!(record),
                returnsNormally,
                reason: '$key is nullable in the schema',
              );
            } else {
              expect(
                problemsOf(() => roundTrips[table]!(record))
                    .map((p) => p.field),
                contains(key),
                reason: '$key is NOT NULL in the schema',
              );
            }
          }
        },
      );
    }

    test(
      'soft-delete columns exist exactly where rows can be deleted',
      () async {
        // The DTOs have no deleted_at_utc: soft-deleted rows are not exported.
        for (final table in BackupTable.values) {
          final hasDeleted = (await columns(table.key))
              .any((r) => r.read<String>('name') == 'deleted_at_utc');
          final first = recordsOf(backup, table).first;
          expect(first.containsKey('deleted_at_utc'), isFalse);
          if (hasDeleted) {
            expect(
              () =>
                  roundTrips[table]!(copyOf(first)..['deleted_at_utc'] = null),
              throwsA(isA<BackupFormatException>()),
              reason: '${table.key} must reject the field as unknown',
            );
          }
        }
      },
    );
  });

  group('JSON arrays are real arrays of strings', () {
    test('motivation_goals, tags_json and muscle_groups', () {
      final profile = recordsOf(backup, BackupTable.profile).single;
      expect(profile['motivation_goals'], ['move_more', 'build_habits']);
      final tasks = recordsOf(backup, BackupTable.tasks);
      expect(tasks.first['tags_json'], ['Finanzen', 'Dringend']);
      final workouts = recordsOf(backup, BackupTable.workoutEntries);
      expect(workouts.first['muscle_groups'], [
        'chest',
        'shoulders',
        'triceps',
      ]);
      expect(workouts.last['muscle_groups'], isEmpty);
    });

    test('a JSON string that contains an array is not an array', () {
      final record = copyOf(recordsOf(backup, BackupTable.tasks).first)
        ..['tags_json'] = '["a"]';
      expect(
        problemsOf(() => TaskDto.fromJson(record)).single.field,
        'tags_json',
      );
    });
  });

  group('DTOs convert to and from database rows without loss', () {
    test('toCompanion restores the row a DTO was read from', () async {
      final harness = await DataHarness.create();
      addTearDown(harness.dispose);
      await populateRichDatabase(harness.database);
      final db = harness.database;
      final row = await (db.select(
        db.weightEntries,
      )..where((t) => t.id.equals(Ids.weightFirst))).getSingle();

      final companion = WeightEntryDto.fromRow(row).toCompanion();
      await db.delete(db.weightEntries).go();
      await db.into(db.weightEntries).insert(companion);

      final restored = await (db.select(
        db.weightEntries,
      )..where((t) => t.id.equals(Ids.weightFirst))).getSingle();
      expect(restored, row);
    });
  });

  group('FocusSessionDto.exportedAt (running session becomes paused)', () {
    FocusSessionDto session({
      String status = 'running',
      int planned = 1500,
      int accumulated = 100,
      DateTime? segmentStart,
    }) => FocusSessionDto(
      id: uuid(1),
      category: 'reading',
      plannedSeconds: planned,
      accumulatedSeconds: accumulated,
      segmentStartedAtUtc: status == 'running'
          ? (segmentStart ?? DateTime.utc(2026, 3, 2, 8))
          : null,
      startedAtUtc: DateTime.utc(2026, 3, 2, 7, 50),
      timezoneId: berlin,
      status: status,
      gamificationEligible: false,
      createdAtUtc: DateTime.utc(2026, 3, 2, 7, 50),
      updatedAtUtc: DateTime.utc(2026, 3, 2, 8),
      rowVersion: 4,
    );

    final start = DateTime.utc(2026, 3, 2, 8);

    test('adds the seconds of the running segment to the accumulated time', () {
      final exported = session().exportedAt(
        start.add(const Duration(minutes: 5)),
      );
      expect(exported.status, 'paused');
      expect(exported.accumulatedSeconds, 400);
      expect(exported.segmentStartedAtUtc, isNull);
      expect(exported.plannedSeconds, 1500);
    });

    test('floors partial seconds', () {
      final exported = session(
        accumulated: 0,
      ).exportedAt(start.add(const Duration(seconds: 59, milliseconds: 999)));
      expect(exported.accumulatedSeconds, 59);
    });

    test('exactly at the start nothing is added', () {
      expect(session().exportedAt(start).accumulatedSeconds, 100);
    });

    test('is clamped to the planned duration', () {
      final exported = session().exportedAt(start.add(const Duration(days: 3)));
      expect(exported.accumulatedSeconds, 1500);
      expect(exported.status, 'paused');
    });

    test('lands exactly on the plan without exceeding it', () {
      final exported = session().exportedAt(
        start.add(const Duration(seconds: 1400)),
      );
      expect(exported.accumulatedSeconds, 1500);
    });

    test('a clock set backwards counts as zero elapsed time', () {
      final exported = session().exportedAt(
        start.subtract(const Duration(hours: 2)),
      );
      expect(exported.accumulatedSeconds, 100);
      expect(exported.status, 'paused');
    });

    test('keeps identity, metadata and version of the row', () {
      final running = session();
      final exported = running.exportedAt(
        start.add(const Duration(minutes: 1)),
      );
      expect(exported.id, running.id);
      expect(exported.updatedAtUtc, running.updatedAtUtc);
      expect(exported.rowVersion, 4);
      expect(exported.startedAtUtc, running.startedAtUtc);
    });

    for (final status in const [
      'paused',
      'awaiting_confirmation',
      'completed',
      'discarded',
    ]) {
      test('a $status session is returned unchanged', () {
        final dto = session(status: status);
        expect(
          identical(dto.exportedAt(start.add(const Duration(hours: 1))), dto),
          isTrue,
        );
      });
    }

    test('the exported session passes the strict contract', () {
      final json = session()
          .exportedAt(start.add(const Duration(minutes: 5)))
          .toJson();
      expect(FocusSessionDto.fromJson(json).status, 'paused');
    });
  });

  group('DTO details', () {
    test('goal keys are goal types or habit:<uuid>', () {
      for (final key in const [
        'water',
        'steps',
        'weight_entry',
        'focus_minutes',
        'task_completion',
        'workout_weekly',
      ]) {
        expect(DailyGoalSnapshotDto.isKnownGoalKey(key), isTrue, reason: key);
      }
      expect(DailyGoalSnapshotDto.isKnownGoalKey('habit:${uuid(5)}'), isTrue);
      for (final key in const [
        'sleep',
        'habit:',
        'habit:not-a-uuid',
        'Water',
        '',
      ]) {
        expect(DailyGoalSnapshotDto.isKnownGoalKey(key), isFalse, reason: key);
      }
    });

    test('LocalDate values keep their civil date', () {
      final dto = ModuleStatusDto.fromJson({
        'id': uuid(1),
        'module_id': 'body',
        'effective_at_utc': '2026-03-31T22:30:00.000Z',
        'local_date': '2026-04-01',
        'enabled': true,
      });
      expect(dto.localDate, LocalDate(2026, 4, 1));
      expect(dto.effectiveAtUtc, DateTime.utc(2026, 3, 31, 22, 30));
    });
  });
}
