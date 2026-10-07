import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';

/// The facts of the page "Über die App" and of the "Version" row of the
/// settings. Version, build number and the two technical versions are read from
/// their constants ([AppConfig], [AppDatabase], [BackupFormat]) and never
/// typed in here; the functions only put them into words.
abstract final class AboutInfo {
  /// Author line of the page. No names of single persons.
  static const String author = 'Spacy.cloud';

  /// Product page, opened in the browser when the user taps "Website".
  static const String websiteUrl = 'https://spacy.cloud/self-improvement';

  /// The address as the page shows it: without the scheme.
  static const String websiteLabel = 'spacy.cloud/self-improvement';

  /// The privacy note of the page.
  static const String privacy =
      'Alle Daten bleiben auf dem Gerät. Kein Konto, keine Cloud, keine '
      'Telemetrie.';

  /// "Version 0.2.0 (Build 2)", the line under the app name.
  static String versionLine({
    String version = AppConfig.appVersion,
    int build = AppConfig.buildNumber,
  }) => 'Version $version (Build $build)';

  /// "Daten-Schema 2 · Backup-Format 2", for support and for the import of a
  /// backup: the version of the local database schema and the version of the
  /// backup file format.
  static String technicalLine({
    int schema = AppDatabase.currentSchemaVersion,
    int backup = BackupFormat.schemaVersion,
  }) => 'Daten-Schema $schema · Backup-Format $backup';

  /// The same as [technicalLine] for a screen reader (no middle dot).
  static String technicalSpoken({
    int schema = AppDatabase.currentSchemaVersion,
    int backup = BackupFormat.schemaVersion,
  }) => 'Daten-Schema $schema, Backup-Format $backup';

  /// Spoken label of the "Version" row of the settings.
  static String versionRowLabel({String version = AppConfig.appVersion}) =>
      'Version $version, Details öffnen';
}
