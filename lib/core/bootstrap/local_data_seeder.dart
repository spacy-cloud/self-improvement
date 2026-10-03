import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Creates the singleton rows a fresh installation needs. Idempotent: running
/// it again never changes existing data.
///
/// Modules, dashboard cards and goal versions are NOT created here: they are
/// written atomically when onboarding completes (or is skipped).
class LocalDataSeeder {
  LocalDataSeeder({required this.database, required this.clock});

  final AppDatabase database;
  final ClockService clock;

  Future<void> ensureSingletons() async {
    await database.transaction(() async {
      final now = clock.nowUtc();
      final profile = await database.select(database.profile).getSingleOrNull();
      if (profile == null) {
        await database
            .into(database.profile)
            .insert(
              ProfileCompanion.insert(
                startedLocalDate: clock.localDateOf(now),
                createdAtUtc: now,
                updatedAtUtc: now,
              ),
            );
      }
      final settings = await database
          .select(database.appSettings)
          .getSingleOrNull();
      if (settings == null) {
        await database
            .into(database.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                createdAtUtc: now,
                updatedAtUtc: now,
                lastKnownTimezone: Value(clock.timeZoneId),
              ),
            );
      }
    });
  }
}
