import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_upgrade.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/time/clock_service.dart';

import 'support/backup_fixtures.dart';

/// `docs/backup-format.md` is a contract: its field lists and its example
/// must stay in sync with the implementation.
void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late String doc;
  late Map<String, Object?> exported;

  setUpAll(() async {
    doc = File('${Directory.current.path}/docs/backup-format.md')
        .readAsStringSync();
    exported = await richBackupJson();
  });

  /// The text of the section that starts with [heading] (up to the next
  /// heading of the same or a higher level).
  String section(String heading) {
    final level = heading.split(' ').first.length;
    final start = doc.indexOf('$heading\n');
    expect(start, isNonNegative, reason: 'missing section $heading');
    final rest = doc.substring(start + heading.length);
    final end = RegExp('\n#{1,$level} ').firstMatch(rest);
    return end == null ? rest : rest.substring(0, end.start);
  }

  /// First-column names of the field table of [text].
  Set<String> documentedFields(String text) => {
    for (final match in RegExp(
      r'^\| `([A-Za-z_]+)` \|',
      multiLine: true,
    ).allMatches(text))
      match.group(1)!,
  };

  group('field lists', () {
    test('the root object documents exactly the root fields', () {
      expect(
        documentedFields(section('## Root-Objekt')),
        exported.keys.toSet(),
      );
    });

    for (final table in BackupTable.values) {
      test('${table.key} documents exactly its fields', () {
        final data = exported['data']! as Map<String, Object?>;
        final value = data[table.key];
        final record = table.isSingleton
            ? value! as Map<String, Object?>
            : (value! as List<Object?>).first! as Map<String, Object?>;
        expect(
          documentedFields(section('### `${table.key}`')),
          record.keys.toSet(),
        );
      });
    }
  });

  group('constants and catalogs', () {
    test('format marker, schema version and file name pattern', () {
      expect(doc, contains('`${AppConfig.backupFormat}`'));
      expect(doc, contains('`schemaVersion`'));
      expect(AppConfig.backupSchemaVersion, 2);
      expect(
        doc,
        contains('${AppConfig.backupFileNamePrefix}-YYYY-MM-DD-HHmm.json'),
      );
    });

    test('limits match the implementation', () {
      expect(BackupFormat.maxFileBytes, 10485760);
      expect(doc, contains('10 MiB'));
      expect(doc, contains('10 485 760'));
      expect(BackupFormat.maxRecords, 50000);
      expect(doc, contains('50 000'));
      expect(BackupFormat.maxReportedProblems, 20);
      expect(doc, contains('bis zu **20 Probleme**'));
    });

    test('every schema key is documented', () {
      final all = <String>{
        ...SchemaKeys.modules,
        ...SchemaKeys.dashboardCards,
        ...SchemaKeys.goalTypes,
        ...SchemaKeys.themeModes,
        ...SchemaKeys.focusCategories,
        ...SchemaKeys.focusStatuses,
        ...SchemaKeys.taskPriorities,
        ...SchemaKeys.trainingCategories,
        ...SchemaKeys.workoutIntensities,
        ...SchemaKeys.muscleGroups,
        ...SchemaKeys.habitIcons,
        ...SchemaKeys.reminderKinds,
        ...SchemaKeys.motivationGoals,
      };
      for (final key in all) {
        expect(doc, contains('`$key`'), reason: key);
      }
    });

    test('the not exported tables are listed with a reason', () {
      final text = section('## Was nicht exportiert wird – und warum');
      for (final table in BackupFormat.technicalTables) {
        expect(text, contains('`$table`'), reason: table);
      }
      expect(text, contains('weich gelöschte Zeilen'));
    });

    test('the section order matches the file order', () {
      final headings = RegExp(
        r'^### `([a-z_]+)`',
        multiLine: true,
      ).allMatches(doc).map((m) => m.group(1)!).toList();
      expect(headings, BackupTable.values.map((t) => t.key).toList());
    });
  });

  group('version 2 and the upward step from version 1 (BS-98)', () {
    test('the readable versions and the current one are documented', () {
      expect(BackupFormat.readableSchemaVersions, [1, 2]);
      expect(doc, contains('# Backup-Format (Version 2)'));
      expect(doc, contains('unterstützt: Version 1 und 2'));
      expect(doc, contains('## Aufwärtsschritt von Version 1 auf 2'));
      expect(doc, contains('`levelup_life_backup`'));
    });

    test('every section of version 2 says that it is new', () {
      for (final table in BackupTable.values) {
        final text = section('### `${table.key}`');
        expect(
          text.contains('Abschnitt neu in Version 2'),
          table.sinceVersion == 2,
          reason: table.key,
        );
      }
    });

    test('every field of version 2 is marked as new in its table', () {
      for (final entry in BackupUpgrade.fieldsAddedInVersion2.entries) {
        final text = section('### `${entry.key}`');
        for (final field in entry.value.keys) {
          final row = RegExp(
            '^\\| `$field` \\|.*\$',
            multiLine: true,
          ).firstMatch(text);
          expect(row, isNotNull, reason: '${entry.key}.$field');
          expect(row!.group(0), contains('(neu in Version 2)'), reason: field);
        }
      }
    });

    test(
      'the upward step table lists every added section, field and default',
      () {
        final text = section('## Aufwärtsschritt von Version 1 auf 2');
        for (final name in BackupUpgrade.sectionsAddedInVersion2) {
          expect(text, contains('`$name`'), reason: name);
        }
        for (final entry in BackupUpgrade.fieldsAddedInVersion2.entries) {
          expect(text, contains('`${entry.key}`'), reason: entry.key);
          for (final field in entry.value.entries) {
            expect(text, contains('`${field.key}`'), reason: field.key);
          }
        }
        expect(text, contains('`manual`'));
        expect(text, contains('`false`'));
        expect(text, contains('`null`'));
        expect(text, contains('`[]`'));
      },
    );

    test(
      'a version 1 file with content of version 2 is documented as rejected',
      () {
        final text = section('## Aufwärtsschritt von Version 1 auf 2');
        expect(text, contains('Unbekannter Abschnitt'));
        expect(text, contains('Unbekanntes Zusatzfeld'));
        expect(text, contains('wird abgelehnt'));
      },
    );

    test('every fixture file of version 1 is documented', () {
      final files = Directory('test/fixtures/v1')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(files, isNotEmpty);
      for (final name in files) {
        expect(doc, contains('`$name`'), reason: name);
      }
    });
  });

  group('example', () {
    late Map<String, Object?> example;

    setUpAll(() {
      final match = RegExp(
        r'```json\n(.*?)\n```',
        dotAll: true,
      ).firstMatch(doc);
      expect(match, isNotNull, reason: 'the document needs a JSON example');
      example = jsonDecode(match!.group(1)!) as Map<String, Object?>;
    });

    test('is a valid backup according to the real validator', () {
      final result = plainValidator.validateDecoded(example);
      expect(
        result.report.problems.map((p) => p.displayText).toList(),
        isEmpty,
      );
      expect(result.isValid, isTrue);
    });

    test('also validates as bytes and has every section', () {
      final result = plainValidator.validateBytes(
        Uint8List.fromList(bytesOf(example)),
      );
      expect(result.isValid, isTrue);
      final counts = result.document!.data.counts;
      for (final table in BackupTable.values) {
        expect(counts[table], greaterThan(0), reason: table.key);
      }
    });

    test('uses synthetic data: Mia Muster and 71,5 kg', () {
      final data = plainValidator.validateDecoded(example).document!.data;
      expect(data.profile.displayName, 'Mia Muster');
      expect(data.weightEntries.map((w) => w.weightGrams), contains(71500));
    });

    test('every field of every section appears in the example', () {
      final data = example['data']! as Map<String, Object?>;
      for (final table in BackupTable.values) {
        final value = data[table.key];
        final records = table.isSingleton
            ? [value! as Map<String, Object?>]
            : (value! as List<Object?>).cast<Map<String, Object?>>();
        final keys = {for (final r in records) ...r.keys};
        final real =
            (table.isSingleton
                    ? [
                        (exported['data']! as Map<String, Object?>)[table.key]!
                            as Map<String, Object?>,
                      ]
                    : ((exported['data']! as Map<String, Object?>)[table.key]!
                              as List<Object?>)
                          .cast<Map<String, Object?>>())
                .first
                .keys
                .toSet();
        expect(keys, real, reason: table.key);
      }
    });
  });

  test('the document is public-repo safe: no local paths, no emoji', () {
    for (final forbidden in ['/home/', '/data/', 'Obsidian', 'Vault', '[[']) {
      expect(doc, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(
      RegExp(
        r'[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]',
        unicode: true,
      ).hasMatch(doc),
      isFalse,
    );
  });
}
