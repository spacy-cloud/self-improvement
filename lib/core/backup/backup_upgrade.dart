import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';

/// The explicit upward steps of the backup format (BS-98, D-016).
///
/// A file of an older `schemaVersion` is brought to the current version here,
/// on the decoded JSON, before the one strict reader looks at it. The reader
/// therefore only knows the current version, and everything it knows about
/// older files lives in this class: which sections and fields a version added
/// and the value a file of the older version means for them. Each step is a
/// pure function that never changes its input.
///
/// ## Version 1 to 2
///
/// Version 2 added the section `workout_day_marks` and the fields listed in
/// [fieldsAddedInVersion2]. A version 1 file means: no day was marked, every
/// step day was typed in by hand (`manual`), the health comparison is off and
/// never ran, no task has a reminder. The step adds exactly these values.
///
/// A version 1 file must not contain anything that came with version 2: the
/// section or one of the fields in a version 1 file is a problem ("unknown
/// section" or "unknown additional field", the same words the strict reader
/// uses for anything it does not know), so a damaged or hand made mixture of
/// both versions is rejected instead of being half believed.
abstract final class BackupUpgrade {
  /// Sections that version 2 added (`BackupTable.sinceVersion`); a version 1
  /// file means an empty array for each of them.
  static final List<String> sectionsAddedInVersion2 = List.unmodifiable([
    for (final table in BackupTable.values)
      if (table.sinceVersion == 2) table.key,
  ]);

  /// Fields that version 2 added to existing sections, with the value a
  /// version 1 file means for them. Keys are section keys; `app_settings` is
  /// a singleton object, the others are arrays of records.
  static const Map<String, Map<String, Object?>> fieldsAddedInVersion2 = {
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
  };

  /// Brings the decoded root object [root] of a file of version [from] to the
  /// current version. Problems of the older version's shape (fields of a newer
  /// version) go to [problems]; the result is meant for the strict reader,
  /// which finds the remaining problems.
  static Map<String, Object?> toCurrent(
    Map<String, Object?> root, {
    required int from,
    required ProblemCollector problems,
  }) {
    var current = root;
    for (var version = from; version < BackupFormat.schemaVersion; version++) {
      current = switch (version) {
        1 => _version1To2(current, problems),
        _ => throw StateError('There is no upward step from version $version'),
      };
    }
    return current;
  }

  static Map<String, Object?> _version1To2(
    Map<String, Object?> root,
    ProblemCollector problems,
  ) {
    final data = root[BackupFormat.rootData];
    if (data is! Map<String, Object?>) {
      // Not an object: the reader reports it with its usual words.
      return {...root, BackupFormat.rootSchemaVersion: 2};
    }
    final upgraded = <String, Object?>{};
    for (final entry in data.entries) {
      final added = fieldsAddedInVersion2[entry.key];
      final table = BackupTable.tryParse(entry.key);
      upgraded[entry.key] = added == null || table == null
          ? entry.value
          : _withFields(table, entry.value, added, problems);
    }
    for (final section in sectionsAddedInVersion2) {
      if (data.containsKey(section)) {
        problems.add(
          const ImportProblem(
            location: 'data',
            message: 'Unbekannter Abschnitt',
          ),
        );
      } else {
        upgraded[section] = const <Object?>[];
      }
    }
    return {
      ...root,
      BackupFormat.rootSchemaVersion: 2,
      BackupFormat.rootData: upgraded,
    };
  }

  /// [section] (an object for a singleton, otherwise an array of records) with
  /// [added] set on every record. A record that already has one of the fields
  /// is a problem and keeps its own value. Anything that is not an object or
  /// an array of objects is returned as it is for the reader to report.
  static Object? _withFields(
    BackupTable table,
    Object? section,
    Map<String, Object?> added,
    ProblemCollector problems,
  ) {
    Object? upgradeRecord(Object? record, int index) {
      if (record is! Map<String, Object?>) {
        return record;
      }
      if (added.keys.any(record.containsKey)) {
        problems.addRecord(table, index, 'Unbekanntes Zusatzfeld');
      }
      return {...added, ...record};
    }

    if (table.isSingleton) {
      return upgradeRecord(section, 0);
    }
    if (section is! List<Object?>) {
      return section;
    }
    return [
      for (var index = 0; index < section.length; index++)
        upgradeRecord(section[index], index),
    ];
  }
}
