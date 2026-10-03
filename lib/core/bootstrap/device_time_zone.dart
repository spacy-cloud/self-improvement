import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Source of the device's IANA time zone id (a thin platform seam).
abstract interface class TimeZoneSource {
  /// The current zone id reported by the platform, e.g. `Europe/Berlin`.
  Future<String> currentZoneId();
}

/// Production source backed by `flutter_timezone`.
final class PlatformTimeZoneSource implements TimeZoneSource {
  const PlatformTimeZoneSource();

  @override
  Future<String> currentZoneId() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}

/// The zone of the device, refreshed on demand (app resume).
///
/// An unknown or unavailable zone id never crashes the app: it falls back to
/// UTC, so dates stay consistent and the failure is visible only as a wrong
/// local day, never as lost data. The id is read synchronously by the clock.
class DeviceTimeZone {
  DeviceTimeZone._(this._source, this._id);

  static const String fallbackZoneId = 'UTC';

  final TimeZoneSource _source;
  String _id;

  /// The current zone id used by the clock.
  String get id => _id;

  /// Detects the zone once at startup.
  static Future<DeviceTimeZone> detect([
    TimeZoneSource source = const PlatformTimeZoneSource(),
  ]) async {
    TimeZones.ensureInitialized();
    return DeviceTimeZone._(source, await _read(source));
  }

  /// Re-reads the platform zone. Returns true if it changed (travel, manual
  /// change); callers then re-evaluate today and re-plan reminders.
  Future<bool> refresh() async {
    final latest = await _read(_source);
    if (latest == _id) {
      return false;
    }
    _id = latest;
    return true;
  }

  static Future<String> _read(TimeZoneSource source) async {
    try {
      final id = await source.currentZoneId();
      if (TimeZones.isKnown(id)) {
        return id;
      }
      debugPrint('unknown time zone id reported by the platform');
    } catch (error) {
      debugPrint('time zone detection failed: ${error.runtimeType}');
    }
    return fallbackZoneId;
  }
}
