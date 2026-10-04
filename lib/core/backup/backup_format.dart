import 'package:self_improvement/core/config/app_config.dart';

/// Stable constants of the V1 backup format.
///
/// The format marker, schema version and file name prefix live in
/// [AppConfig]; this class adds the import limits and the root field names.
abstract final class BackupFormat {
  /// Exact value of the root field `format`.
  static const String marker = AppConfig.backupFormat;

  /// Exact value of the root field `schemaVersion`. Unknown versions are
  /// rejected; there is no silent migration.
  static const int schemaVersion = AppConfig.backupSchemaVersion;

  /// Largest accepted import file: 10 MiB (inclusive).
  static const int maxFileBytes = 10 * 1024 * 1024;

  /// Largest accepted number of records in one file (inclusive). The two
  /// singleton objects `profile` and `app_settings` count as one record each.
  static const int maxRecords = 50000;

  /// A validation report lists at most this many problems.
  static const int maxReportedProblems = 20;

  /// Extension of backup files, without the dot.
  static const String fileExtension = 'json';

  static const String rootFormat = 'format';
  static const String rootSchemaVersion = 'schemaVersion';
  static const String rootExportedAtUtc = 'exportedAtUtc';
  static const String rootAppVersion = 'appVersion';
  static const String rootData = 'data';

  /// Technical tables that are never part of a backup. They are recomputed
  /// (`xp_awards`) or meaningless on another installation.
  static const Set<String> technicalTables = {
    'xp_awards',
    'command_receipts',
    'scheduled_notifications',
  };
}

/// The 16 sections of the `data` object, in file order.
///
/// [key] is the stable JSON key (identical to the database table name).
enum BackupTable {
  profile('profile', 'Profil', isSingleton: true),
  appSettings('app_settings', 'Einstellungen', isSingleton: true),
  moduleStatusHistory('module_status_history', 'Modulstatus-Verlauf'),
  dashboardCards('dashboard_cards', 'Dashboard-Karten'),
  goalVersions('goal_versions', 'Zielversionen'),
  dailyGoalSnapshots('daily_goal_snapshots', 'Tagesziel-Snapshots'),
  weightEntries('weight_entries', 'Gewichtseinträge'),
  stepDays('step_days', 'Schritte-Tage'),
  waterEntries('water_entries', 'Wassereinträge'),
  mealEntries('meal_entries', 'Mahlzeiten'),
  focusSessions('focus_sessions', 'Fokus-Sitzungen'),
  workoutEntries('workout_entries', 'Workouts'),
  tasks('tasks', 'Aufgaben'),
  habits('habits', 'Gewohnheiten'),
  habitChecks('habit_checks', 'Gewohnheits-Checks'),
  reminderRules('reminder_rules', 'Erinnerungsregeln');

  const BackupTable(this.key, this.germanLabel, {this.isSingleton = false});

  /// JSON key of the section and database table name.
  final String key;

  /// Display name for previews and messages.
  final String germanLabel;

  /// Singletons are exported as one object, all others as an array.
  final bool isSingleton;

  /// The table for a JSON [key], or `null` when unknown.
  static BackupTable? tryParse(String key) {
    for (final table in values) {
      if (table.key == key) {
        return table;
      }
    }
    return null;
  }
}
