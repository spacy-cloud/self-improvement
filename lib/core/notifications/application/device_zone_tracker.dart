import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';

/// Keeps the device time zone id in a synchronous getter and reports when it
/// changed.
///
/// `SystemClock` needs the zone as a synchronous `String Function()`, but the
/// platform answers asynchronously. The app root therefore reads the zone once
/// before the first frame and again on every resume:
///
/// ```dart
/// final tracker = DeviceZoneTracker(source: const FlutterTimezoneSource());
/// await tracker.refresh();
/// final clock = SystemClock(timeZoneIdProvider: () => tracker.zoneId);
/// // on AppLifecycleState.resumed:
/// if (await tracker.refresh()) {
///   await reminderService.reconcile(); // plans every reminder in the new zone
/// }
/// ```
///
/// A zone that cannot be read keeps the last known one; the planner then
/// simply plans in that zone.
final class DeviceZoneTracker {
  DeviceZoneTracker({required this._source, String initialZoneId = 'UTC'})
    : _zoneId = initialZoneId;

  final DeviceTimeZoneSource _source;
  String _zoneId;

  /// The last known IANA zone id of the device.
  String get zoneId => _zoneId;

  /// Reads the device zone again. Returns true when it differs from the last
  /// known one (the first successful read after the `UTC` placeholder counts).
  /// Never throws.
  Future<bool> refresh() async {
    final id = await _source.currentZoneId();
    if (id == null || id == _zoneId) {
      return false;
    }
    _zoneId = id;
    return true;
  }
}
