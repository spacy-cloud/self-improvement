/// Read models of the habits: today's list and the detail with the 30-day
/// history grid. Pure functions of the stored habits, their checks and today.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/tasks/domain/german_dates.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// "3 Tage in Folge", "1 Tag in Folge" or "Noch keine Serie".
String habitSeriesText(int days) => switch (days) {
  <= 0 => 'Noch keine Serie',
  1 => '1 Tag in Folge',
  _ => '$days Tage in Folge',
};

/// "Längste Serie: 7 Tage", "Längste Serie: 1 Tag" or "Noch keine Serie".
String habitLongestSeriesText(int days) => switch (days) {
  <= 0 => 'Noch keine Serie',
  1 => 'Längste Serie: 1 Tag',
  _ => 'Längste Serie: $days Tage',
};

/// "Täglich um 08:00 Uhr" or "Keine Erinnerung".
String habitReminderText(Habit habit) {
  final time = habit.reminderTime;
  return time == null ? 'Keine Erinnerung' : 'Täglich um ${time.toIso()} Uhr';
}

/// One habit in today's list.
@immutable
final class HabitTodayItem {
  const HabitTodayItem({
    required this.habit,
    required this.checkedToday,
    required this.series,
    required this.archivePending,
  });

  final Habit habit;

  /// Whether today is checked ("Erledigt") or still open ("Offen").
  final bool checkedToday;

  /// Current and longest series of this habit ([computeHabitSeries]): an
  /// unchecked today does not break the series yet.
  final HabitSeries series;

  /// Archived from tomorrow on, still applicable today.
  final bool archivePending;

  /// "Ab morgen archiviert" while [archivePending], otherwise null.
  String? get archiveHint => archivePending ? habitArchivePendingHint : null;

  /// "3 Tage in Folge" ...
  String get currentSeriesText => habitSeriesText(series.current);

  /// "Längste Serie: 7 Tage" ...
  String get longestSeriesText => habitLongestSeriesText(series.longest);

  /// "Erledigt" or "Offen" (state in words, not only by colour).
  String get statusText => checkedToday ? 'Erledigt' : 'Offen';
}

/// Today's habit list.
@immutable
final class HabitsOverview {
  const HabitsOverview({
    required this.today,
    required this.items,
    required this.archived,
  });

  final LocalDate today;

  /// Habits that apply today (archive-pending ones included), oldest first.
  final List<HabitTodayItem> items;

  /// Habits whose archive date has been reached, most recently archived first.
  /// Their checks and history are kept; they are never reactivated. The V1
  /// design has no archive screen: this list is for a later, optional use.
  final List<HabitTodayItem> archived;

  /// Number of today's habits that are checked.
  int get doneCount => items.where((item) => item.checkedToday).length;

  /// Number of habits that apply today.
  int get totalCount => items.length;

  /// "2 von 5 erledigt".
  String get progressText => '$doneCount von $totalCount erledigt';

  bool get isEmpty => items.isEmpty;
}

/// The state of one day in the history grid.
enum HabitDayStatus {
  /// The habit applies and the day is checked.
  checked('erledigt'),

  /// The habit applies and the day is not checked (yet).
  open('offen'),

  /// The day lies before the habit was created.
  beforeStart('noch nicht begonnen'),

  /// The day is on or after the archive date.
  archived('archiviert');

  const HabitDayStatus(this.text);

  /// German word for the status, the text alternative to the cell colour.
  final String text;
}

/// One cell of the history grid.
@immutable
final class HabitDayEntry {
  const HabitDayEntry({
    required this.date,
    required this.status,
    required this.isToday,
  });

  final LocalDate date;
  final HabitDayStatus status;
  final bool isToday;

  /// Whether the habit applies on this day.
  bool get applicable =>
      status == HabitDayStatus.checked || status == HabitDayStatus.open;

  bool get checked => status == HabitDayStatus.checked;

  /// Whether the UI may offer a tap on this cell: exactly the applicable days.
  /// All grid days lie inside the 30-day window; setting a check on one of them
  /// is always allowed by the repository.
  bool get editable => applicable;

  /// Text for the cell's semantics, for example "Fr., 02.10.: erledigt". Add
  /// "Heute" in front for the cell with [isToday].
  String get semanticsLabel =>
      '${formatGermanWeekdayDate(date)}: ${status.text}';
}

/// The habit detail screen.
@immutable
final class HabitDetail {
  const HabitDetail({
    required this.habit,
    required this.today,
    required this.checkedToday,
    required this.series,
    required this.history,
  });

  final Habit habit;
  final LocalDate today;

  /// Whether today is checked.
  final bool checkedToday;

  final HabitSeries series;

  /// The last [habitHistoryDays] days, oldest first, today last.
  final List<HabitDayEntry> history;

  /// Archived from tomorrow on, still applicable today.
  bool get archivePending => habit.isArchivePendingOn(today);

  /// "Ab morgen archiviert" while [archivePending], otherwise null.
  String? get archiveHint => archivePending ? habitArchivePendingHint : null;

  /// Archived and no longer applicable today (read-only history).
  bool get ended => habit.hasEndedOn(today);

  /// Checked days inside the grid.
  int get checkedDaysInHistory => history.where((day) => day.checked).length;

  /// Days inside the grid on which the habit applied.
  int get applicableDaysInHistory =>
      history.where((day) => day.applicable).length;

  /// "12 von 30 Tagen erledigt" (counted over the days the habit applied).
  String get historySummaryText =>
      '$checkedDaysInHistory von $applicableDaysInHistory Tagen erledigt';

  String get currentSeriesText => habitSeriesText(series.current);

  String get longestSeriesText => habitLongestSeriesText(series.longest);

  String get reminderText => habitReminderText(habit);
}

HabitSeries _seriesOf(
  Habit habit,
  Set<LocalDate> checkedDates,
  LocalDate today,
) => computeHabitSeries(
  today: today,
  habitStart: habit.startedOn,
  archivedFrom: habit.archivedFrom,
  isChecked: checkedDates.contains,
);

HabitTodayItem _todayItem(
  Habit habit,
  Set<LocalDate> checked,
  LocalDate today,
) => HabitTodayItem(
  habit: habit,
  checkedToday: checked.contains(today),
  series: _seriesOf(habit, checked, today),
  archivePending: habit.isArchivePendingOn(today),
);

/// Builds today's list from the habits and their checks.
///
/// A habit is listed while it applies today; one that is archived from
/// tomorrow on is still listed (with [HabitTodayItem.archivePending]). Habits
/// whose archive date is reached move to [HabitsOverview.archived].
HabitsOverview buildHabitsOverview({
  required Iterable<Habit> habits,
  required HabitCheckIndex checks,
  required LocalDate today,
}) {
  final active = <HabitTodayItem>[];
  final ended = <HabitTodayItem>[];
  final sorted = habits.toList()
    ..sort((a, b) {
      final byCreated = a.createdAtUtc.compareTo(b.createdAtUtc);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  for (final habit in sorted) {
    final checked = checks.datesOf(habit.id);
    if (habit.hasEndedOn(today)) {
      ended.add(_todayItem(habit, checked, today));
    } else if (habit.appliesOn(today)) {
      active.add(_todayItem(habit, checked, today));
    }
    // A habit that starts after today (clock moved back) is not listed yet.
  }
  ended.sort((a, b) {
    final byEnd = b.habit.archivedFrom!.compareTo(a.habit.archivedFrom!);
    return byEnd != 0 ? byEnd : a.habit.id.compareTo(b.habit.id);
  });
  return HabitsOverview(
    today: today,
    items: List.unmodifiable(active),
    archived: List.unmodifiable(ended),
  );
}

/// The history grid: the last [days] days ending [today], oldest first.
List<HabitDayEntry> buildHabitHistory({
  required Habit habit,
  required Set<LocalDate> checkedDates,
  required LocalDate today,
  int days = habitHistoryDays,
}) {
  final entries = <HabitDayEntry>[];
  for (var back = days - 1; back >= 0; back--) {
    final date = today.addDays(-back);
    final HabitDayStatus status;
    final archivedFrom = habit.archivedFrom;
    if (date.isBefore(habit.startedOn)) {
      status = HabitDayStatus.beforeStart;
    } else if (archivedFrom != null && !date.isBefore(archivedFrom)) {
      status = HabitDayStatus.archived;
    } else if (checkedDates.contains(date)) {
      status = HabitDayStatus.checked;
    } else {
      status = HabitDayStatus.open;
    }
    entries.add(
      HabitDayEntry(date: date, status: status, isToday: date == today),
    );
  }
  return List.unmodifiable(entries);
}

/// Builds the detail of one habit with its series and the 30-day history.
HabitDetail buildHabitDetail({
  required Habit habit,
  required Set<LocalDate> checkedDates,
  required LocalDate today,
  int historyDays = habitHistoryDays,
}) => HabitDetail(
  habit: habit,
  today: today,
  checkedToday: checkedDates.contains(today),
  series: _seriesOf(habit, checkedDates, today),
  history: buildHabitHistory(
    habit: habit,
    checkedDates: checkedDates,
    today: today,
    days: historyDays,
  ),
);
