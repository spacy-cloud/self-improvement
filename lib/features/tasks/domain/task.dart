import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/tasks/domain/german_dates.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The optional reminder of a task (BS-111): the instant the notification is
/// due, with the local date and the zone frozen when the reminder was set (the
/// time model of the facts, see `FrozenInstant`).
///
/// The three values always belong together: a task has all of them or none.
/// The instant is the truth: the notification is due at exactly [atUtc],
/// whatever zone the device is in later. [localDate] and [timezoneId] record
/// the business date of the moment the user chose it.
@immutable
final class TaskReminder {
  const TaskReminder({
    required this.atUtc,
    required this.localDate,
    required this.timezoneId,
  });

  /// When the notification is due (UTC, whole minutes).
  final DateTime atUtc;

  /// Local date of [atUtc] in [timezoneId], frozen when the reminder was set.
  final LocalDate localDate;

  /// IANA zone the reminder was set in.
  final String timezoneId;

  @override
  bool operator ==(Object other) =>
      other is TaskReminder &&
      other.atUtc.isAtSameMomentAs(atUtc) &&
      other.localDate == localDate &&
      other.timezoneId == timezoneId;

  @override
  int get hashCode =>
      Object.hash(atUtc.millisecondsSinceEpoch, localDate, timezoneId);

  @override
  String toString() => 'TaskReminder($atUtc, $localDate, $timezoneId)';
}

/// A stored task. Open means [completedAtUtc] is null.
///
/// The completion fields always belong together: they are all set or all null.
/// A task can only be completed once per state; reopening clears the whole
/// completion (including its XP eligibility flag) and a later completion is a
/// new one with a new flag.
///
/// The [reminder] is independent of the completion: completing a task keeps
/// it (it only stops being delivered), so reopening the task or undoing the
/// completion brings the reminder back if its time is still ahead.
@immutable
final class Task {
  const Task({
    required this.id,
    required this.title,
    required this.priority,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.description,
    this.dueDate,
    this.tags = const [],
    this.completedAtUtc,
    this.completedLocalDate,
    this.completionTimezoneId,
    this.completionEligibility,
    this.reminder,
  });

  final String id;

  /// 1 to 120 characters, trimmed.
  final String title;

  /// Optional free text of at most 1.000 characters, trimmed; null when blank.
  final String? description;

  final TaskPriority priority;

  /// Optional due DAY (no time of day).
  final LocalDate? dueDate;

  /// Up to five tags of 1 to 20 characters, trimmed and deduplicated
  /// case-insensitively (first spelling kept).
  final List<String> tags;

  /// When the current completion happened; null while open.
  final DateTime? completedAtUtc;

  /// Business date of the current completion, frozen in the zone of that moment.
  final LocalDate? completedLocalDate;

  /// IANA zone of the current completion.
  final String? completionTimezoneId;

  /// Whether gamification was enabled when the current completion happened
  /// (frozen, never recomputed). Null while open.
  final bool? completionEligibility;

  /// The optional reminder; null when none is set.
  final TaskReminder? reminder;

  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  /// Incremented on every change; used for conflict detection (edit, undo).
  final int rowVersion;

  bool get isCompleted => completedAtUtc != null;

  bool get isOpen => !isCompleted;

  /// Overdue: open and the due date lies before [today]. The UI must show a
  /// TEXT for this state in addition to any colour (see [taskDueText]).
  bool isOverdueOn(LocalDate today) {
    final due = dueDate;
    return isOpen && due != null && due.isBefore(today);
  }

  /// Open and due exactly [today].
  bool isDueTodayOn(LocalDate today) => isOpen && dueDate == today;

  /// Whether a notification is still to come: the task is open and its
  /// reminder lies after [nowUtc]. A completed task and a reminder that has
  /// passed deliver nothing.
  bool hasUpcomingReminder(DateTime nowUtc) {
    final due = reminder?.atUtc;
    return isOpen && due != null && due.isAfter(nowUtc);
  }

  /// Whether the task belongs on today's dashboard list: open and without a
  /// due date or due up to and including [today]. Future tasks only show up in
  /// the "Alle" list.
  bool appliesOn(LocalDate today) {
    final due = dueDate;
    return isOpen && (due == null || due <= today);
  }
}

/// User input for creating or editing a task (before validation).
///
/// Editing never touches the completion; it only changes these six fields.
@immutable
final class TaskDraft {
  const TaskDraft({
    required this.title,
    this.description,
    this.priority = defaultTaskPriority,
    this.dueDate,
    this.tags = const [],
    this.reminderAtUtc,
  });

  final String title;
  final String? description;
  final TaskPriority priority;
  final LocalDate? dueDate;
  final List<String> tags;

  /// The instant of the optional reminder (UTC); null means no reminder. On
  /// saving, the command freezes the local date and the zone with it.
  final DateTime? reminderAtUtc;
}

/// A short German due text for list rows and semantics, or null without a due
/// date. Open tasks past their day read "Überfällig seit 02.10.2026"; the word
/// is the text alternative to the overdue colour.
String? taskDueText(Task task, LocalDate today) {
  final due = task.dueDate;
  if (due == null) {
    return null;
  }
  if (task.isCompleted) {
    return 'Fällig am ${formatGermanDate(due)}';
  }
  if (due.isBefore(today)) {
    return 'Überfällig seit ${formatGermanDate(due)}';
  }
  if (due == today) {
    return 'Heute fällig';
  }
  if (due == today.addDays(1)) {
    return 'Morgen fällig';
  }
  return 'Fällig am ${formatGermanDate(due)}';
}
