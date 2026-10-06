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

  /// Build number (the part of the `pubspec.yaml` version after the `+`); kept
  /// in sync with `pubspec.yaml` by `test/core/config/app_config_test.dart`.
  /// The settings row and the page "Über die App" show [appVersion] and this
  /// number, so they can only differ from the release by the one version in
  /// `pubspec.yaml`.
  static const int buildNumber = 1;

  /// Stable technical backup format marker of V1. Not a visible brand name.
  static const String backupFormat = 'levelup_life_backup';

  /// Backup schema version of V1.
  static const int backupSchemaVersion = 1;

  /// Prefix of exported backup files:
  /// `self-improvement-backup-YYYY-MM-DD-HHmm.json`.
  static const String backupFileNamePrefix = 'self-improvement-backup';

  /// Default locale of the user interface (German only in V1).
  static const String localeTag = 'de_DE';
}
