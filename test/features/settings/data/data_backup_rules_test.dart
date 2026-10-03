import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/features/settings/application/data_backup_rules.dart';

import '../../../core/backup/support/backup_fixtures.dart';

/// Pure rules of the data screen: the reset phrase, the counting of entries,
/// the readable import problems and the warnings derived from a file.
void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('ResetPhrase (AT32, C09)', () {
    test('only the exact word confirms', () {
      expect(ResetPhrase.matches('LÖSCHEN'), isTrue);
    });

    for (final wrong in <String>[
      '',
      'löschen',
      'Löschen',
      'LOESCHEN',
      'LOSCHEN',
      'LÖSCHEN ',
      ' LÖSCHEN',
      'LÖSCHEN!',
      'LÖSCH',
      'LÖSCHEN LÖSCHEN',
      'L Ö S C H E N',
    ]) {
      test('rejects "$wrong"', () {
        expect(ResetPhrase.matches(wrong), isFalse);
      });
    }

    test('a near miss is the right word in the wrong shape', () {
      expect(ResetPhrase.isNearMiss('löschen'), isTrue);
      expect(ResetPhrase.isNearMiss(' LÖSCHEN '), isTrue);
      expect(ResetPhrase.isNearMiss('Löschen'), isTrue);
      expect(ResetPhrase.isNearMiss('LÖSCHEN'), isFalse);
      expect(ResetPhrase.isNearMiss('LOESCHEN'), isFalse);
      expect(ResetPhrase.isNearMiss(''), isFalse);
      expect(ResetPhrase.isNearMiss('LÖSCH'), isFalse);
    });
  });

  group('counting', () {
    test('entries are the user records, not the history sections', () {
      final counts = <BackupTable, int>{
        BackupTable.profile: 1,
        BackupTable.appSettings: 1,
        BackupTable.moduleStatusHistory: 5,
        BackupTable.dashboardCards: 8,
        BackupTable.goalVersions: 6,
        BackupTable.dailyGoalSnapshots: 40,
        BackupTable.weightEntries: 12,
        BackupTable.stepDays: 10,
        BackupTable.waterEntries: 30,
        BackupTable.mealEntries: 4,
        BackupTable.focusSessions: 2,
        BackupTable.workoutEntries: 3,
        BackupTable.tasks: 7,
        BackupTable.habits: 2,
        BackupTable.habitChecks: 25,
        BackupTable.reminderRules: 5,
      };
      expect(userEntryCount(counts), 12 + 10 + 30 + 4 + 2 + 3 + 7 + 2 + 25);
      expect(userEntryCount(const {}), 0);
    });

    test('entriesText follows German number rules', () {
      expect(entriesText(0), '0 Einträge');
      expect(entriesText(1), '1 Eintrag');
      expect(entriesText(2), '2 Einträge');
      expect(entriesText(1250), '1.250 Einträge');
    });

    test('the dative form is used after "mit"', () {
      expect(entriesDativeText(0), '0 Einträgen');
      expect(entriesDativeText(1), '1 Eintrag');
      expect(entriesDativeText(3), '3 Einträgen');
      expect(entriesDativeText(1250), '1.250 Einträgen');
    });

    test('areaCounts lists user entries first and leaves out empty areas', () {
      final areas = areaCounts(<BackupTable, int>{
        BackupTable.profile: 1,
        BackupTable.appSettings: 1,
        BackupTable.moduleStatusHistory: 5,
        BackupTable.waterEntries: 30,
        BackupTable.weightEntries: 12,
        BackupTable.mealEntries: 0,
        BackupTable.reminderRules: 2,
      });
      expect(areas.map((a) => a.label), [
        'Gewichtseinträge',
        'Wassereinträge',
        'Modulstatus-Verlauf',
        'Erinnerungsregeln',
      ]);
      expect(areas.map((a) => a.count), [12, 30, 5, 2]);
    });
  });

  group('readable problems (AT31)', () {
    test('a record problem names the area and the human position', () {
      final problem = ImportProblem.record(
        BackupTable.weightEntries,
        3,
        'Gewicht außerhalb des erlaubten Bereichs',
      );
      expect(
        describeImportProblem(problem),
        'Gewichtseinträge, Eintrag 4: Gewicht außerhalb des erlaubten '
        'Bereichs',
      );
    });

    test('a singleton and a whole section have no position', () {
      expect(
        describeImportProblem(
          ImportProblem.record(BackupTable.profile, 0, 'Name zu lang'),
        ),
        'Profil: Name zu lang',
      );
      expect(
        describeImportProblem(
          ImportProblem.table(BackupTable.tasks, 'Abschnitt fehlt'),
        ),
        'Aufgaben: Abschnitt fehlt',
      );
    });

    test('file level problems keep their message', () {
      for (final location in <String>['file', 'root', 'data']) {
        expect(
          describeImportProblem(
            ImportProblem(location: location, message: 'Die Datei ist leer.'),
          ),
          'Die Datei ist leer.',
        );
      }
    });

    test('an unknown location is not turned into an area', () {
      expect(
        describeImportProblem(
          const ImportProblem(location: 'x_y[2]', message: 'Meldung'),
        ),
        'Meldung',
      );
    });

    test('at most five reasons, with a note for the rest', () {
      final report = ImportValidationReport([
        for (var i = 0; i < 8; i++)
          ImportProblem.record(BackupTable.waterEntries, i, 'Fehler $i'),
      ]);
      final text = describeRejection(report);
      expect(text.reasons, hasLength(5));
      expect(text.reasons.first, 'Wassereinträge, Eintrag 1: Fehler 0');
      expect(text.moreNote, '3 weitere Probleme werden nicht angezeigt.');
    });

    test('exactly one hidden problem is told in the singular', () {
      final report = ImportValidationReport([
        for (var i = 0; i < 6; i++)
          ImportProblem.record(BackupTable.waterEntries, i, 'Fehler'),
      ]);
      expect(
        describeRejection(report).moreNote,
        'Ein weiteres Problem wird nicht angezeigt.',
      );
    });

    test('five or fewer problems need no note', () {
      final report = ImportValidationReport([
        for (var i = 0; i < 5; i++)
          ImportProblem.record(BackupTable.waterEntries, i, 'Fehler'),
      ]);
      expect(describeRejection(report).reasons, hasLength(5));
      expect(describeRejection(report).moreNote, isNull);
    });

    test('a truncated report says that more problems exist', () {
      final report = ImportValidationReport([
        for (var i = 0; i < 20; i++)
          ImportProblem.record(BackupTable.waterEntries, i, 'Fehler'),
      ], truncated: true);
      final text = describeRejection(report);
      expect(text.reasons, hasLength(5));
      expect(text.moreNote, contains('weitere Probleme'));
    });
  });

  group('import warnings come from the file', () {
    Future<PreparedImport> prepared(
      void Function(Map<String, Object?> json) edit,
    ) async {
      final json = jsonCopy(await richBackupJson());
      edit(json);
      final result = const BackupValidator().validateBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );
      expect(result.report.problems, isEmpty);
      return PreparedImport(result.document!);
    }

    test(
      'a file of the same version with open work and notifications',
      () async {
        final file = await prepared((_) {});
        final warnings = importWarnings(file, currentAppVersion: '1.0.0');
        expect(warnings, [
          'Eine offene Fokus-Sitzung wird pausiert wiederhergestellt.',
          contains('Erinnerungen sind in der Sicherung eingeschaltet'),
        ]);
      },
    );

    test('another app version is named with both versions', () async {
      final file = await prepared((json) => json['appVersion'] = '0.9.2');
      final warnings = importWarnings(file, currentAppVersion: '1.0.0');
      expect(warnings.first, contains('0.9.2'));
      expect(warnings.first, contains('1.0.0'));
    });

    test('a file without entries says so', () async {
      final file = await prepared((json) {
        final data = json['data']! as Map<String, Object?>;
        for (final table in <String>[
          'weight_entries',
          'step_days',
          'water_entries',
          'meal_entries',
          'focus_sessions',
          'workout_entries',
          'tasks',
          'habit_checks',
          'habits',
        ]) {
          data[table] = <Object?>[];
        }
        (data['app_settings']!
                as Map<String, Object?>)['notifications_enabled'] =
            false;
      });
      final warnings = importWarnings(file, currentAppVersion: '1.0.0');
      expect(warnings, hasLength(1));
      expect(warnings.single, contains('keine Einträge'));
    });

    test('a quiet file has no warnings', () async {
      final file = await prepared((json) {
        final data = json['data']! as Map<String, Object?>;
        data['focus_sessions'] = <Object?>[];
        (data['app_settings']!
                as Map<String, Object?>)['notifications_enabled'] =
            false;
      });
      expect(importWarnings(file, currentAppVersion: '1.0.0'), isEmpty);
    });
  });
}
