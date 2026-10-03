/// Read model of the habit list for ONE day (today or one of the last seven
/// days) together with the week strip above it. Pure functions of the stored
/// habits, their checks and today.
///
/// The list of today is [HabitDay.isToday]; a past day of the strip is the
/// quick way to correct yesterday and the days before. The 30 day history of
/// one habit lives in `habit_overview.dart`.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/tasks/domain/german_dates.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// How many days the week strip shows: today and the six days before it.
const int habitWeekDays = 7;

/// How completely the habits of one day are done.
enum HabitDayCompletion {
  /// No habit applies on that day.
  noHabits,

  /// Habits apply, none is checked.
  none,

  /// Some, but not all applicable habits are checked.
  partial,

  /// All applicable habits are checked.
  complete,
}

HabitDayCompletion _completionOf(int applicable, int checked) {
  if (applicable == 0) {
    return HabitDayCompletion.noHabits;
  }
  if (checked == 0) {
    return HabitDayCompletion.none;
  }
  return checked >= applicable
      ? HabitDayCompletion.complete
      : HabitDayCompletion.partial;
}

/// One day of the week strip.
@immutable
final class HabitWeekDay {
  const HabitWeekDay({
    required this.date,
    required this.isToday,
    required this.applicableCount,
    required this.checkedCount,
  });

  final LocalDate date;
  final bool isToday;

  /// Habits that apply on this day (archived habits still count for the days
  /// before their archive date).
  final int applicableCount;

  /// Applicable habits that are checked on this day.
  final int checkedCount;

  HabitDayCompletion get completion =>
      _completionOf(applicableCount, checkedCount);

  /// "3 von 5 erledigt" or "Keine Gewohnheit": the text alternative to the dot
  /// under the day.
  String get statusText => applicableCount == 0
      ? 'Keine Gewohnheit'
      : '$checkedCount von $applicableCount erledigt';

  /// Complete label of the day button, e.g. "Heute, Fr., 02.10.: 3 von 5
  /// erledigt".
  String get semanticsLabel =>
      '${isToday ? 'Heute, ' : ''}${formatGermanWeekdayDate(date)}: '
      '$statusText';
}

/// One habit in the list of a day.
@immutable
final class HabitDayItem {
  const HabitDayItem({
    required this.habit,
    required this.checked,
    required this.editable,
    required this.series,
    required this.archivePending,
  });

  final Habit habit;

  /// Whether the habit is checked on the listed day.
  final bool checked;

  /// Whether the check of this day may be set or removed (exactly the rules of
  /// `checkDateError`).
  final bool editable;

  /// The series as of today; null on a past day (the series belongs to today).
  final HabitSeries? series;

  /// Archived from tomorrow on (only reported for the list of today).
  final bool archivePending;

  /// "Ab morgen archiviert" while [archivePending], otherwise null.
  String? get archiveHint => archivePending ? habitArchivePendingHint : null;

  /// "3 Tage in Folge"; null on a past day.
  String? get seriesText =>
      series == null ? null : habitSeriesText(series!.current);

  /// "Erledigt" or "Offen" (state in words, not only by the checkbox).
  String get statusText => checked ? 'Erledigt' : 'Offen';

  /// A complete German semantics label, e.g. "Lesen, erledigt, 3 Tage in Folge,
  /// Ab morgen archiviert".
  String get semanticsLabel => [
    habit.title,
    statusText.toLowerCase(),
    ?seriesText,
    ?archiveHint,
  ].join(', ');
}

/// The habit list of one day plus the week strip.
@immutable
final class HabitDay {
  const HabitDay({
    required this.date,
    required this.today,
    required this.items,
    required this.week,
  });

  /// The listed day.
  final LocalDate date;

  final LocalDate today;

  /// The habits that apply on [date], oldest habit first.
  final List<HabitDayItem> items;

  /// The last [habitWeekDays] days ending today, oldest first.
  final List<HabitWeekDay> week;

  bool get isToday => date == today;

  int get doneCount => items.where((item) => item.checked).length;

  int get totalCount => items.length;

  bool get isEmpty => items.isEmpty;

  HabitDayCompletion get completion => _completionOf(totalCount, doneCount);

  /// "2 von 5 erledigt".
  String get progressText => '$doneCount von $totalCount erledigt';

  /// 0 to 1 for the progress bar; 0 without habits.
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;
}

/// The day the list shows: [selected] when it is one of the strip's days, else
/// today (nothing selected, a day that has left the strip after midnight, or a
/// day in the future).
LocalDate effectiveHabitDay(LocalDate? selected, LocalDate today) {
  if (selected == null ||
      selected.isAfter(today) ||
      selected.isBefore(today.addDays(-(habitWeekDays - 1)))) {
    return today;
  }
  return selected;
}

/// Builds the list of [date] and the week strip from the habits and checks.
///
/// A habit is listed when it applies on [date]: from its start day up to the
/// day before its archive date. The series and the archive hint only belong to
/// the list of today.
HabitDay buildHabitDay({
  required Iterable<Habit> habits,
  required HabitCheckIndex checks,
  required LocalDate date,
  required LocalDate today,
}) {
  final sorted = habits.toList()
    ..sort((a, b) {
      final byCreated = a.createdAtUtc.compareTo(b.createdAtUtc);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  final items = <HabitDayItem>[];
  for (final habit in sorted) {
    if (!habit.appliesOn(date)) {
      continue;
    }
    final checkedDates = checks.datesOf(habit.id);
    final isToday = date == today;
    items.add(
      HabitDayItem(
        habit: habit,
        checked: checkedDates.contains(date),
        editable:
            checkDateError(habit: habit, date: date, today: today) == null,
        series: isToday
            ? computeHabitSeries(
                today: today,
                habitStart: habit.startedOn,
                archivedFrom: habit.archivedFrom,
                isChecked: checkedDates.contains,
              )
            : null,
        archivePending: isToday && habit.isArchivePendingOn(today),
      ),
    );
  }
  final week = <HabitWeekDay>[];
  for (var back = habitWeekDays - 1; back >= 0; back--) {
    final day = today.addDays(-back);
    var applicable = 0;
    var checked = 0;
    for (final habit in sorted) {
      if (habit.appliesOn(day)) {
        applicable++;
        if (checks.isChecked(habit.id, day)) {
          checked++;
        }
      }
    }
    week.add(
      HabitWeekDay(
        date: day,
        isToday: day == today,
        applicableCount: applicable,
        checkedCount: checked,
      ),
    );
  }
  return HabitDay(
    date: date,
    today: today,
    items: List.unmodifiable(items),
    week: List.unmodifiable(week),
  );
}
