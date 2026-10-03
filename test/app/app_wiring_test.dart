import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/bootstrap/device_time_zone.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/modules/application/data_epoch.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/db_fixtures.dart';
import '../support/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_modules.dart';

const String _habitId = '123e4567-e89b-42d3-a456-426614174000';
const String _otherId = '223e4567-e89b-42d3-a456-426614174999';

final AppTabBuilders _tabs = AppTabBuilders(
  home: (context, state) => const CounterTab('Tab-Home'),
  analysis: (context, state) => const CounterTab('Tab-Analyse'),
  habits: (context, state) => const CounterTab('Tab-Habits'),
  profile: (context, state) => const CounterTab('Tab-Profil'),
);

Future<void> _seedHabit(DataHarness harness) async {
  await harness.database
      .into(harness.database.habits)
      .insert(habitRow(id: _habitId));
}

void main() {
  group('notification entry (AT29)', () {
    testWidgets(
      'a cold start from a habit reminder opens the habit above the dashboard (AT29)',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
          seed: _seedHabit,
          preparePlatform: (platform) =>
              platform.launchPayloadValue = '/habits/$_habitId',
        );
        await tester.pumpUntil(() => app.location == '/habits/$_habitId');
        await app.settle();
        expect(find.text('probe:habit-detail {id: $_habitId}'), findsOneWidget);
        // Back returns to the dashboard: there is a history below.
        expect(await app.systemBack(), isTrue);
        expect(app.location, '/');
        expect(find.text('Tab-Home:0'), findsOneWidget);
      },
    );

    testWidgets('a habit that does not exist opens the habit list (AT29)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
        preparePlatform: (platform) =>
            platform.launchPayloadValue = '/habits/$_otherId',
      );
      await tester.pumpUntil(() => app.location == '/habits');
      await app.settle();
      expect(find.text('Tab-Habits:0'), findsOneWidget);
      expect(find.byType(AppBottomNavBar), findsOneWidget);
    });

    testWidgets('a switched-off module opens the dashboard (AT29)', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
        enabledModules: <String>{'body', 'focus', 'tasks', 'gamification'},
        preparePlatform: (platform) => platform.launchPayloadValue = '/water',
      );
      await app.settle();
      expect(app.location, '/');
      expect(find.text('Tab-Home:0'), findsOneWidget);
      expect(find.textContaining('probe:'), findsNothing);
    });

    testWidgets('a water reminder opens the water screen above the dashboard', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
        preparePlatform: (platform) => platform.launchPayloadValue = '/water',
      );
      await tester.pumpUntil(() => app.location == '/water');
      expect(find.text('probe:water'), findsOneWidget);
    });

    testWidgets('an unknown or damaged payload opens the dashboard', (
      tester,
    ) async {
      for (final payload in <String>[
        'https://example.invalid/steal',
        '/habits/not-an-id',
        '../../etc',
        '',
      ]) {
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
          preparePlatform: (platform) => platform.launchPayloadValue = payload,
        );
        await app.settle();
        expect(app.location, '/', reason: payload);
        expect(find.textContaining('probe:'), findsNothing, reason: payload);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'a tap while the app runs opens the target on top of what is open',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
        );
        app.platform.emitTap('/water');
        await tester.pumpUntil(() => app.location == '/water');
        expect(find.text('probe:water'), findsOneWidget);
        expect(await app.systemBack(), isTrue);
        expect(app.location, '/');
      },
    );

    testWidgets('a tap never takes an open form away: its input survives', (
      tester,
    ) async {
      final app = await pumpFullApp(tester, modules: fullFakeModules());
      app.router.go('/');
      unawaited(app.router.push<void>('/weight/new'));
      await tester.pump();
      await app.settle();
      app.platform.emitTap('/habits');
      await app.settle();
      // A tab target does not replace a screen the user is working on.
      expect(app.location, '/weight/new');
      app.platform.emitTap('/water');
      await tester.pumpUntil(() => app.location == '/water');
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/weight/new');
    });

    testWidgets(
      'during the onboarding the payload is ignored, also afterwards',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          onboarded: false,
          modules: fullFakeModules(),
          preparePlatform: (platform) => platform.launchPayloadValue = '/water',
        );
        await app.settle();
        expect(app.location, '/onboarding');
        app.platform.emitTap('/water');
        await app.settle();
        expect(app.location, '/onboarding');
        await app.run(app.harness.seedOnboarded);
        await app.settle();
        expect(app.location, '/');
      },
    );
  });

  group('reminders', () {
    testWidgets(
      'the platform is initialized and a database change plans reminders',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        expect(app.platform.initializeCalls, 1);
        final preferences = app.container.read(
          reminderPreferencesRepositoryProvider,
        );
        await app.run(
          () => preferences.setNotificationsEnabled(
            commandId: app.harness.ids.newId(),
            enabled: true,
          ),
        );
        await app.run(
          () => preferences.setWaterSlots(
            commandId: app.harness.ids.newId(),
            hours: <int>{12, 14},
          ),
        );
        await tester.pumpUntil(
          () => app.platform.alarms.isNotEmpty,
          reason: 'the auto reconciler did not plan the reminders',
        );
        expect(
          app.platform.alarms.values.every(
            (alarm) => alarm.payload == '/water',
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'reaching the water goal cancels today\'s remaining water reminders',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        final preferences = app.container.read(
          reminderPreferencesRepositoryProvider,
        );
        await app.run(
          () => preferences.setNotificationsEnabled(
            commandId: app.harness.ids.newId(),
            enabled: true,
          ),
        );
        await app.run(
          () => preferences.setWaterSlots(
            commandId: app.harness.ids.newId(),
            hours: <int>{12, 14},
          ),
        );
        await tester.pumpUntil(() => app.platform.alarms.isNotEmpty);
        final today = app.harness.clock.today();
        bool plannedToday() => app.platform.alarms.values.any(
          (alarm) => app.harness.clock.localDateOf(alarm.fireAtUtc) == today,
        );
        expect(plannedToday(), isTrue);

        // The goal is 2500 ml; one entry is at most 2000 ml.
        for (final entry in <(String, int)>[('wa1', 1250), ('wa2', 1250)]) {
          await app.run(
            () => app.harness.database
                .into(app.harness.database.waterEntries)
                .insert(waterRow(id: entry.$1, ml: entry.$2)),
          );
        }
        await tester.pumpUntil(
          () => !plannedToday(),
          reason: 'today\'s water reminders were not cancelled',
        );
        expect(app.platform.alarms, isNotEmpty); // tomorrow's stay
      },
    );
  });

  group('backup integration', () {
    testWidgets(
      'leftover temporary exports are cleaned up once after the start',
      (tester) async {
        final app = await pumpFullApp(tester);
        expect(app.backupFiles.deleteCalls, <bool>[true]);
      },
    );

    testWidgets(
      'a reset leads to the onboarding, cancels notifications and tells the app (AT32)',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        expect(app.container.read(dataEpochProvider), 0);
        final outcome = await app.runLive(
          () => app.container
              .read(resetServiceProvider)
              .resetAllData(confirmation: ResetService.confirmationPhrase),
        );
        expect(outcome.notificationsCancelled, isTrue);
        expect(outcome.listenerNotified, isTrue);
        await tester.pumpUntil(() => app.location == '/onboarding');
        expect(find.byType(AppBottomNavBar), findsNothing);
        expect(app.platform.cancelAllPendingCalls, greaterThanOrEqualTo(1));
        expect(app.container.read(dataEpochProvider), 1);
      },
    );

    testWidgets(
      'the canceller and the listener are the app\'s, not the no-ops',
      (tester) async {
        final app = await pumpFullApp(tester);
        final before = app.platform.cancelAllPendingCalls;
        await app.container
            .read(notificationCancellerProvider)
            .cancelAllNotifications();
        expect(app.platform.cancelAllPendingCalls, before + 1);
        await app.runLive(
          () => app.container.read(backupListenerProvider).onDataReplaced(),
        );
        expect(app.container.read(dataEpochProvider), 1);
      },
    );
  });

  group('clock', () {
    testWidgets('today follows the local midnight while the app runs', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      expect(app.container.read(todayProvider), LocalDate(2026, 10, 3));
      app.harness.clock.advance(const Duration(hours: 15));
      await tester.pump(const Duration(hours: 15));
      expect(app.container.read(todayProvider), LocalDate(2026, 10, 4));
    });

    testWidgets(
      'today is read again when the app comes back to the foreground',
      (tester) async {
        final app = await pumpFullApp(tester);
        app.harness.clock.advance(const Duration(hours: 40));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await app.settle();
        expect(app.container.read(todayProvider), LocalDate(2026, 10, 5));
      },
    );

    testWidgets(
      'a running focus session is restored when the app comes back, also away '
      'from the session screen (AT16, AT17)',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          seed: (h) => h.database
              .into(h.database.focusSessions)
              .insert(
                focusRow(
                  status: 'running',
                  accumulated: 0,
                  segmentStartedAt: Value(h.clock.nowUtc()),
                ),
              ),
        );
        final epoch = app.container.read(focusForegroundEpochProvider);

        // The device slept for 30 minutes: no tick ran, the clock moved on.
        app.harness.clock.advance(const Duration(minutes: 30));
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        for (var i = 0; i < 4; i++) {
          await app.settle();
        }

        expect(
          app.container.read(focusForegroundEpochProvider),
          greaterThan(epoch),
          reason: 'the countdown starts a fresh phase',
        );
        final row = await tester.runAsync(
          () => (app.harness.database.select(
            app.harness.database.focusSessions,
          )..where((s) => s.id.equals('f1'))).getSingle(),
        );
        expect(row!.status, 'awaiting_confirmation');
      },
    );

    test('the zone source follows the device zone (AT25)', () async {
      final source = _MutableTimeZoneSource('Europe/Berlin');
      final zone = await DeviceTimeZone.detect(source);
      final adapter = RuntimeZoneSource(zone);
      expect(await adapter.currentZoneId(), 'Europe/Berlin');
      source.id = 'America/New_York';
      expect(await adapter.currentZoneId(), 'America/New_York');
      // The clock reads the shared zone, so it already follows.
      expect(zone.id, 'America/New_York');
      source.id = 'Not/AZone';
      expect(await adapter.currentZoneId(), 'UTC');
    });
  });
}

final class _MutableTimeZoneSource implements TimeZoneSource {
  _MutableTimeZoneSource(this.id);

  String id;

  @override
  Future<String> currentZoneId() async => id;
}
