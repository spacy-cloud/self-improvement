/// Central, compile-time application configuration.
///
/// This is the single place for the visible application name and the stable
/// technical identifiers. Native display names (Android `strings.xml`, iOS
/// `Info.plist`) are synchronised from [appName] by `tool/sync_app_name.dart`
/// and guarded by `test/core/config/app_config_test.dart`.
abstract final class AppConfig {
  /// Visible application name.
  ///
  /// Placeholder "App-Name" until the name decision (Jira BS-47) is made.
  /// Change this constant, then run `dart run tool/sync_app_name.dart`.
  static const String appName = 'App-Name';

  /// Technical Dart package name. Never changes with the visible name.
  static const String technicalName = 'self_improvement';

  /// Android application id / iOS bundle identifier. Stable technical id.
  static const String applicationId = 'de.lf10.selfimprovement';

  /// Application version (without build number); kept in sync with
  /// `pubspec.yaml` by `test/core/config/app_config_test.dart`.
  static const String appVersion = '1.0.0';

  /// Stable technical backup format marker (unchanged since V1). Not a
  /// visible brand name.
  static const String backupFormat = 'levelup_life_backup';

  /// Backup schema version the app writes. Version 1 (v0.1.0) is still read,
  /// through an explicit upward step (see `docs/backup-format.md`).
  static const int backupSchemaVersion = 2;

  /// Prefix of exported backup files:
  /// `self-improvement-backup-YYYY-MM-DD-HHmm.json`.
  static const String backupFileNamePrefix = 'self-improvement-backup';

  /// Default locale of the user interface (German only in V1).
  static const String localeTag = 'de_DE';
}
