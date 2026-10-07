import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Zones used by the tests.
const String berlin = 'Europe/Berlin';
const String newYork = 'America/New_York';

/// A deterministic UUID shaped id (habit, session).
String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

/// Planner inputs with sensible defaults: reminders wanted, permission
/// granted, every module on, nothing configured.
ReminderInputs plannerInputs({
  required DateTime now,
  String zone = berlin,
  bool wanted = true,
  NotificationPermission permission = NotificationPermission.granted,
  Set<ModuleId>? modules,
  List<WaterReminderRule> water = const [],
  bool waterGoalReached = false,
  List<HabitReminderInput> habits = const [],
  List<TaskReminderInput> tasks = const [],
  FocusEndInput? focus,
}) => ReminderInputs(
  nowUtc: now,
  timeZoneId: zone,
  remindersWanted: wanted,
  permission: permission,
  enabledModules: modules ?? ModuleId.values.toSet(),
  waterRules: water,
  waterGoalReachedToday: waterGoalReached,
  habits: habits,
  tasks: tasks,
  focusSession: focus,
);

/// A water slot rule at [hour]:00.
WaterReminderRule waterSlot(int hour, {String? id, bool enabled = true}) =>
    WaterReminderRule(
      id: id ?? 'rule-$hour',
      time: LocalTime(hour, 0),
      enabled: enabled,
    );

/// The five slots the UI offers.
final List<WaterReminderRule> allWaterSlots = [
  for (final hour in [10, 12, 14, 16, 18]) waterSlot(hour),
];

/// A habit with a reminder (default 09:00), active since the start of 2026.
HabitReminderInput habitInput(
  int n, {
  LocalTime? time = const LocalTime(9, 0),
  LocalDate? started,
  LocalDate? archivedFrom,
  bool deleted = false,
}) => HabitReminderInput(
  id: uuid(n),
  startedOn: started ?? LocalDate(2026, 1, 1),
  reminderTime: time,
  archivedFrom: archivedFrom,
  deleted: deleted,
);

/// An open task whose reminder is due at [at] (UTC).
TaskReminderInput taskInput(int n, {required DateTime at}) =>
    TaskReminderInput(id: uuid(n), reminderAtUtc: at);

/// A running focus session whose current segment started at [segmentStart].
FocusEndInput runningFocus({
  required DateTime segmentStart,
  int planned = 1500,
  int accumulated = 0,
  int session = 90,
}) => FocusEndInput(
  sessionId: uuid(session),
  status: OpenFocusStatus.running,
  plannedSeconds: planned,
  accumulatedSeconds: accumulated,
  segmentStartedAtUtc: segmentStart,
);

/// The semantic keys of a plan, in plan order.
List<String> planKeys(ReminderPlan plan) =>
    plan.notifications.map((n) => n.semanticKey).toList();

/// The planned notification with [key].
PlannedNotification planned(ReminderPlan plan, String key) =>
    plan.notifications.singleWhere((n) => n.semanticKey == key);
