import 'package:drift/drift.dart';
import 'package:self_improvement/core/bootstrap/app_bootstrap.dart';
import 'package:self_improvement/core/bootstrap/device_time_zone.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/database_connection.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// The long-lived objects of a running app: clock, device zone and the opened,
/// migrated and seeded database.
class AppRuntime {
  AppRuntime._({
    required this.clock,
    required this.zone,
    required this.database,
  });

  final ClockService clock;
  final DeviceTimeZone zone;
  final AppDatabase database;

  /// Opens everything. Throws [MigrationFailure] when the database cannot be
  /// opened or migrated; callers show a diagnosis with retry and NEVER reset
  /// data automatically. [executor] and [zoneSource] exist for tests.
  static Future<AppRuntime> create({
    QueryExecutor? executor,
    TimeZoneSource zoneSource = const PlatformTimeZoneSource(),
  }) async {
    final zone = await DeviceTimeZone.detect(zoneSource);
    final clock = SystemClock(timeZoneIdProvider: () => zone.id);
    final database = AppDatabase(executor ?? openAppConnection());
    try {
      await AppBootstrap.run(database: database, clock: clock);
    } on AppFailure {
      await database.close();
      rethrow;
    }
    return AppRuntime._(clock: clock, zone: zone, database: database);
  }

  Future<void> dispose() => database.close();
}
