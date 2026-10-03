import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/application/device_zone_tracker.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';

class _Source implements DeviceTimeZoneSource {
  String? zone;
  Object? failure;

  @override
  Future<String?> currentZoneId() async {
    final error = failure;
    if (error != null) {
      throw error;
    }
    return zone;
  }
}

void main() {
  late _Source source;
  late DeviceZoneTracker tracker;

  setUp(() {
    source = _Source();
    tracker = DeviceZoneTracker(source: source);
  });

  test('starts with the UTC placeholder until the first read', () {
    expect(tracker.zoneId, 'UTC');
  });

  test('the first successful read replaces the placeholder', () async {
    source.zone = 'Europe/Berlin';
    expect(await tracker.refresh(), isTrue);
    expect(tracker.zoneId, 'Europe/Berlin');
  });

  test('an unchanged zone is not reported', () async {
    source.zone = 'Europe/Berlin';
    await tracker.refresh();
    expect(await tracker.refresh(), isFalse);
    expect(tracker.zoneId, 'Europe/Berlin');
  });

  test('a changed zone is reported once', () async {
    source.zone = 'Europe/Berlin';
    await tracker.refresh();
    source.zone = 'America/New_York';
    expect(await tracker.refresh(), isTrue);
    expect(tracker.zoneId, 'America/New_York');
    expect(await tracker.refresh(), isFalse);
  });

  test('an unreadable zone keeps the last known one', () async {
    source.zone = 'Europe/Berlin';
    await tracker.refresh();
    source.zone = null;
    expect(await tracker.refresh(), isFalse);
    expect(tracker.zoneId, 'Europe/Berlin');
  });

  test('a source that throws keeps the last known zone', () async {
    source.zone = 'Europe/Berlin';
    await tracker.refresh();
    source.failure = StateError('platform');
    expect(await tracker.refresh(), isFalse);
    expect(tracker.zoneId, 'Europe/Berlin');
  });

  test('a configurable placeholder is supported', () async {
    final custom = DeviceZoneTracker(
      source: source,
      initialZoneId: 'Europe/Berlin',
    );
    source.zone = 'Europe/Berlin';
    expect(await custom.refresh(), isFalse, reason: 'already known');
  });
}
