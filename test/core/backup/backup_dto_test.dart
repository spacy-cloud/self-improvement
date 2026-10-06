import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
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
  BackupTable.workoutDayMarks: (j) => WorkoutDayMarkDto.fromJson(j).toJson(),
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
              'reminder_at_utc',
              'reminder_local_date',
              'reminder_timezone_id',
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

  group('BackupDocument.fromJson', () {
    test('round trips a real export, key order included', () {
      final document = BackupDocument.fromJson(jsonCopy(backup));
      final json = document.toJson();
      expect(json, equals(backup));
      expect(json.keys.toList(), backup.keys.toList());
      expect(
        (json['data']! as Map<String, Object?>).keys.toList(),
        (backup['data']! as Map<String, Object?>).keys.toList(),
      );
      expect(document.exportedAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(document.appVersion, '1.0.0');
    });

    test('lists every record-level problem of the whole file', () {
      final root = jsonCopy(backup);
      final data = root['data']! as Map<String, Object?>;
      ((data['weight_entries']! as List<Object?>)[1]!
              as Map<String, Object?>)['weight_grams'] =
          5;
      ((data['water_entries']! as List<Object?>)[0]!
              as Map<String, Object?>)['amount_ml'] =
          1;
      final problems = problemsOf(() => BackupDocument.fromJson(root));
      expect(problems.map((p) => p.location), [
        'weight_entries[1]',
        'water_entries[0]',
      ]);
    });

    test('rejects a wrong format marker and a wrong version', () {
      expect(
        problemsOf(
          () => BackupDocument.fromJson(jsonCopy(backup)..['format'] = 'x'),
        ).single.field,
        'format',
      );
      for (final version in [0, 3, 99]) {
        expect(
          problemsOf(
            () => BackupDocument.fromJson(
              jsonCopy(backup)..['schemaVersion'] = version,
            ),
          ).single.field,
          'schemaVersion',
          reason: 'version $version',
        );
      }
    });

    test('a document made from the database is of the current version', () {
      final document = BackupDocument.fromJson(jsonCopy(backup));
      expect(document.sourceSchemaVersion, 2);
      expect(document.toJson()['schemaVersion'], BackupFormat.schemaVersion);
    });

    test('the record limit is checked before the records are read', () {
      final root = jsonCopy(backup);
      final rules =
          (root['data']! as Map<String, Object?>)['reminder_rules']!
              as List<Object?>;
      for (var i = 0; i < BackupFormat.maxRecords; i++) {
        rules.add(<String, Object?>{});
      }
      final problems = problemsOf(() => BackupDocument.fromJson(root));
      expect(problems.single.location, 'data');
    });
  });

  group('the fields of schema 2 (BS-98)', () {
    Map<String, Object?> first(BackupTable table) =>
        copyOf(recordsOf(backup, table).first);

    List<ImportProblem> problemsOfSet(
      BackupTable table,
      Map<String, Object?> changes,
    ) => problemsOf(() => roundTrips[table]!(first(table)..addAll(changes)));

    test('step_days.source: manual and health, nothing else (BS-97)', () {
      final days = recordsOf(backup, BackupTable.stepDays);
      expect(days.map((d) => d['source']).toSet(), {'manual', 'health'});
      for (final source in ['manual', 'health']) {
        expect(
          () => roundTrips[BackupTable.stepDays]!(
            first(BackupTable.stepDays)..['source'] = source,
          ),
          returnsNormally,
        );
      }
      for (final source in ['watch', 'Manual', 'HEALTH', '', ' health']) {
        final problems = problemsOfSet(BackupTable.stepDays, {
          'source': source,
        });
        expect(problems.single.field, 'source', reason: '"$source"');
        expect(
          problems.single.message,
          'Quelle enthält einen unbekannten Wert',
        );
        if (source.trim().isNotEmpty) {
          expect(problems.single.displayText, isNot(contains(source.trim())));
        }
      }
      expect(
        problemsOfSet(BackupTable.stepDays, {'source': null}).single.message,
        'Quelle darf nicht leer sein',
      );
      expect(
        problemsOfSet(BackupTable.stepDays, {'source': 1}).single.message,
        contains('Datentyp'),
      );
    });

    test(
      'app_settings: the health switch and the time of the last comparison',
      () {
        final settings = recordsOf(backup, BackupTable.appSettings).single;
        expect(settings['health_steps_sync_enabled'], isTrue);
        expect(
          settings['health_steps_last_sync_at_utc'],
          '2026-03-02T17:45:30.125Z',
        );
        // The time is optional, the switch is not.
        expect(
          () => roundTrips[BackupTable.appSettings]!(
            first(BackupTable.appSettings)
              ..['health_steps_last_sync_at_utc'] = null,
          ),
          returnsNormally,
        );
        expect(
          problemsOfSet(BackupTable.appSettings, {
            'health_steps_sync_enabled': null,
          }).single.field,
          'health_steps_sync_enabled',
        );
        for (final wrong in <Object>[1, 'true', 0]) {
          expect(
            problemsOfSet(BackupTable.appSettings, {
              'health_steps_sync_enabled': wrong,
            }).single.message,
            contains('Datentyp'),
            reason: '$wrong',
          );
        }
        for (final bad in [
          '2026-03-02T17:45:30Z',
          '2026-03-02T17:45:30.125+02:00',
          '2026-03-02',
          '2026-13-02T17:45:30.125Z',
          1775000000000,
        ]) {
          expect(
            problemsOfSet(BackupTable.appSettings, {
              'health_steps_last_sync_at_utc': bad,
            }).single.field,
            'health_steps_last_sync_at_utc',
            reason: '$bad',
          );
        }
      },
    );

    group('tasks: the optional reminder is all or nothing (BS-111)', () {
      const reminder = {
        'reminder_at_utc': '2026-03-09T07:30:15.250Z',
        'reminder_local_date': '2026-03-09',
        'reminder_timezone_id': 'Europe/Berlin',
      };

      test('open and completed tasks may carry one, or none', () {
        final tasks = recordsOf(backup, BackupTable.tasks);
        expect(
          tasks.where((t) => t['reminder_at_utc'] != null),
          hasLength(2),
          reason: 'one open and one completed task with a reminder',
        );
        expect(tasks.where((t) => t['reminder_at_utc'] == null), isNotEmpty);
        expect(
          tasks.where(
            (t) =>
                t['reminder_at_utc'] != null && t['completed_at_utc'] == null,
          ),
          isNotEmpty,
        );
        expect(
          tasks.where(
            (t) =>
                t['reminder_at_utc'] != null && t['completed_at_utc'] != null,
          ),
          isNotEmpty,
        );
      });

      test('all three fields set, or all three null', () {
        final open = first(BackupTable.tasks)
          ..['completed_at_utc'] = null
          ..['completed_local_date'] = null
          ..['timezone_id'] = null
          ..['completion_eligibility'] = null;
        expect(
          () => roundTrips[BackupTable.tasks]!({...open, ...reminder}),
          returnsNormally,
        );
        expect(
          () => roundTrips[BackupTable.tasks]!({
            ...open,
            'reminder_at_utc': null,
            'reminder_local_date': null,
            'reminder_timezone_id': null,
          }),
          returnsNormally,
        );
      });

      for (final keep in <Set<String>>[
        {'reminder_at_utc'},
        {'reminder_local_date'},
        {'reminder_timezone_id'},
        {'reminder_at_utc', 'reminder_local_date'},
        {'reminder_at_utc', 'reminder_timezone_id'},
        {'reminder_local_date', 'reminder_timezone_id'},
      ]) {
        test('only ${keep.join(' and ')} is rejected', () {
          final record = {
            ...first(BackupTable.tasks),
            for (final key in reminder.keys)
              key: keep.contains(key) ? reminder[key] : null,
          };
          final problems = problemsOf(
            () => roundTrips[BackupTable.tasks]!(record),
          );
          expect(problems.single.field, 'reminder_at_utc');
          expect(
            problems.single.message,
            'Erinnerungsangaben unvollständig (Zeitpunkt, Datum und '
            'Zeitzone gehören zusammen)',
          );
        });
      }

      test('each field is checked on its own', () {
        for (final (field, bad) in <(String, Object?)>[
          ('reminder_at_utc', '2026-03-09T07:30:15Z'),
          ('reminder_at_utc', 5),
          ('reminder_local_date', '2026-02-30'),
          ('reminder_local_date', '09.03.2026'),
          ('reminder_timezone_id', 'Mars/Olympus'),
          ('reminder_timezone_id', ''),
        ]) {
          final problems = problemsOf(
            () => roundTrips[BackupTable.tasks]!({
              ...first(BackupTable.tasks),
              ...reminder,
              field: bad,
            }),
          );
          expect(problems.map((p) => p.field), [field], reason: '$field $bad');
        }
      });

      test('the values survive the typed record unchanged', () {
        final dto = TaskDto.fromJson({
          ...first(BackupTable.tasks),
          ...reminder,
        });
        expect(dto.reminderAtUtc, DateTime.utc(2026, 3, 9, 7, 30, 15, 250));
        expect(dto.reminderAtUtc!.isUtc, isTrue);
        expect(dto.reminderLocalDate, LocalDate(2026, 3, 9));
        expect(dto.reminderTimezoneId, 'Europe/Berlin');
      });
    });

    group('workout_day_marks: rest and skipped days (BS-99)', () {
      test('the rich fixture has both kinds and two zones', () {
        final marks = recordsOf(backup, BackupTable.workoutDayMarks);
        expect(marks.map((m) => m['kind']).toSet(), {'rest', 'skipped'});
        expect(marks.map((m) => m['timezone_id']).toSet(), {
          'Europe/Berlin',
          'Europe/London',
        });
      });

      test('kind is rest or skipped', () {
        for (final kind in ['rest', 'skipped']) {
          expect(
            () => roundTrips[BackupTable.workoutDayMarks]!(
              first(BackupTable.workoutDayMarks)..['kind'] = kind,
            ),
            returnsNormally,
          );
        }
        for (final kind in [
          'sick',
          'Rest',
          'SKIPPED',
          '',
          'rest ',
          'workout',
        ]) {
          final problems = problemsOfSet(BackupTable.workoutDayMarks, {
            'kind': kind,
          });
          expect(problems.single.field, 'kind', reason: '"$kind"');
          expect(problems.single.message, 'Art enthält einen unbekannten Wert');
        }
        expect(
          problemsOfSet(BackupTable.workoutDayMarks, {
            'kind': null,
          }).single.message,
          'Art darf nicht leer sein',
        );
      });

      test('date, zone, id and version are checked', () {
        for (final (field, bad) in <(String, Object?)>[
          ('local_date', '2026-02-30'),
          ('local_date', '2026-3-5'),
          ('local_date', null),
          ('timezone_id', 'Mars/Olympus'),
          ('timezone_id', null),
          ('id', 'not-a-uuid'),
          ('id', null),
          ('row_version', 0),
          ('created_at_utc', '2026-03-05T21:00:00Z'),
          ('updated_at_utc', null),
        ]) {
          expect(
            problemsOfSet(BackupTable.workoutDayMarks, {
              field: bad,
            }).map((p) => p.field),
            [field],
            reason: '$field $bad',
          );
        }
      });

      test('the typed record keeps its values and writes them back', () {
        final json = first(BackupTable.workoutDayMarks);
        final dto = WorkoutDayMarkDto.fromJson(json);
        expect(dto.kind, json['kind']);
        expect(dto.localDate.toIso(), json['local_date']);
        expect(dto.timezoneId, json['timezone_id']);
        expect(dto.rowVersion, json['row_version']);
        expect(dto.toJson(), json);
        expect(dto.toCompanion().kind, Value<String>(dto.kind));
      });
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
        'workout_daily',
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
