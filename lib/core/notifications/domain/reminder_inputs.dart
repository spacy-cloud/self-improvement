import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// A water slot rule (`reminder_rules` row of kind `water`).
@immutable
final class WaterReminderRule {
  const WaterReminderRule({
    required this.id,
    required this.time,
    this.enabled = true,
  });

  /// The `reminder_rules.id`.
  final String id;

  /// Wall clock time of the slot (`HH:00` for the slots the UI offers).
  final LocalTime time;

  final bool enabled;
}

/// What the planner needs to know about a habit.
@immutable
final class HabitReminderInput {
  const HabitReminderInput({
    required this.id,
    required this.startedOn,
    this.reminderTime,
    this.archivedFrom,
    this.deleted = false,
  });

  final String id;

  /// First day the habit applies.
  final LocalDate startedOn;

  /// Individual daily reminder time; `null` means no reminder.
  final LocalTime? reminderTime;

  /// First day the habit no longer applies (archiving works from tomorrow);
  /// `null` while active. On the archive day itself the habit still applies.
  final LocalDate? archivedFrom;

  /// Soft deleted habits are never reminded.
  final bool deleted;

  /// Whether the habit applies on [day].
  bool appliesOn(LocalDate day) =>
      !deleted &&
      day >= startedOn &&
      (archivedFrom == null || day < archivedFrom!);
}

/// State of an open focus session.
enum OpenFocusStatus {
  running,
  paused,
  awaitingConfirmation;

  /// The state for a persisted `focus_sessions.status`; `null` for the closed
  /// states `completed` and `discarded` and for unknown keys.
  static OpenFocusStatus? tryParse(String key) => switch (key) {
    'running' => OpenFocusStatus.running,
    'paused' => OpenFocusStatus.paused,
    'awaiting_confirmation' => OpenFocusStatus.awaitingConfirmation,
    _ => null,
  };

  /// The persisted key.
  String get key => switch (this) {
    OpenFocusStatus.running => 'running',
    OpenFocusStatus.paused => 'paused',
    OpenFocusStatus.awaitingConfirmation => 'awaiting_confirmation',
  };

  /// Keys of all open states, as stored in `focus_sessions.status`.
  static List<String> get keys => SchemaKeys.focusOpenStatuses;
}

/// The open focus session as persisted (segment based, never ticker based).
@immutable
final class FocusEndInput {
  const FocusEndInput({
    required this.sessionId,
    required this.status,
    required this.plannedSeconds,
    required this.accumulatedSeconds,
    this.segmentStartedAtUtc,
  });

  final String sessionId;
  final OpenFocusStatus status;

  /// Planned countdown in seconds.
  final int plannedSeconds;

  /// Seconds already accumulated in finished segments.
  final int accumulatedSeconds;

  /// Start of the running segment; only set while running.
  final DateTime? segmentStartedAtUtc;

  bool get isRunning => status == OpenFocusStatus.running;

  /// The instant the countdown reaches zero: the start of the running segment
  /// plus the remaining planned seconds. `null` unless the session is running.
  ///
  /// This is exactly the moment at which the persisted elapsed time reaches
  /// the plan, also after a clock correction: the timer treats a negative
  /// segment length as zero, which only delays the same end instant.
  DateTime? get endsAtUtc {
    final start = segmentStartedAtUtc;
    if (!isRunning || start == null) {
      return null;
    }
    return start.add(Duration(seconds: plannedSeconds - accumulatedSeconds));
  }
}

/// Everything the planner reads, captured once per run. All instants are UTC;
/// calendar days are computed from [nowUtc] in [timeZoneId].
@immutable
final class ReminderInputs {
  const ReminderInputs({
    required this.nowUtc,
    required this.timeZoneId,
    required this.remindersWanted,
    required this.permission,
    required this.enabledModules,
    this.waterRules = const [],
    this.waterGoalReachedToday = false,
    this.habits = const [],
    this.focusSession,
  });

  /// The instant this run started. Nothing at or before it is planned.
  final DateTime nowUtc;

  /// IANA zone of the device in this run.
  final String timeZoneId;

  /// The master switch: `app_settings.notifications_enabled`.
  final bool remindersWanted;

  /// The real permission as read from the device.
  final NotificationPermission permission;

  /// The modules that are switched on right now.
  final Set<ModuleId> enabledModules;

  final List<WaterReminderRule> waterRules;

  /// Whether today's water goal is already reached. Remaining water reminders
  /// of today are dropped; tomorrow's stay.
  final bool waterGoalReachedToday;

  final List<HabitReminderInput> habits;

  /// The open focus session (running, paused or awaiting confirmation).
  final FocusEndInput? focusSession;

  bool isModuleEnabled(ModuleId module) => enabledModules.contains(module);
}
