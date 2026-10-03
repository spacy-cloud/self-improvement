import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/notifications/application/notification_entry_resolver.dart';
import 'package:self_improvement/core/notifications/application/reminder_auto_reconciler.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/notifications/platform/device_time_zone.dart';
import 'package:self_improvement/core/notifications/platform/flutter_local_notifications_reminder_platform.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// The platform adapter. The default is the real
/// `flutter_local_notifications` adapter; tests override it with
/// `FakeReminderPlatform`. The app shell calls `initialize()` on it once at
/// start, before the first frame.
final reminderPlatformProvider = Provider<ReminderPlatform>((ref) {
  final platform = FlutterLocalNotificationsReminderPlatform();
  ref.onDispose(platform.dispose);
  return platform;
});

/// Reads the device time zone (for the app's clock and zone change detection).
final deviceTimeZoneSourceProvider = Provider<DeviceTimeZoneSource>(
  (ref) => const FlutterTimezoneSource(),
);

/// INJECTED: whether today's water goal is already reached. The default is
/// "never", so reminders are not suppressed until the app wires the real day
/// status (override with a function that answers from committed data). When it
/// returns true, today's remaining water reminders are cancelled and tomorrow's
/// stay.
final waterGoalReachedTodayProvider = Provider<Future<bool> Function()>(
  (ref) =>
      () async => false,
);

/// INJECTED: the open focus session. The default reads it straight from the
/// `focus_sessions` table; override to replace the source.
final reminderFocusSessionProvider =
    Provider<Future<FocusEndInput?> Function()>((ref) {
      final database = ref.watch(appDatabaseProvider);
      return () => ReminderInputReader.readOpenFocusSession(database);
    });

final reminderPlannerProvider = Provider<ReminderPlanner>(
  (ref) => ReminderPlanner(clock: ref.watch(clockProvider)),
);

final scheduledNotificationRepositoryProvider =
    Provider<ScheduledNotificationRepository>(
      (ref) => ScheduledNotificationRepository(ref.watch(appDatabaseProvider)),
    );

/// Master switch and water slots (commands).
final reminderPreferencesRepositoryProvider =
    Provider<ReminderPreferencesRepository>(
      (ref) => ReminderPreferencesRepository(
        database: ref.watch(appDatabaseProvider),
        runner: ref.watch(commandRunnerProvider),
      ),
    );

final reminderInputReaderProvider = Provider<ReminderInputReader>(
  (ref) => ReminderInputReader(
    database: ref.watch(appDatabaseProvider),
    modules: ref.watch(moduleStatusRepositoryProvider),
    waterGoalReachedToday: ref.watch(waterGoalReachedTodayProvider),
    focusSession: ref.watch(reminderFocusSessionProvider),
  ),
);

/// The reminder engine. Call `reconcile()` on app start, resume and time zone
/// change; see `ReminderService` for the full list of triggers and the honest
/// limits of local notifications.
final reminderServiceProvider = Provider<ReminderService>((ref) {
  final service = ReminderService(
    inputs: ref.watch(reminderInputReaderProvider),
    scheduled: ref.watch(scheduledNotificationRepositoryProvider),
    preferences: ref.watch(reminderPreferencesRepositoryProvider),
    platform: ref.watch(reminderPlatformProvider),
    clock: ref.watch(clockProvider),
    planner: ref.watch(reminderPlannerProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Starts the reconcile trigger on database changes (and one run for the app
/// start). Read it once at the app root after bootstrap.
final reminderAutoReconcileProvider = Provider<ReminderAutoReconciler>((ref) {
  final reconciler = ReminderAutoReconciler(
    database: ref.watch(appDatabaseProvider),
    service: ref.watch(reminderServiceProvider),
  )..start();
  ref.onDispose(reconciler.dispose);
  return reconciler;
});

/// Wish, permission, count and last error of the reminder feature; updated
/// after every reconcile run.
final reminderStatusProvider = StreamProvider<ReminderStatus>(
  (ref) => ref.watch(reminderServiceProvider).watchStatus(),
);

/// The V1 "notification list": the planned reminders, soonest first. There is
/// no delivery history. Rows of an unknown kind are left out.
final plannedRemindersProvider = StreamProvider<List<ScheduledReminder>>(
  (ref) => ref
      .watch(scheduledNotificationRepositoryProvider)
      .watchAll()
      .map(
        (rows) => [
          for (final row in rows)
            if (row.kind != null) row,
        ],
      ),
);

/// The enabled water slot hours (subset of 10, 12, 14, 16, 18).
final waterReminderHoursProvider = StreamProvider<Set<int>>(
  (ref) =>
      ref.watch(reminderPreferencesRepositoryProvider).watchEnabledWaterHours(),
);

/// Resolves a notification payload to a safe in-app route.
final notificationEntryResolverProvider = Provider<NotificationEntryResolver>(
  (ref) => NotificationEntryResolver(
    database: ref.watch(appDatabaseProvider),
    modules: ref.watch(moduleStatusRepositoryProvider),
    clock: ref.watch(clockProvider),
  ),
);
