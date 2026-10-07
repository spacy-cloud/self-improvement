import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_codec.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_upgrade.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/time/clock_service.dart';

import 'support/backup_fixtures.dart';
import 'support/v1_backup_support.dart';

/// The upward step of the backup format from version 1 to version 2 (BS-98,
/// D-016): the files of v0.1.0 are read through `BackupUpgrade`, what version
/// 2 added must not appear in a version 1 file, and every other version is
/// rejected.
///
/// The version 1 files are fixtures that the unchanged code of v0.1.0 wrote
/// (`test/fixtures/v1`).
void main() {
  setUpAll(TimeZones.ensureInitialized);

  const validator = BackupValidator();

  BackupValidationResult validate(Map<String, Object?> root) =>
      validator.validateDecoded(root);

  List<String> problemsOf(BackupValidationResult result) =>
      result.report.problems.map((p) => p.displayText).toList();

  Map<String, Object?> dataOf(Map<String, Object?> root) =>
      root['data']! as Map<String, Object?>;

  group(
    'files of version 1 are read through the upward step (AT30, BS-98)',
    () {
      for (final name in v1BackupFiles) {
        test('$name is valid and was read as version 1', () {
          final result = validator.validateBytes(v1Bytes(name));
          expect(problemsOf(result), isEmpty);
          final document = result.document!;
          expect(document.sourceSchemaVersion, 1);
          expect(document.data.workoutDayMarks, isEmpty);
          expect(document.data.counts[BackupTable.workoutDayMarks], 0);
        });

        test('$name means the documented defaults in version 2', () {
          final v1 = v1Json(name);
          final document = validate(v1).document!;
          final written = document.toJson();
          expect(written['schemaVersion'], 2);
          expect(written['exportedAtUtc'], v1['exportedAtUtc']);
          expect(written['appVersion'], v1['appVersion']);
          // Compared as decoded JSON: the key order inside a record is not
          // part of the meaning.
          expect(
            jsonDecode(jsonEncode(written['data'])),
            expectedVersion2Data(dataOf(v1)),
          );
        });

        test('$name gives typed records with the version 2 defaults', () {
          final data = validate(v1Json(name)).document!.data;
          expect(data.stepDays.map((d) => d.source).toSet(), {
            if (data.stepDays.isNotEmpty) 'manual',
          });
          expect(data.appSettings.healthStepsSyncEnabled, isFalse);
          expect(data.appSettings.healthStepsLastSyncAtUtc, isNull);
          for (final task in data.tasks) {
            expect(task.reminderAtUtc, isNull);
            expect(task.reminderLocalDate, isNull);
            expect(task.reminderTimezoneId, isNull);
          }
        });

        test('$name is written as version 2 and read back as version 2', () {
          final document = validator.validateBytes(v1Bytes(name)).document!;
          final bytes = BackupCodec.encode(document);
          expect(BackupCodec.encode(document), bytes, reason: 'deterministic');
          final again = validator.validateBytes(bytes);
          expect(problemsOf(again), isEmpty);
          expect(again.document!.sourceSchemaVersion, 2);
          expect(BackupCodec.encode(again.document!), bytes);
        });
      }

      test('the step leaves the decoded input untouched', () {
        final root = v1Json(richBackupFile);
        final before = jsonEncode(root);
        validate(root);
        BackupUpgrade.toCurrent(root, from: 1, problems: ProblemCollector());
        expect(jsonEncode(root), before);
      });

      test('on its own it turns version 1 JSON into version 2 JSON', () {
        final v1 = v1Json(richBackupFile);
        final problems = ProblemCollector();
        final v2 = BackupUpgrade.toCurrent(v1, from: 1, problems: problems);
        expect(problems.hasProblems, isFalse);
        expect(v2['schemaVersion'], 2);
        expect(v2['format'], v1['format']);
        expect(v2['exportedAtUtc'], v1['exportedAtUtc']);
        expect(v2['appVersion'], v1['appVersion']);
        expect(dataOf(v2), expectedVersion2Data(dataOf(v1)));
      });

      test('the documented additions are exactly what the test expects', () {
        expect(BackupUpgrade.sectionsAddedInVersion2, ['workout_day_marks']);
        expect(BackupUpgrade.fieldsAddedInVersion2, {
          'step_days': {'source': 'manual'},
          'app_settings': {
            'health_steps_sync_enabled': false,
            'health_steps_last_sync_at_utc': null,
          },
          'tasks': {
            'reminder_at_utc': null,
            'reminder_local_date': null,
            'reminder_timezone_id': null,
          },
        });
      });

      test(
        'a file that is already current passes the step unchanged',
        () async {
          final v2 = await richBackupJson();
          final problems = ProblemCollector();
          final result = BackupUpgrade.toCurrent(
            v2,
            from: 2,
            problems: problems,
          );
          expect(identical(result, v2), isTrue);
          expect(problems.hasProblems, isFalse);
        },
      );

      test('there is no step from a version that was never written', () {
        expect(
          () => BackupUpgrade.toCurrent(
            v1Json(freshInstallBackupFile),
            from: 0,
            problems: ProblemCollector(),
          ),
          throwsStateError,
        );
      });
    },
  );

  group('what version 2 added must not be in a version 1 file (AT31, BS-98)', () {
    test('a version 1 file with the new section is rejected', () {
      final root = v1Json(freshInstallBackupFile);
      dataOf(root)['workout_day_marks'] = <Object?>[];
      final result = validate(root);
      expect(result.isValid, isFalse);
      expect(problemsOf(result), ['data: Unbekannter Abschnitt']);
    });

    for (final section in BackupUpgrade.fieldsAddedInVersion2.entries) {
      for (final field in section.value.keys) {
        test('a version 1 file with ${section.key}.$field is rejected', () {
          final root = v1Json(richBackupFile);
          final value = dataOf(root)[section.key];
          final record = value is List
              ? value.first! as Map<String, Object?>
              : value! as Map<String, Object?>;
          record[field] = section.value[field];
          final result = validate(root);
          expect(result.isValid, isFalse);
          final location = value is List ? '${section.key}[0]' : section.key;
          expect(problemsOf(result), ['$location: Unbekanntes Zusatzfeld']);
        });
      }
    }

    test('a version 1 file in the shape of version 2 is rejected', () async {
      final v2 = await richBackupJson();
      v2['schemaVersion'] = 1;
      final result = validate(v2);
      expect(result.isValid, isFalse);
      expect(result.document, isNull);
      expect(
        problemsOf(result),
        contains('data: Unbekannter Abschnitt'),
        reason: 'the section of version 2',
      );
      expect(
        problemsOf(result),
        contains('app_settings: Unbekanntes Zusatzfeld'),
      );
    });

    test('other problems of a version 1 file keep their position', () {
      final root = v1Json(demoBackupFile);
      final weights = dataOf(root)['weight_entries']! as List<Object?>;
      (weights[1]! as Map<String, Object?>)['weight_grams'] = 19900;
      final result = validate(root);
      expect(problemsOf(result), [
        'weight_entries[1]: Gewicht außerhalb des erlaubten Bereichs',
      ]);
    });

    test('a broken shape is reported the way it always was', () {
      Map<String, Object?> v1() => v1Json(freshInstallBackupFile);

      var root = v1();
      dataOf(root)['step_days'] = <String, Object?>{};
      expect(problemsOf(validate(root)), [
        'step_days: Abschnitt muss eine Liste sein',
      ]);

      root = v1();
      dataOf(root)['tasks'] = <Object?>[42];
      expect(problemsOf(validate(root)), [
        'tasks[0]: Eintrag muss ein Objekt sein',
      ]);

      root = v1();
      dataOf(root)['app_settings'] = <Object?>[];
      expect(problemsOf(validate(root)), [
        'app_settings: Es muss genau ein Einstellungs-Objekt vorhanden sein',
      ]);

      root = v1();
      root['data'] = <Object?>[];
      expect(problemsOf(validate(root)), [
        'root: Datenabschnitt hat einen ungültigen Datentyp (erwartet: Objekt)',
      ]);
    });
  });

  group('only the versions 1 and 2 are read (AT31, BS-98)', () {
    test('the readable versions are 1 and the current one', () {
      expect(BackupFormat.readableSchemaVersions, [1, 2]);
      expect(BackupFormat.schemaVersion, 2);
    });

    for (final version in <Object?>[
      0,
      3,
      4,
      99,
      -1,
      '1',
      '2',
      1.0,
      2.5,
      null,
    ]) {
      test('schemaVersion $version is rejected', () async {
        final root = await richBackupJson();
        if (version == null) {
          root.remove('schemaVersion');
        } else {
          root['schemaVersion'] = version;
        }
        final result = validate(root);
        expect(result.isValid, isFalse);
        expect(result.document, isNull);
        final problem = result.report.problems.single;
        expect(problem.location, 'root');
        expect(problem.field, 'schemaVersion');
        expect(
          problem.message,
          'Die Schema-Version dieser Datei wird nicht unterstützt '
          '(unterstützt: Version 1 und 2).',
        );
      });
    }

    test(
      'a wrong marker is rejected before the version is looked at',
      () async {
        for (final version in [1, 2, 3]) {
          final root = await richBackupJson();
          root['format'] = 'other_app_backup';
          root['schemaVersion'] = version;
          final result = validate(root);
          expect(result.report.problems.single.field, 'format');
          expect(
            result.report.problems.single.message,
            contains('keine Sicherung dieser App'),
          );
        }
      },
    );

    test(
      'a version 2 file needs every field and section of version 2',
      () async {
        Future<List<String>> problemsWithout(
          void Function(Map<String, Object?> data) change,
        ) async {
          final root = await richBackupJson();
          change(dataOf(root));
          return problemsOf(validate(root));
        }

        expect(await problemsWithout((d) => d.remove('workout_day_marks')), [
          'workout_day_marks: Pflichtabschnitt fehlt',
        ]);
        expect(
          await problemsWithout(
            (d) => (d['step_days']! as List<Object?>)
                .cast<Map<String, Object?>>()
                .first
                .remove('source'),
          ),
          ['step_days[0]: Pflichtfeld fehlt: Quelle'],
        );
        expect(
          await problemsWithout(
            (d) => (d['app_settings']! as Map<String, Object?>).remove(
              'health_steps_sync_enabled',
            ),
          ),
          ['app_settings: Pflichtfeld fehlt: Schritte aus Health übernehmen'],
        );
        expect(
          await problemsWithout(
            (d) => (d['app_settings']! as Map<String, Object?>).remove(
              'health_steps_last_sync_at_utc',
            ),
          ),
          ['app_settings: Pflichtfeld fehlt: Letzter Schritteabgleich'],
        );
        expect(
          await problemsWithout(
            (d) => (d['tasks']! as List<Object?>)
                .cast<Map<String, Object?>>()
                .first
                .remove('reminder_timezone_id'),
          ),
          ['tasks[0]: Pflichtfeld fehlt: Erinnerungszeitzone'],
        );
      },
    );
  });
}
