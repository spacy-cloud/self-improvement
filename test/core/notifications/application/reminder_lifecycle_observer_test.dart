import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/application/device_zone_tracker.dart';
import 'package:self_improvement/core/notifications/application/reminder_lifecycle_observer.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';

import '../support/reminder_harness.dart';

class _Zone implements DeviceTimeZoneSource {
  String? zone = 'Europe/Berlin';
  int reads = 0;

  @override
  Future<String?> currentZoneId() async {
    reads++;
    return zone;
  }
}

/// Resume and time zone change: the lifecycle triggers of the reconcile.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness h;
  late _Zone source;
  late DeviceZoneTracker tracker;
  late ReminderLifecycleObserver observer;

  setUp(() async {
    h = await ReminderHarness.create();
    source = _Zone();
    tracker = DeviceZoneTracker(source: source);
    await tracker.refresh();
    observer = ReminderLifecycleObserver(service: h.service, zones: tracker);
    await h.setWanted(true);
    await h.setWaterHours({10});
  });
  tearDown(() async {
    observer.detach();
    await h.dispose();
  });

  test('a resume reads the zone and reconciles', () async {
    source.reads = 0;
    await observer.onResumed();
    expect(source.reads, 1);
    expect(await h.rows(), hasLength(7));
  });

  test('the lifecycle callback runs the same steps', () async {
    observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    await h.service.whenIdle();
    expect(await h.rows(), hasLength(7));
  });

  test('other lifecycle states do nothing', () async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      observer.didChangeAppLifecycleState(state);
    }
    await pumpEventQueue();
    await h.service.whenIdle();
    expect(await h.rows(), isEmpty);
    expect(h.platform.pendingIdsCalls, 0);
  });

  test(
    'a time zone change while in the background re-plans on resume',
    () async {
      await observer.onResumed();
      final before = await h.rows();
      h.platform.clearCalls();

      // The device was moved to New York; the app's clock follows its tracker.
      source.zone = 'America/New_York';
      expect(await tracker.refresh(), isTrue);
      h.data.clock.setTimeZone(tracker.zoneId);
      await observer.onResumed();

      final after = await h.rows();
      expect(
        after.map((r) => r.notificationId),
        before.map((r) => r.notificationId),
      );
      expect(
        after.first.fireAtUtc,
        isNot(before.first.fireAtUtc),
        reason: '10:00 in New York is another instant',
      );
      expect(h.platform.scheduleCalls, isNotEmpty);
    },
  );

  test('a resume without any change does nothing to the system', () async {
    await observer.onResumed();
    h.platform.clearCalls();
    await observer.onResumed();
    expect(h.platform.scheduleCalls, isEmpty);
    expect(h.platform.cancelCalls, isEmpty);
  });

  test('attach and detach are idempotent', () {
    observer
      ..attach()
      ..attach()
      ..detach()
      ..detach();
  });

  test(
    'the provider attaches an observer and detaches it on dispose',
    () async {
      final platform = FakeReminderPlatform(clock: h.data.clock);
      final container = h.data.createContainer(
        overrides: [
          reminderPlatformProvider.overrideWithValue(platform),
          deviceTimeZoneSourceProvider.overrideWithValue(source),
        ],
      );
      final provided = container.read(reminderLifecycleProvider);
      expect(provided, isA<ReminderLifecycleObserver>());
      provided.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      await container.read(reminderServiceProvider).whenIdle();
      expect(await h.rows(), hasLength(7));
      container.dispose();
      await platform.dispose();
    },
  );
}
