import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/settings/app_settings_value.dart';

/// Read access to the singleton application settings.
class AppSettingsRepository {
  AppSettingsRepository(this._database);

  final AppDatabase _database;

  Stream<AppSettingsValue?> watch() => _database
      .select(_database.appSettings)
      .watchSingleOrNull()
      .map((row) => row == null ? null : mapSettings(row));

  Future<AppSettingsValue?> get() async {
    final row = await _database.select(_database.appSettings).getSingleOrNull();
    return row == null ? null : mapSettings(row);
  }

  static AppSettingsValue mapSettings(AppSettingsRow row) => AppSettingsValue(
    themeModeKey: row.themeMode,
    reduceMotion: row.reduceMotion,
    haptics: row.haptics,
    notificationsEnabled: row.notificationsEnabled,
    lastKnownTimezone: row.lastKnownTimezone,
    healthStepsSyncEnabled: row.healthStepsSyncEnabled,
    healthStepsLastSyncAtUtc: row.healthStepsLastSyncAtUtc,
    rowVersion: row.rowVersion,
  );
}
