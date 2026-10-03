import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';

/// Gathers the plain facts the planner needs, once per run.
///
/// Reads the master switch, the module statuses, the water rules, the habits
/// with a reminder time and the open focus session straight from the database.
/// Two facts come from outside and are injected: whether today's water goal is
/// reached (it depends on goals and entries, which belong to other features)
/// and, optionally, the open focus session.
class ReminderInputReader {
  ReminderInputReader({
    required this._database,
    required this._modules,
    required this._waterGoalReachedToday,
    this._focusSession,
  });

  final AppDatabase _database;
  final ModuleStatusRepository _modules;
  final Future<bool> Function() _waterGoalReachedToday;
  final Future<FocusEndInput?> Function()? _focusSession;

  /// Captures all inputs for a run at [nowUtc] in [timeZoneId], with the
  /// [permission] the device reported in this run.
  Future<ReminderInputs> read({
    required DateTime nowUtc,
    required String timeZoneId,
    required NotificationPermission permission,
  }) async {
    final settings = await _database
        .select(_database.appSettings)
        .getSingleOrNull();
    final statuses = await _modules.statuses();
    final waterRules = await _readWaterRules();
    final habits = await _readHabits();
    final waterReached = await _waterGoalReachedToday();
    final focus =
        await (_focusSession?.call() ?? readOpenFocusSession(_database));
    return ReminderInputs(
      nowUtc: nowUtc,
      timeZoneId: timeZoneId,
      remindersWanted: settings?.notificationsEnabled ?? false,
      permission: permission,
      enabledModules: {
        for (final entry in statuses.entries)
          if (entry.value) entry.key,
      },
      waterRules: waterRules,
      waterGoalReachedToday: waterReached,
      habits: habits,
      focusSession: focus,
    );
  }

  Future<List<WaterReminderRule>> _readWaterRules() async {
    final rows = await (_database.select(
      _database.reminderRules,
    )..where((r) => r.kind.equals(ReminderKind.water.key))).get();
    return [
      for (final row in rows)
        if (row.localTime != null)
          WaterReminderRule(
            id: row.id,
            time: row.localTime!,
            enabled: row.enabled,
          ),
    ];
  }

  /// Habits with a reminder time. Soft deleted rows are included and flagged;
  /// the planner is the single place that decides which habits apply.
  Future<List<HabitReminderInput>> _readHabits() async {
    final rows = await (_database.select(
      _database.habits,
    )..where((h) => h.reminderLocalTime.isNotNull())).get();
    return [
      for (final row in rows)
        HabitReminderInput(
          id: row.id,
          startedOn: row.startedLocalDate,
          reminderTime: row.reminderLocalTime,
          archivedFrom: row.archivedFromDate,
          deleted: row.deletedAtUtc != null,
        ),
    ];
  }

  /// The open focus session straight from `focus_sessions` (at most one row
  /// can be open), or `null` when none is open. This is the default of the
  /// injectable focus input.
  static Future<FocusEndInput?> readOpenFocusSession(
    AppDatabase database,
  ) async {
    final row =
        await (database.select(database.focusSessions)..where(
              (s) =>
                  s.status.isIn(OpenFocusStatus.keys) & s.deletedAtUtc.isNull(),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final status = OpenFocusStatus.tryParse(row.status);
    if (status == null) {
      return null;
    }
    return FocusEndInput(
      sessionId: row.id,
      status: status,
      plannedSeconds: row.plannedSeconds,
      accumulatedSeconds: row.accumulatedSeconds,
      segmentStartedAtUtc: row.segmentStartedAtUtc,
    );
  }
}
