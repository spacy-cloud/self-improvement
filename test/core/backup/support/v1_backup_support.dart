import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Directory of the schema 1 fixtures. They were made with the unchanged code
/// of v0.1.0 before the schema 2 change, see
/// `test/fixtures/v1/generate_v1_fixtures.dart.txt`.
const String v1FixtureDirectory = 'test/fixtures/v1';

/// The 90 day sample backup of the demo generator (all modules).
const String demoBackupFile = 'demo-backup-v1-90-tage.json';

/// A backup of a fresh installation (empty arrays, default settings).
const String freshInstallBackupFile = 'fresh-install-backup-v1.json';

/// A backup in which every field has a non-default value and the text values
/// carry quotes, backslashes, line breaks and characters outside the BMP.
const String richBackupFile = 'rich-backup-v1.json';

/// The backup the v1 exporter made of `v1-database.sql` (the fixture database
/// of the migration tests) at the end of the scenario.
const String databaseBackupFile = 'v1-database-backup.json';

/// All version 1 backup fixtures.
const List<String> v1BackupFiles = [
  demoBackupFile,
  freshInstallBackupFile,
  richBackupFile,
  databaseBackupFile,
];

/// The bytes of the fixture [name].
Uint8List v1Bytes(String name) =>
    File('$v1FixtureDirectory/$name').readAsBytesSync();

/// The decoded (mutable) JSON of the fixture [name].
Map<String, Object?> v1Json(String name) =>
    jsonDecode(utf8.decode(v1Bytes(name))) as Map<String, Object?>;

/// What the `data` object of a version 1 file means in version 2 terms,
/// written out by hand and independent of `BackupUpgrade`: no day is marked,
/// every step day is `manual`, the health comparison is off and never ran,
/// no task has a reminder.
Map<String, Object?> expectedVersion2Data(Map<String, Object?> version1Data) {
  final data = jsonDecode(jsonEncode(version1Data)) as Map<String, Object?>;
  (data['app_settings']! as Map<String, Object?>)
    ..['health_steps_sync_enabled'] = false
    ..['health_steps_last_sync_at_utc'] = null;
  for (final day
      in (data['step_days']! as List<Object?>).cast<Map<String, Object?>>()) {
    day['source'] = 'manual';
  }
  for (final task
      in (data['tasks']! as List<Object?>).cast<Map<String, Object?>>()) {
    task
      ..['reminder_at_utc'] = null
      ..['reminder_local_date'] = null
      ..['reminder_timezone_id'] = null;
  }
  data['workout_day_marks'] = <Object?>[];
  return data;
}
