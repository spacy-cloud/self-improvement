import 'package:self_improvement/core/bootstrap/app_runtime.dart';
import 'package:self_improvement/core/bootstrap/device_time_zone.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// What a successful start hands to the running app.
class AppServices {
  AppServices({
    required this.database,
    required this.clock,
    required this.zoneSource,
    required this.dispose,
  });

  /// The opened, migrated and seeded local database.
  final AppDatabase database;

  /// The app's clock (reads the current device zone).
  final ClockService clock;

  /// Re-reads the device zone; feeds `DeviceZoneTracker` (reminder planning
  /// follows the zone) and keeps [clock] in step.
  final DeviceTimeZoneSource zoneSource;

  /// Releases the database.
  final Future<void> Function() dispose;
}

/// Starts the app's services. A failure (the database cannot be opened or
/// migrated) is thrown and shown with a retry; it never deletes data.
typedef AppStarter = Future<AppServices> Function();

/// The production start: opens the local database, detects the device time
/// zone and creates the singleton rows (the existing `AppRuntime`).
Future<AppServices> startProductionServices() async {
  final runtime = await AppRuntime.create();
  return AppServices(
    database: runtime.database,
    clock: runtime.clock,
    zoneSource: RuntimeZoneSource(runtime.zone),
    dispose: runtime.dispose,
  );
}

/// Bridges the bootstrap's [DeviceTimeZone] (which the clock reads) to the
/// reminder engine's [DeviceTimeZoneSource]: asking for the zone refreshes the
/// shared value first, so the clock already uses the new zone when the reminder
/// plan is recomputed after a resume.
final class RuntimeZoneSource implements DeviceTimeZoneSource {
  const RuntimeZoneSource(this._zone);

  final DeviceTimeZone _zone;

  @override
  Future<String?> currentZoneId() async {
    await _zone.refresh();
    return _zone.id;
  }
}
