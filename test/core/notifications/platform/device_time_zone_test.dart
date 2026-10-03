import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// The zone source on the real `flutter_timezone` Dart code with a replaced
/// native side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_timezone');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUpAll(TimeZones.ensureInitialized);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer(Object? Function(MethodCall call) handler) => messenger
      .setMockMethodCallHandler(channel, (call) async => handler(call));

  test('returns the IANA id the platform reports as a plain string', () async {
    answer((_) => 'Europe/Berlin');
    expect(
      await const FlutterTimezoneSource().currentZoneId(),
      'Europe/Berlin',
    );
  });

  test('returns the id of the structured answer of newer platforms', () async {
    answer(
      (_) => <String, Object?>{
        'identifier': 'America/New_York',
        'localizedName': null,
      },
    );
    expect(
      await const FlutterTimezoneSource().currentZoneId(),
      'America/New_York',
    );
  });

  test('asks the platform for the local time zone', () async {
    String? method;
    answer((call) {
      method = call.method;
      return 'Europe/Berlin';
    });
    await const FlutterTimezoneSource().currentZoneId();
    expect(method, 'getLocalTimezone');
  });

  test('an id that the time zone database does not know is null', () async {
    answer((_) => 'Mars/Olympus');
    expect(await const FlutterTimezoneSource().currentZoneId(), isNull);
  });

  test('a failing platform is null, never an exception', () async {
    answer((_) => throw PlatformException(code: 'x'));
    expect(await const FlutterTimezoneSource().currentZoneId(), isNull);
  });

  test('a missing plugin is null', () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await const FlutterTimezoneSource().currentZoneId(), isNull);
  });

  test('UTC aliases are known zones', () async {
    answer((_) => 'Etc/UTC');
    expect(await const FlutterTimezoneSource().currentZoneId(), 'Etc/UTC');
  });
}
