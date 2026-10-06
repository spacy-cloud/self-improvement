import 'package:drift/drift.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';

/// Writes the singleton application settings. Each setter is its own command
/// (atomic, idempotent). `notifications_enabled` is a DESIRED state; the real
/// OS permission is queried from the device.
class SettingsCommands {
  SettingsCommands({required this._database, required this._runner});

  static const String type = 'settings.update';

  final AppDatabase _database;
  final CommandRunner _runner;

  Future<CommandOutcome> setThemeMode({
    required String commandId,
    required String themeModeKey,
  }) async {
    if (!SchemaKeys.themeModes.contains(themeModeKey)) {
      throw ValidationFailure.field('themeMode', 'Unbekannte Darstellung.');
    }
    return _write(
      commandId,
      (nowUtc, version) => AppSettingsCompanion(
        themeMode: Value(themeModeKey),
        updatedAtUtc: Value(nowUtc),
        rowVersion: Value(version),
      ),
    );
  }

  Future<CommandOutcome> setReduceMotion({
    required String commandId,
    required bool value,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      reduceMotion: Value(value),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  Future<CommandOutcome> setHaptics({
    required String commandId,
    required bool value,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      haptics: Value(value),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  Future<CommandOutcome> setNotificationsEnabled({
    required String commandId,
    required bool value,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      notificationsEnabled: Value(value),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  Future<CommandOutcome> setLastKnownTimezone({
    required String commandId,
    required String timezoneId,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      lastKnownTimezone: Value(timezoneId),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  /// Sets the wish "Schritte aus Health übernehmen" (BS-97). Like
  /// [setNotificationsEnabled] it is a DESIRED state; the access of the health
  /// interface is asked from the device.
  Future<CommandOutcome> setHealthStepsSyncEnabled({
    required String commandId,
    required bool value,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      healthStepsSyncEnabled: Value(value),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  /// Stores when the last comparison with the health interface finished
  /// (BS-97). The instant is cut to the minute, the precision the app shows.
  Future<CommandOutcome> setHealthStepsLastSyncAt({
    required String commandId,
    required DateTime atUtc,
  }) => _write(
    commandId,
    (nowUtc, version) => AppSettingsCompanion(
      healthStepsLastSyncAtUtc: Value(minuteOf(atUtc)),
      updatedAtUtc: Value(nowUtc),
      rowVersion: Value(version),
    ),
  );

  /// [instant] without seconds and milliseconds (UTC): the precision of the
  /// time of the last comparison.
  static DateTime minuteOf(DateTime instant) {
    final utc = instant.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  Future<CommandOutcome> _write(
    String commandId,
    AppSettingsCompanion Function(DateTime nowUtc, int newVersion) build,
  ) {
    return _runner.run(
      commandId: commandId,
      type: type,
      body: (ctx) async {
        final row = await _database
            .select(_database.appSettings)
            .getSingleOrNull();
        if (row == null) {
          throw const NotFoundFailure(entity: 'app_settings');
        }
        await (_database.update(_database.appSettings)
              ..where((s) => s.id.equals('app')))
            .write(build(ctx.nowUtc, row.rowVersion + 1));
        return const CommandEffect(entityId: 'app');
      },
    );
  }
}
