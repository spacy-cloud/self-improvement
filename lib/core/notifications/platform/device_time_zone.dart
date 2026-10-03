import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Reads the IANA time zone the device is set to.
///
/// The app root uses it to feed `SystemClock.timeZoneId` (a synchronous
/// getter, so the id is read asynchronously at start and on resume and then
/// cached) and to notice a zone change: after the cached id changed, the app
/// calls `ReminderService.reconcile`, which plans every reminder again in the
/// new zone.
abstract interface class DeviceTimeZoneSource {
  /// The IANA id of the device zone (e.g. `Europe/Berlin`), or `null` when it
  /// cannot be read or the id is not part of the bundled time zone database.
  /// Never throws.
  Future<String?> currentZoneId();
}

/// [DeviceTimeZoneSource] on top of `flutter_timezone`
/// (`FlutterTimezone.getLocalTimezone`). Needs a device; not covered by host
/// tests.
final class FlutterTimezoneSource implements DeviceTimeZoneSource {
  const FlutterTimezoneSource();

  @override
  Future<String?> currentZoneId() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return TimeZones.isKnown(info.identifier) ? info.identifier : null;
    } catch (_) {
      return null;
    }
  }
}
