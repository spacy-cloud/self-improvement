import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/reminders/presentation/reminders_section.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../support/pump_app.dart';

/// The settings route of the host page in the tests.
const String settingsRoute = '/settings';

/// A real in-memory database (clock 2026-10-03 10:00 Europe/Berlin), the real
/// reminder engine on top of it and a fake of the operating system.
class ReminderEnv {
  ReminderEnv({
    required this.harness,
    required this.container,
    required this.platform,
    required this.feedback,
  });

  final DataHarness harness;
  final ProviderContainer container;
  final FakeReminderPlatform platform;
  final RecordingFeedbackService feedback;

  /// The stored wish (`app_settings.notifications_enabled`).
  Future<bool> wanted(WidgetTester tester) async => (await tester.runAsync(
    () => harness.database.select(harness.database.appSettings).getSingle(),
  ))!.notificationsEnabled;

  /// The enabled water slot hours as stored.
  Future<Set<int>> waterHours(WidgetTester tester) async {
    final rules = (await tester.runAsync(
      () => (harness.database.select(
        harness.database.reminderRules,
      )..where((r) => r.kind.equals('water'))).get(),
    ))!;
    return {
      for (final rule in rules)
        if (rule.enabled) rule.localTime!.hour,
    };
  }

  /// Another app start on the same database: a fresh container.
  ProviderContainer restart() => harness.createContainer(
    overrides: [
      reminderPlatformProvider.overrideWithValue(platform),
      feedbackServiceProvider.overrideWithValue(feedback),
    ],
  );

  /// Adds [count] habits with a reminder time (18:00, 18:01, ...), to exceed
  /// the planning limit of 40 notifications.
  Future<void> addHabitsWithReminders(WidgetTester tester, int count) async {
    await tester.runAsync(() async {
      final db = harness.database;
      final now = harness.clock.nowUtc();
      for (var i = 0; i < count; i++) {
        await db
            .into(db.habits)
            .insert(
              HabitsCompanion.insert(
                id: harness.ids.newId(),
                title: 'Gewohnheit $i',
                startedLocalDate: harness.clock.today(),
                createdAtUtc: now,
                updatedAtUtc: now,
                reminderLocalTime: Value(LocalTime(18, i)),
              ),
            );
      }
    });
  }
}

Future<ReminderEnv> createReminderEnv(
  WidgetTester tester, {
  NotificationPermission permission = NotificationPermission.granted,
  NotificationPermission afterRequest = NotificationPermission.granted,
  Set<String>? enabledModules,
  List<Override> overrides = const <Override>[],
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(DataHarness.create))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(
    () => harness.seedOnboarded(enabledModules: enabledModules),
  );
  final platform = FakeReminderPlatform(
    permission: permission,
    clock: harness.clock,
  )..permissionAfterRequest = afterRequest;
  addTearDown(platform.dispose);
  final feedback = RecordingFeedbackService(ids: harness.ids);
  final container = harness.createContainer(
    overrides: [
      reminderPlatformProvider.overrideWithValue(platform),
      feedbackServiceProvider.overrideWithValue(feedback),
      ...overrides,
    ],
  );
  return ReminderEnv(
    harness: harness,
    container: container,
    platform: platform,
    feedback: feedback,
  );
}

/// Routes of the host page: the settings page with the block and the targets
/// a planned reminder can open.
List<RouteBase> reminderRoutes() => [
  GoRoute(
    path: '/',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Dashboard'))),
  ),
  GoRoute(
    path: settingsRoute,
    builder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: RemindersSection(),
      ),
    ),
  ),
  GoRoute(
    path: '/water',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Wasser'))),
  ),
  GoRoute(
    path: '/habits',
    builder: (context, state) =>
        const Scaffold(body: Center(child: Text('Gewohnheiten'))),
  ),
];

Future<GoRouter> openSettings(
  WidgetTester tester,
  ReminderEnv env, {
  ProviderContainer? container,
  Size size = const Size(393, 852),
  double textScale = 1.0,
  EdgeInsets viewInsets = EdgeInsets.zero,
}) async {
  final router = await pumpRouterApp(
    tester,
    routes: reminderRoutes(),
    initialLocation: settingsRoute,
    container: container ?? env.container,
    size: size,
    textScale: textScale,
    viewInsets: viewInsets,
  );
  await settle(tester);
  return router;
}

/// Lets real async work (database, engine, fakes) finish and the animations
/// end.
Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.pumpAndSettle();
}

/// Taps the first widget with [text] and settles.
Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await settle(tester);
}

/// Switches reminders on or off by tapping the master row.
Future<void> tapMasterSwitch(WidgetTester tester) =>
    tapText(tester, 'Erinnerungen');

/// Taps the slot chip of [hour] (`10:00`).
Future<void> tapSlot(WidgetTester tester, int hour) =>
    tapText(tester, '${hour.toString().padLeft(2, '0')}:00');
