import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The reminder time offered when the user switches the reminder on and has not
/// chosen a time yet. A reminder is OFF by default.
const LocalTime defaultHabitReminderTime = LocalTime(20, 0);

/// A stored daily habit (V1: daily frequency and yes/no per day only).
@immutable
final class Habit {
  const Habit({
    required this.id,
    required this.title,
    required this.icon,
    required this.startedOn,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.reminderTime,
    this.archivedFrom,
  });

  final String id;

  /// 1 to 80 characters, trimmed.
  final String title;

  final HabitIcon icon;

  /// The day the habit was created and the first day it applies (frozen).
  final LocalDate startedOn;

  /// Optional daily reminder time; null means the reminder is off.
  final LocalTime? reminderTime;

  /// The first day the habit no longer applies (archiving works from
  /// TOMORROW); null while the habit is active. Archived habits keep their
  /// checks and history and are never reactivated.
  final LocalDate? archivedFrom;

  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  /// Incremented on every change; used for conflict detection (edit, undo).
  final int rowVersion;

  bool get hasReminder => reminderTime != null;

  /// Whether the habit is a daily goal on [day]: from its start day up to the
  /// day before the archive date.
  bool appliesOn(LocalDate day) {
    final end = archivedFrom;
    return !day.isBefore(startedOn) && (end == null || day.isBefore(end));
  }

  /// Archived but still applicable today: the UI shows "Ab morgen archiviert".
  bool isArchivePendingOn(LocalDate today) {
    final end = archivedFrom;
    return end != null && today.isBefore(end);
  }

  /// Archived and no longer applicable today.
  bool hasEndedOn(LocalDate today) {
    final end = archivedFrom;
    return end != null && !today.isBefore(end);
  }
}

/// User input for creating or editing a habit (before validation).
///
/// Only the title, the icon and the reminder time can be edited; the start day
/// is set at creation and history is never rewritten. There is no weekday or
/// time-of-day option: V1 habits are daily.
@immutable
final class HabitDraft {
  const HabitDraft({
    required this.title,
    this.iconKey = 'book',
    this.reminderTime,
  });

  /// A draft for a known [icon].
  HabitDraft.withIcon({
    required this.title,
    HabitIcon icon = defaultHabitIcon,
    this.reminderTime,
  }) : iconKey = icon.key;

  final String title;

  /// One of `book`, `moon`, `drop`, `check`, `flame`, `heart` (default `book`).
  /// The validation rejects every other key with a field error.
  final String iconKey;

  /// Daily reminder time; null leaves the reminder off.
  final LocalTime? reminderTime;
}

/// One stored check: the habit was done on [date].
@immutable
final class HabitCheck {
  const HabitCheck({
    required this.id,
    required this.habitId,
    required this.date,
    required this.checkedAtUtc,
    required this.timezoneId,
    required this.eligibility,
    required this.rowVersion,
  });

  final String id;
  final String habitId;

  /// The day the check belongs to (a retroactive check keeps ITS day).
  final LocalDate date;

  /// When the check was made (a reactivated check gets a fresh time).
  final DateTime checkedAtUtc;

  /// Zone in which the check was made.
  final String timezoneId;

  /// Whether gamification was enabled when this check was made (frozen).
  final bool eligibility;

  final int rowVersion;
}

/// The active checks of all existing habits, indexed by habit.
@immutable
final class HabitCheckIndex {
  const HabitCheckIndex(this._byHabit);

  /// No checks at all.
  static const HabitCheckIndex empty = HabitCheckIndex({});

  final Map<String, Set<LocalDate>> _byHabit;

  /// Whether [habitId] is checked on [date].
  bool isChecked(String habitId, LocalDate date) =>
      _byHabit[habitId]?.contains(date) ?? false;

  /// All days [habitId] is checked on.
  Set<LocalDate> datesOf(String habitId) => _byHabit[habitId] ?? const {};

  /// Total number of checks.
  int get count => _byHabit.values.fold(0, (sum, days) => sum + days.length);
}
