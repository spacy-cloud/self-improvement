import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/settings/app_settings_repository.dart';
import 'package:self_improvement/core/settings/app_settings_value.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The clock. Overridden at the app root (SystemClock) and in tests
/// (FakeClock); reading it unoverridden is a programming error.
final clockProvider = Provider<ClockService>(
  (ref) => throw UnimplementedError('clockProvider must be overridden'),
);

/// Source of ids for records and commands (UUID v4; deterministic in tests).
final idGeneratorProvider = Provider<IdGenerator>(
  (ref) => const UuidGenerator(),
);

/// The single local database. Overridden at the app root and in tests.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider must be overridden'),
);

/// Post-commit UI events.
final commandEventsProvider = Provider<CommandEvents>((ref) {
  final events = CommandEvents();
  ref.onDispose(events.dispose);
  return events;
});

/// Keeps goal snapshots and XP consistent inside command transactions. The
/// default does nothing; the real implementation overrides it.
final projectionSynchronizerProvider = Provider<ProjectionSynchronizer>(
  (ref) => const NoopProjectionSynchronizer(),
);

final moduleStatusRepositoryProvider = Provider<ModuleStatusRepository>(
  (ref) => ModuleStatusRepository(ref.watch(appDatabaseProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(appDatabaseProvider)),
);

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => AppSettingsRepository(ref.watch(appDatabaseProvider)),
);

/// Runs every mutation atomically and idempotently.
final commandRunnerProvider = Provider<CommandRunner>((ref) {
  final modules = ref.watch(moduleStatusRepositoryProvider);
  return CommandRunner(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    projections: ref.watch(projectionSynchronizerProvider),
    events: ref.watch(commandEventsProvider),
    gamificationEnabled: () => modules.isEnabled(ModuleId.gamification),
  );
});

/// The local profile (null until seeded).
final profileProvider = StreamProvider<UserProfile?>(
  (ref) => ref.watch(profileRepositoryProvider).watch(),
);

/// The application settings (null until seeded).
final appSettingsProvider = StreamProvider<AppSettingsValue?>(
  (ref) => ref.watch(appSettingsRepositoryProvider).watch(),
);

/// Which modules are enabled right now.
final moduleStatusesProvider = StreamProvider<Map<ModuleId, bool>>(
  (ref) => ref.watch(moduleStatusRepositoryProvider).watchStatuses(),
);

/// Today's local date. Rebuilds listeners when the day changes; the app root
/// calls [TodayNotifier.refresh] on resume and at midnight.
final todayProvider = NotifierProvider<TodayNotifier, LocalDate>(
  TodayNotifier.new,
);

class TodayNotifier extends Notifier<LocalDate> {
  @override
  LocalDate build() => ref.watch(clockProvider).today();

  /// Re-evaluates the date (resume, midnight timer, zone change).
  void refresh() {
    final now = ref.read(clockProvider).today();
    if (now != state) {
      state = now;
    }
  }
}
