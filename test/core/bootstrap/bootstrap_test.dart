import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/bootstrap/app_bootstrap.dart';
import 'package:self_improvement/core/bootstrap/local_data_seeder.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/testing/broken_executor.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late FakeClock clock;

  setUp(() {
    db = createTestDatabase();
    clock = FakeClock.at('2026-10-03T22:30:00Z');
  });
  tearDown(() => db.close());

  test(
    'seeds profile and settings with honest defaults, no invented data',
    () async {
      await AppBootstrap.run(database: db, clock: clock);

      final profile = await ProfileRepository(db).get();
      expect(profile, isNotNull);
      expect(profile!.onboardingCompleted, isFalse);
      expect(profile.displayName, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.ageYears, isNull);
      expect(profile.startWeightGrams, isNull);
      expect(profile.targetWeightGrams, isNull);
      expect(profile.motivationGoals, isEmpty);
      // 22:30 UTC is already the next day in Berlin.
      expect(profile.startedOn, LocalDate(2026, 10, 4));

      final settings = await AppSettingsRepository(db).get();
      expect(settings, isNotNull);
      expect(settings!.themeModeKey, 'system');
      expect(
        settings.notificationsEnabled,
        isFalse,
        reason: 'reminders start off',
      );
      expect(settings.lastKnownTimezone, 'Europe/Berlin');

      // No business data is invented.
      expect(await db.select(db.weightEntries).get(), isEmpty);
      expect(await db.select(db.moduleStatusHistory).get(), isEmpty);
      expect(await db.select(db.goalVersions).get(), isEmpty);
      expect(await db.select(db.dashboardCards).get(), isEmpty);
    },
  );

  test('seeding is idempotent and never changes existing rows', () async {
    await AppBootstrap.run(database: db, clock: clock);
    await (db.update(db.profile))
        .write(const ProfileCompanion(displayName: Value('Mia')));
    clock.advance(const Duration(days: 10));
    await LocalDataSeeder(database: db, clock: clock).ensureSingletons();
    await AppBootstrap.run(database: db, clock: clock);

    expect((await db.select(db.profile).get()), hasLength(1));
    expect((await db.select(db.appSettings).get()), hasLength(1));
    final profile = await ProfileRepository(db).get();
    expect(profile!.displayName, 'Mia');
    expect(
      profile.startedOn,
      LocalDate(2026, 10, 4),
      reason: 'start date is not re-seeded',
    );
  });

  test(
    'an open/migration failure becomes MigrationFailure and deletes nothing',
    () async {
      final broken = AppDatabase(BrokenQueryExecutor());
      addTearDown(() async {});
      await expectLater(
        AppBootstrap.run(database: broken, clock: clock),
        throwsA(
          isA<MigrationFailure>().having(
            (f) => f.userMessage,
            'message',
            'Daten konnten nicht geöffnet werden.',
          ),
        ),
      );
    },
  );
}
