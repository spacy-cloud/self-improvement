import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/bootstrap/local_data_seeder.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Opens and migrates the database and creates the singleton rows.
///
/// A failure is reported as [MigrationFailure] so the app can show a
/// diagnosis with retry. It NEVER deletes or resets data.
abstract final class AppBootstrap {
  static Future<void> run({
    required AppDatabase database,
    required ClockService clock,
  }) async {
    try {
      // Forces opening and migrating the (lazily opened) connection.
      await database.customSelect('SELECT 1').get();
      await LocalDataSeeder(
        database: database,
        clock: clock,
      ).ensureSingletons();
    } on AppFailure {
      rethrow;
    } catch (error) {
      debugPrint('bootstrap failed: ${error.runtimeType}');
      throw MigrationFailure(causeType: error.runtimeType.toString());
    }
  }
}
