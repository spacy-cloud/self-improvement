import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/notifications/platform/fake_reminder_platform.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Real in-memory database, fake clock (Europe/Berlin), fake platform and the
/// real reminder service, wired like the app wires them.
///
/// The default "now" is 2026-10-03 06:30Z = 08:30 in Berlin (summer time), so
/// the 10:00 water slot of the day is still ahead.
final class ReminderHarness {
  ReminderHarness._({
    required this.data,
    required this.platform,
    required this.preferences,
    required this.scheduled,
    required this.service,
    required this.goal,
  });

  final DataHarness data;
  final FakeReminderPlatform platform;
  final ReminderPreferencesRepository preferences;
  final ScheduledNotificationRepository scheduled;
  final ReminderService service;

  /// The injected "today's water goal is reached" fact.
  final GoalSwitch goal;

  static Future<ReminderHarness> create({
    String nowIso = '2026-10-03T06:30:00Z',
    String zone = 'Europe/Berlin',
    NotificationPermission permission = NotificationPermission.granted,
    ScheduledNotificationRepository Function(AppDatabase database)?
    scheduledFactory,
  }) async {
    final data = await DataHarness.create(nowIso: nowIso, timeZoneId: zone);
    final platform = FakeReminderPlatform(
      permission: permission,
      clock: data.clock,
    );
    final preferences = ReminderPreferencesRepository(
      database: data.database,
      runner: data.runner,
    );
    final scheduled =
        scheduledFactory?.call(data.database) ??
        ScheduledNotificationRepository(data.database);
    final goal = GoalSwitch();
    final service = ReminderService(
      inputs: ReminderInputReader(
        database: data.database,
        modules: data.moduleStatus,
        waterGoalReachedToday: () async => goal.reached,
      ),
      scheduled: scheduled,
      preferences: preferences,
      platform: platform,
      clock: data.clock,
    );
    return ReminderHarness._(
      data: data,
      platform: platform,
      preferences: preferences,
      scheduled: scheduled,
      service: service,
      goal: goal,
    );
  }

  /// A second service over the same database and platform: a new process.
  ReminderService newProcess() => ReminderService(
    inputs: ReminderInputReader(
      database: data.database,
      modules: data.moduleStatus,
      waterGoalReachedToday: () async => goal.reached,
    ),
    scheduled: scheduled,
    preferences: preferences,
    platform: platform,
    clock: data.clock,
  );

  AppDatabase get database => data.database;

  Future<void> dispose() async {
    await service.dispose();
    await platform.dispose();
    await data.dispose();
  }

  // ------------------------------------------------------------- settings

  /// Switches the master switch (the wish of the user) without reconciling.
  Future<void> setWanted(bool wanted) async {
    await preferences.setNotificationsEnabled(
      commandId: data.ids.newId(),
      enabled: wanted,
    );
  }

  /// Sets the enabled water slot hours without reconciling.
  Future<void> setWaterHours(Set<int> hours) async {
    await preferences.setWaterSlots(commandId: data.ids.newId(), hours: hours);
  }

  /// Switches a module on or off (a new history row).
  Future<void> setModule(ModuleId module, {required bool enabled}) async {
    await database
        .into(database.moduleStatusHistory)
        .insert(
          ModuleStatusHistoryCompanion.insert(
            id: data.ids.newId(),
            moduleId: module.key,
            effectiveAtUtc: data.clock.nowUtc(),
            localDate: data.clock.today(),
            enabled: enabled,
          ),
        );
  }

  // --------------------------------------------------------------- habits

  /// Inserts a habit and returns its id.
  Future<String> addHabit({
    LocalTime? time = const LocalTime(18, 0),
    LocalDate? started,
    LocalDate? archivedFrom,
    bool deleted = false,
    String title = 'Lesen',
  }) async {
    final id = data.ids.newId();
    final now = data.clock.nowUtc();
    await database
        .into(database.habits)
        .insert(
          HabitsCompanion.insert(
            id: id,
            title: title,
            startedLocalDate: started ?? LocalDate(2026, 1, 1),
            reminderLocalTime: Value(time),
            archivedFromDate: Value(archivedFrom),
            deletedAtUtc: Value(deleted ? now : null),
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    return id;
  }

  Future<void> updateHabit(
    String id, {
    Value<LocalTime?> time = const Value.absent(),
    Value<LocalDate?> archivedFrom = const Value.absent(),
    Value<DateTime?> deletedAt = const Value.absent(),
  }) async {
    await (database.update(
      database.habits,
    )..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        reminderLocalTime: time,
        archivedFromDate: archivedFrom,
        deletedAtUtc: deletedAt,
      ),
    );
  }

  // ---------------------------------------------------------------- focus

  /// Inserts an open focus session and returns its id. A running session
  /// needs [segmentStart].
  Future<String> addFocus({
    String status = 'running',
    int planned = 1500,
    int accumulated = 0,
    DateTime? segmentStart,
  }) async {
    final id = data.ids.newId();
    final now = data.clock.nowUtc();
    await database
        .into(database.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            category: 'reading',
            plannedSeconds: planned,
            accumulatedSeconds: Value(accumulated),
            segmentStartedAtUtc: Value(segmentStart),
            startedAtUtc: now,
            timezoneId: data.clock.timeZoneId,
            status: status,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        );
    return id;
  }

  /// Pauses a session: the segment is folded into the accumulated seconds.
  Future<void> pauseFocus(String id, {required int accumulated}) async {
    await (database.update(
      database.focusSessions,
    )..where((s) => s.id.equals(id))).write(
      FocusSessionsCompanion(
        status: const Value('paused'),
        accumulatedSeconds: Value(accumulated),
        segmentStartedAtUtc: const Value(null),
      ),
    );
  }

  /// Resumes a paused session with a new segment starting now.
  Future<void> resumeFocus(String id) async {
    await (database.update(
      database.focusSessions,
    )..where((s) => s.id.equals(id))).write(
      FocusSessionsCompanion(
        status: const Value('running'),
        segmentStartedAtUtc: Value(data.clock.nowUtc()),
      ),
    );
  }

  /// Ends the session: `completed` (with a business date) or `discarded`.
  Future<void> closeFocus(String id, {required bool completed}) async {
    await (database.update(
      database.focusSessions,
    )..where((s) => s.id.equals(id))).write(
      FocusSessionsCompanion(
        status: Value(completed ? 'completed' : 'discarded'),
        segmentStartedAtUtc: const Value(null),
        completedLocalDate: Value(completed ? data.clock.today() : null),
        endedAtUtc: Value(data.clock.nowUtc()),
      ),
    );
  }

  // -------------------------------------------------------------- reading

  Future<List<ScheduledReminder>> rows() => scheduled.all();

  /// The ids of all rows.
  Future<Set<int>> rowIds() async => {
    for (final r in await rows()) r.notificationId,
  };

  /// Row keys, soonest first.
  Future<List<String>> rowKeys() async => [
    for (final r in await rows()) r.semanticKey,
  ];

  Future<int> receiptCount() async =>
      (await database.select(database.commandReceipts).get()).length;
}

/// Mutable flag behind the injected water goal predicate.
final class GoalSwitch {
  bool reached = false;
}
