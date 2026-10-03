import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_overview.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';
import 'package:self_improvement/core/testing/data_harness.dart';

import '../support/reminder_harness.dart';

/// The providers wire the engine the way the app root does; the platform is
/// the only part replaced.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  final originalDebugPrint = debugPrint;
  setUp(() => debugPrint = (String? message, {int? wrapWidth}) {});
  tearDown(() => debugPrint = originalDebugPrint);

  late DataHarness data;
  late FakeReminderPlatform platform;
  late ReminderHarness seed;

  setUp(() async {
    // The harness gives helpers to seed rows; the container shares its data.
    seed = await ReminderHarness.create();
    data = seed.data;
    platform = FakeReminderPlatform(clock: data.clock);
  });
  tearDown(() async {
    await platform.dispose();
    await seed.dispose();
  });

  ProviderContainer container({List<Override> overrides = const []}) =>
      data.createContainer(
        overrides: [
          reminderPlatformProvider.overrideWithValue(platform),
          ...overrides,
        ],
      );

  group('defaults', () {
    test('the water goal fact defaults to "not reached"', () async {
      final c = container();
      expect(await c.read(waterGoalReachedTodayProvider)(), isFalse);
    });

    test('the platform defaults to the real adapter without touching it', () {
      // Only the type is checked: building it must not call the plugin.
      final c = ProviderContainer.test(
        overrides: [
          // Everything but the platform is irrelevant for this check.
        ],
      );
      expect(
        c.read(reminderPlatformProvider),
        isA<FlutterLocalNotificationsReminderPlatform>(),
      );
    });

    test('the focus input defaults to the focus_sessions table', () async {
      final c = container();
      expect(await c.read(reminderFocusSessionProvider)(), isNull);
      final session = await seed.addFocus(
        planned: 900,
        segmentStart: data.clock.nowUtc(),
      );
      final input = await c.read(reminderFocusSessionProvider)();
      expect(input!.sessionId, session);
      expect(input.status, OpenFocusStatus.running);
    });
  });

  group('service', () {
    test('reconciles end to end through the providers', () async {
      final c = container();
      await seed.setWanted(true);
      await seed.setWaterHours({10, 12});

      final status = await c.read(reminderServiceProvider).reconcile();

      expect(status.state, ReminderState.active);
      expect(status.scheduledCount, 14);
      expect(platform.alarms, hasLength(14));
    });

    test('the injected water goal fact is used', () async {
      var reached = false;
      final c = container(
        overrides: [
          waterGoalReachedTodayProvider.overrideWithValue(() async => reached),
        ],
      );
      await seed.setWanted(true);
      await seed.setWaterHours({10, 12});
      final service = c.read(reminderServiceProvider);
      await service.reconcile();
      expect(platform.alarms, hasLength(14));

      reached = true;
      await service.reconcile();
      expect(platform.alarms, hasLength(12));
    });

    test('the injected focus input is used instead of the table', () async {
      final injected = FocusEndInput(
        sessionId: '00000000-0000-4000-8000-0000000000aa',
        status: OpenFocusStatus.running,
        plannedSeconds: 600,
        accumulatedSeconds: 0,
        segmentStartedAtUtc: data.clock.nowUtc(),
      );
      final c = container(
        overrides: [
          reminderFocusSessionProvider.overrideWithValue(() async => injected),
        ],
      );
      await seed.setWanted(true);
      await c.read(reminderServiceProvider).reconcile();
      final rows = await seed.rows();
      expect(rows.single.semanticKey, 'focus_end:${injected.sessionId}');
    });

    test('the service is created once per container', () {
      final c = container();
      expect(
        identical(
          c.read(reminderServiceProvider),
          c.read(reminderServiceProvider),
        ),
        isTrue,
      );
    });
  });

  group('status provider', () {
    test('streams the status and every change', () async {
      final c = container();
      final seen = <ReminderStatus>[];
      c.listen<AsyncValue<ReminderStatus>>(
        reminderStatusProvider,
        (_, next) => next.whenData(seen.add),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(seen.last.state, ReminderState.off);

      await seed.setWanted(true);
      await seed.setWaterHours({10});
      await c.read(reminderServiceProvider).reconcile();
      await pumpEventQueue();
      expect(seen.last.state, ReminderState.active);
      expect(seen.last.scheduledCount, 7);
    });
  });

  group('notification list', () {
    test('is the list of planned reminders, soonest first', () async {
      final c = container();
      final seen = <List<ScheduledReminder>>[];
      c.listen<AsyncValue<List<ScheduledReminder>>>(
        plannedRemindersProvider,
        (_, next) => next.whenData(seen.add),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(seen.last, isEmpty);

      await seed.setWanted(true);
      await seed.setWaterHours({10, 12});
      await seed.addHabit();
      await c.read(reminderServiceProvider).reconcile();
      await pumpEventQueue();

      final list = seen.last;
      expect(list, hasLength(21));
      final times = list.map((r) => r.fireAtUtc).toList();
      expect(times, [...times]..sort());
      expect(list.map((r) => r.kind).toSet(), {
        ReminderKind.water,
        ReminderKind.habit,
      });
    });

    test(
      'has no delivery history: delivered notifications leave the list',
      () async {
        final c = container();
        c.listen<AsyncValue<List<ScheduledReminder>>>(
          plannedRemindersProvider,
          (_, _) {},
          fireImmediately: true,
        );
        await seed.setWanted(true);
        await seed.setWaterHours({10});
        final service = c.read(reminderServiceProvider);
        await service.reconcile();
        expect(
          (await c.read(plannedRemindersProvider.future)).first.semanticKey,
          'water:2026-10-03:10:00',
        );

        data.clock.setNow(DateTime.utc(2026, 10, 3, 8, 5));
        platform.deliverDue(data.clock.nowUtc());
        await service.reconcile();
        await pumpEventQueue();
        final list = await c.read(plannedRemindersProvider.future);
        expect(list.first.semanticKey, 'water:2026-10-04:10:00');
      },
    );

    test('leaves out rows of an unknown kind', () async {
      final c = container();
      // A listener keeps the stream running (providers pause without one).
      c.listen<AsyncValue<List<ScheduledReminder>>>(
        plannedRemindersProvider,
        (_, _) {},
      );
      await data.database
          .into(data.database.scheduledNotifications)
          .insert(
            ScheduledNotificationsCompanion.insert(
              semanticKey: 'unknown:x',
              fireAtUtc: DateTime.utc(2026, 10, 5),
              route: '/',
            ),
          );
      expect(await c.read(plannedRemindersProvider.future), isEmpty);
    });
  });

  group('overview', () {
    test('combines the planned reminders with the permission status', () async {
      final c = container();
      final seen = <AsyncValue<ReminderOverview>>[];
      c.listen<AsyncValue<ReminderOverview>>(
        reminderOverviewProvider,
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      expect(seen.first, isA<AsyncLoading<ReminderOverview>>());
      await pumpEventQueue();
      expect(seen.last.value!.isEmpty, isTrue);
      expect(seen.last.value!.status.state, ReminderState.off);

      await seed.setWaterHours({10});
      await c
          .read(reminderServiceProvider)
          .enableReminders(commandId: data.ids.newId());
      await pumpEventQueue();

      final overview = seen.last.value!;
      expect(overview.reminders, hasLength(7));
      expect(overview.status.state, ReminderState.active);
      expect(overview.status.permission, NotificationPermission.granted);
    });

    test('shows a blocked permission next to an empty list', () async {
      platform.permission = NotificationPermission.denied;
      platform.permissionAfterRequest = NotificationPermission.denied;
      final c = container();
      c.listen<AsyncValue<ReminderOverview>>(
        reminderOverviewProvider,
        (_, _) {},
      );
      await seed.setWaterHours({10});
      await c
          .read(reminderServiceProvider)
          .enableReminders(commandId: data.ids.newId());
      await pumpEventQueue();
      final overview = c.read(reminderOverviewProvider).value!;
      expect(overview.isEmpty, isTrue);
      expect(overview.status.isBlocked, isTrue);
    });
  });

  group('settings providers', () {
    test('the enabled water slots stream', () async {
      final c = container();
      final seen = <Set<int>>[];
      c.listen<AsyncValue<Set<int>>>(
        waterReminderHoursProvider,
        (_, next) => next.whenData(seen.add),
        fireImmediately: true,
      );
      await pumpEventQueue();
      expect(seen.last, isEmpty);
      await c
          .read(reminderPreferencesRepositoryProvider)
          .setWaterSlots(commandId: data.ids.newId(), hours: {14, 18});
      await pumpEventQueue();
      expect(seen.last, {14, 18});
    });

    test(
      'switching on through the service stores the wish and plans',
      () async {
        final c = container();
        await seed.setWaterHours({10});
        final status = await c
            .read(reminderServiceProvider)
            .enableReminders(commandId: data.ids.newId());
        expect(status.state, ReminderState.active);
        expect(
          await c
              .read(reminderPreferencesRepositoryProvider)
              .notificationsWanted(),
          isTrue,
        );
      },
    );
  });

  group('auto reconcile', () {
    test('plans after changes without any explicit call', () async {
      final c = container();
      c.read(reminderAutoReconcileProvider);
      final service = c.read(reminderServiceProvider);
      await seed.setWanted(true);
      await seed.setWaterHours({10});
      for (var round = 0; round < 3; round++) {
        await pumpEventQueue();
        await service.whenIdle();
      }
      expect(platform.alarms, hasLength(7));
    });

    test('a module switched off removes its reminders', () async {
      final c = container();
      c.read(reminderAutoReconcileProvider);
      final service = c.read(reminderServiceProvider);
      await seed.setWanted(true);
      await seed.setWaterHours({10});
      await pumpEventQueue();
      await service.whenIdle();
      await seed.setModule(ModuleId.nutrition, enabled: false);
      for (var round = 0; round < 3; round++) {
        await pumpEventQueue();
        await service.whenIdle();
      }
      expect(platform.alarms, isEmpty);
    });
  });

  group('device zone', () {
    test('the tracker reads the zone through the injected source', () async {
      final c = container(
        overrides: [
          deviceTimeZoneSourceProvider.overrideWithValue(
            _FixedZone('Europe/Berlin'),
          ),
        ],
      );
      final tracker = c.read(deviceZoneTrackerProvider);
      expect(tracker.zoneId, 'UTC');
      expect(await tracker.refresh(), isTrue);
      expect(tracker.zoneId, 'Europe/Berlin');
    });
  });

  group('entry resolver', () {
    test('is wired with the module statuses and records', () async {
      final c = container();
      final habit = await seed.addHabit();
      final resolver = c.read(notificationEntryResolverProvider);
      expect(await resolver.resolve('/habits/$habit'), '/habits/$habit');
      await seed.setModule(ModuleId.tasks, enabled: false);
      expect(await resolver.resolve('/habits/$habit'), '/');
    });
  });
}

class _FixedZone implements DeviceTimeZoneSource {
  _FixedZone(this.zone);

  final String zone;

  @override
  Future<String?> currentZoneId() async => zone;
}
