import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_overview.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/habit_test_support.dart';

void main() {
  // 2026-10-03 is a Saturday.
  final today = LocalDate(2026, 10, 3);

  Set<LocalDate> days(Iterable<LocalDate> dates) => dates.toSet();

  /// The checked days `today - back` for each offset in [backs].
  Set<LocalDate> checkedBack(Iterable<int> backs) =>
      days(backs.map((back) => today.addDays(-back)));

  HabitDetail detail(
    Set<LocalDate> checked, {
    LocalDate? start,
    LocalDate? archivedFrom,
    LocalDate? asOf,
  }) => buildHabitDetail(
    habit: makeHabit(startedOn: start, archivedFrom: archivedFrom),
    checkedDates: checked,
    today: asOf ?? today,
  );

  group('German texts', () {
    test('series texts name the length and handle zero and one', () {
      expect(habitSeriesText(0), 'Noch keine Serie');
      expect(habitSeriesText(1), '1 Tag in Folge');
      expect(habitSeriesText(3), '3 Tage in Folge');
      expect(habitLongestSeriesText(0), 'Noch keine Serie');
      expect(habitLongestSeriesText(1), 'Längste Serie: 1 Tag');
      expect(habitLongestSeriesText(12), 'Längste Serie: 12 Tage');
    });

    test('the reminder text shows the time or says there is none', () {
      expect(habitReminderText(makeHabit()), 'Keine Erinnerung');
      expect(
        habitReminderText(makeHabit(reminderTime: const LocalTime(8, 5))),
        'Täglich um 08:05 Uhr',
      );
    });
  });

  group('history grid (30 days)', () {
    test('has 30 consecutive days, oldest first, today last', () {
      final history = detail(const {}).history;
      expect(history, hasLength(30));
      expect(history.last.date, today);
      expect(history.last.isToday, isTrue);
      expect(history.first.date, LocalDate(2026, 9, 4));
      expect(history.where((day) => day.isToday), hasLength(1));
      for (var i = 1; i < history.length; i++) {
        expect(
          history[i].date,
          history[i - 1].date.addDays(1),
          reason: 'no gap, no repeated day',
        );
      }
    });

    test('checked days read "erledigt", the others "offen"', () {
      final history = detail(checkedBack([0, 1, 5])).history;
      final byDate = {for (final day in history) day.date: day};
      expect(byDate[today]!.status, HabitDayStatus.checked);
      expect(byDate[today.addDays(-1)]!.status, HabitDayStatus.checked);
      expect(byDate[today.addDays(-2)]!.status, HabitDayStatus.open);
      expect(byDate[today.addDays(-5)]!.checked, isTrue);
      expect(byDate[today]!.semanticsLabel, 'Sa., 03.10.: erledigt');
      expect(
        byDate[today.addDays(-1)]!.semanticsLabel,
        'Fr., 02.10.: erledigt',
      );
      expect(byDate[today.addDays(-2)]!.semanticsLabel, 'Do., 01.10.: offen');
    });

    test('every semantics label has the weekday, the date and the state', () {
      final history = detail(checkedBack([0])).history;
      final pattern = RegExp(
        r'^(Mo|Di|Mi|Do|Fr|Sa|So)\., \d{2}\.\d{2}\.: (erledigt|offen)$',
      );
      for (final day in history) {
        expect(day.semanticsLabel, matches(pattern));
      }
    });

    test(
      'days before the start are "noch nicht begonnen" and not editable',
      () {
        final history = detail(
          checkedBack([0]),
          start: today.addDays(-2),
        ).history;
        final before = history.where(
          (day) => day.status == HabitDayStatus.beforeStart,
        );
        expect(before, hasLength(27));
        expect(history[27].date, today.addDays(-2));
        expect(history[27].applicable, isTrue);
        expect(history[26].status, HabitDayStatus.beforeStart);
        expect(history[26].editable, isFalse);
        expect(history[26].applicable, isFalse);
        expect(history[26].semanticsLabel, 'Mi., 30.09.: noch nicht begonnen');
      },
    );

    test(
      'from the archive date the days are "archiviert" and not editable',
      () {
        final history = detail(
          checkedBack([2, 1]),
          archivedFrom: today.addDays(-1),
        ).history;
        expect(history[27].status, HabitDayStatus.checked, reason: 'day -2');
        expect(history[28].status, HabitDayStatus.archived, reason: 'day -1');
        expect(history[29].status, HabitDayStatus.archived, reason: 'today');
        expect(history[29].editable, isFalse);
        expect(history[28].semanticsLabel, 'Fr., 02.10.: archiviert');
      },
    );

    test('archive date tomorrow: today is still an editable day', () {
      final history = detail(const {}, archivedFrom: today.addDays(1)).history;
      expect(history.last.status, HabitDayStatus.open);
      expect(history.last.editable, isTrue);
    });

    test('checks outside the applicable days are not shown as checked', () {
      final history = detail(
        checkedBack([0, 28]),
        start: today.addDays(-2),
      ).history;
      expect(history.where((day) => day.checked), hasLength(1));
    });

    test('a shorter grid can be requested', () {
      final history = buildHabitHistory(
        habit: makeHabit(),
        checkedDates: const {},
        today: today,
        days: 7,
      );
      expect(history, hasLength(7));
      expect(history.first.date, today.addDays(-6));
    });

    test('is calendar based across the spring DST change of 2026-03-29', () {
      final spring = LocalDate(2026, 3, 30);
      final history = buildHabitHistory(
        habit: makeHabit(startedOn: LocalDate(2026, 1, 1)),
        checkedDates: days([
          LocalDate(2026, 3, 28),
          LocalDate(2026, 3, 29),
          LocalDate(2026, 3, 30),
        ]),
        today: spring,
      );
      final byDate = {for (final day in history) day.date: day};
      expect(history.map((d) => d.date).toSet(), hasLength(30));
      expect(
        byDate[LocalDate(2026, 3, 29)]!.semanticsLabel,
        'So., 29.03.: erledigt',
      );
      expect(byDate[LocalDate(2026, 3, 28)]!.checked, isTrue);
      expect(byDate[LocalDate(2026, 3, 27)]!.checked, isFalse);
    });

    test('is calendar based across the autumn DST change of 2026-10-25', () {
      final history = buildHabitHistory(
        habit: makeHabit(startedOn: LocalDate(2026, 9, 1)),
        checkedDates: days([
          LocalDate(2026, 10, 24),
          LocalDate(2026, 10, 25),
          LocalDate(2026, 10, 26),
        ]),
        today: LocalDate(2026, 10, 26),
      );
      final byDate = {for (final day in history) day.date: day};
      expect(history.map((d) => d.date).toSet(), hasLength(30));
      expect(
        byDate[LocalDate(2026, 10, 25)]!.semanticsLabel,
        'So., 25.10.: erledigt',
      );
      expect(byDate[LocalDate(2026, 10, 26)]!.isToday, isTrue);
    });

    test('is calendar based across a month and a year boundary', () {
      final history = buildHabitHistory(
        habit: makeHabit(startedOn: LocalDate(2026, 11, 1)),
        checkedDates: days([LocalDate(2026, 12, 31), LocalDate(2027, 1, 1)]),
        today: LocalDate(2027, 1, 5),
      );
      expect(history.first.date, LocalDate(2026, 12, 7));
      final byDate = {for (final day in history) day.date: day};
      expect(
        byDate[LocalDate(2026, 12, 31)]!.semanticsLabel,
        'Do., 31.12.: erledigt',
      );
      expect(
        byDate[LocalDate(2027, 1, 1)]!.semanticsLabel,
        'Fr., 01.01.: erledigt',
      );
      expect(history, hasLength(30));
    });

    test('February of a leap year has the 29th', () {
      final history = buildHabitHistory(
        habit: makeHabit(startedOn: LocalDate(2028, 1, 1)),
        checkedDates: days([LocalDate(2028, 2, 29)]),
        today: LocalDate(2028, 3, 1),
      );
      final byDate = {for (final day in history) day.date: day};
      expect(byDate[LocalDate(2028, 2, 29)]!.checked, isTrue);
      expect(byDate[LocalDate(2028, 2, 28)]!.checked, isFalse);
    });
  });

  group('series (same calendar rules as the global streak)', () {
    test('three checked days ending today are a series of three', () {
      final series = detail(checkedBack([0, 1, 2])).series;
      expect(series, const HabitSeries(current: 3, longest: 3));
    });

    test('an unchecked today does not break the series yet', () {
      final result = detail(checkedBack([1, 2, 3]));
      expect(result.series.current, 3);
      expect(result.checkedToday, isFalse);
    });

    test('an unchecked yesterday breaks it', () {
      final series = detail(checkedBack([0, 2, 3])).series;
      expect(series.current, 1);
      expect(series.longest, 2);
      expect(detail(checkedBack([2, 3])).series.current, 0);
    });

    test('the longest series is kept after a gap', () {
      final series = detail(checkedBack([0, 1, 4, 5, 6, 7, 8])).series;
      expect(series.current, 2);
      expect(series.longest, 5);
    });

    test('a habit without checks has no series', () {
      expect(
        detail(const {}).series,
        const HabitSeries(current: 0, longest: 0),
      );
    });

    test('an archived habit keeps the series of its last applicable day', () {
      // Archived from day -1: the last applicable day is day -2.
      final kept = detail(
        checkedBack([2, 3, 4]),
        archivedFrom: today.addDays(-1),
      ).series;
      expect(kept.current, 3);
      final broken = detail(
        checkedBack([3, 4]),
        archivedFrom: today.addDays(-1),
      ).series;
      expect(broken.current, 0, reason: 'the last applicable day was open');
    });

    test('a series runs across the 2026-03-29 DST change', () {
      final series = detail(
        days([
          LocalDate(2026, 3, 28),
          LocalDate(2026, 3, 29),
          LocalDate(2026, 3, 30),
        ]),
        start: LocalDate(2026, 3, 1),
        asOf: LocalDate(2026, 3, 30),
      ).series;
      expect(series, const HabitSeries(current: 3, longest: 3));
    });

    test('a series runs across the 2026-10-25 DST change', () {
      final series = detail(
        days([
          LocalDate(2026, 10, 24),
          LocalDate(2026, 10, 25),
          LocalDate(2026, 10, 26),
        ]),
        start: LocalDate(2026, 10, 1),
        asOf: LocalDate(2026, 10, 26),
      ).series;
      expect(series, const HabitSeries(current: 3, longest: 3));
    });

    test('a series runs across month and year boundaries', () {
      final yearEnd = detail(
        days([
          LocalDate(2026, 12, 30),
          LocalDate(2026, 12, 31),
          LocalDate(2027, 1, 1),
        ]),
        start: LocalDate(2026, 12, 1),
        asOf: LocalDate(2027, 1, 1),
      ).series;
      expect(yearEnd, const HabitSeries(current: 3, longest: 3));
      final monthEnd = detail(
        days([LocalDate(2026, 2, 28), LocalDate(2026, 3, 1)]),
        start: LocalDate(2026, 2, 1),
        asOf: LocalDate(2026, 3, 1),
      ).series;
      expect(monthEnd.current, 2, reason: 'Feb 28 is the last day of Feb 2026');
      final leap = detail(
        days([
          LocalDate(2028, 2, 28),
          LocalDate(2028, 2, 29),
          LocalDate(2028, 3, 1),
        ]),
        start: LocalDate(2028, 2, 1),
        asOf: LocalDate(2028, 3, 1),
      ).series;
      expect(leap.current, 3, reason: '2028 has a February 29');
    });
  });

  group('habit detail', () {
    test('summarises the grid in words', () {
      final result = detail(checkedBack([0, 1, 2, 10]));
      expect(result.checkedDaysInHistory, 4);
      expect(result.applicableDaysInHistory, 30);
      expect(result.historySummaryText, '4 von 30 Tagen erledigt');
      expect(result.checkedToday, isTrue);
      expect(result.currentSeriesText, '3 Tage in Folge');
      expect(result.longestSeriesText, 'Längste Serie: 3 Tage');
      expect(result.reminderText, 'Keine Erinnerung');
    });

    test('a young habit counts only its applicable days', () {
      final result = detail(checkedBack([0]), start: today.addDays(-4));
      expect(result.applicableDaysInHistory, 5);
      expect(result.historySummaryText, '1 von 5 Tagen erledigt');
    });

    test('archive pending and ended are distinguished', () {
      final pending = detail(const {}, archivedFrom: today.addDays(1));
      expect(pending.archivePending, isTrue);
      expect(pending.ended, isFalse);
      expect(pending.archiveHint, 'Ab morgen archiviert');
      final ended = detail(const {}, archivedFrom: today);
      expect(ended.archivePending, isFalse);
      expect(ended.ended, isTrue);
      expect(ended.archiveHint, isNull);
      final active = detail(const {});
      expect(active.archivePending, isFalse);
      expect(active.ended, isFalse);
    });
  });

  group('today overview', () {
    final h1 = makeHabit(
      id: 'a',
      title: 'Lesen',
      createdAtUtc: DateTime.utc(2026, 9, 1, 8),
    );
    final h2 = makeHabit(
      id: 'b',
      title: 'Sport',
      createdAtUtc: DateTime.utc(2026, 9, 2, 8),
    );
    final h3 = makeHabit(
      id: 'c',
      title: 'Wasser',
      createdAtUtc: DateTime.utc(2026, 9, 3, 8),
    );

    HabitCheckIndex checks(Map<String, Iterable<LocalDate>> byHabit) =>
        HabitCheckIndex({
          for (final e in byHabit.entries) e.key: e.value.toSet(),
        });

    test(
      'lists the habits that apply today, oldest first, with their state',
      () {
        final overview = buildHabitsOverview(
          habits: [h3, h1, h2],
          checks: checks({
            'a': [today],
            'b': [today.addDays(-1)],
          }),
          today: today,
        );
        expect(overview.items.map((i) => i.habit.title), [
          'Lesen',
          'Sport',
          'Wasser',
        ]);
        expect(overview.items.map((i) => i.checkedToday), [true, false, false]);
        expect(overview.items.map((i) => i.statusText), [
          'Erledigt',
          'Offen',
          'Offen',
        ]);
        expect(overview.doneCount, 1);
        expect(overview.totalCount, 3);
        expect(overview.progressText, '1 von 3 erledigt');
        expect(overview.isEmpty, isFalse);
        expect(overview.archived, isEmpty);
      },
    );

    test('series per habit follow the checks', () {
      final overview = buildHabitsOverview(
        habits: [h1],
        checks: checks({
          'a': [today, today.addDays(-1), today.addDays(-2)],
        }),
        today: today,
      );
      final item = overview.items.single;
      expect(item.series, const HabitSeries(current: 3, longest: 3));
      expect(item.currentSeriesText, '3 Tage in Folge');
      expect(item.longestSeriesText, 'Längste Serie: 3 Tage');
    });

    test('a habit archived from tomorrow is listed with the hint', () {
      final pending = makeHabit(id: 'p', archivedFrom: today.addDays(1));
      final overview = buildHabitsOverview(
        habits: [pending, h1],
        checks: HabitCheckIndex.empty,
        today: today,
      );
      final item = overview.items.firstWhere((i) => i.habit.id == 'p');
      expect(item.archivePending, isTrue);
      expect(item.archiveHint, 'Ab morgen archiviert');
      expect(
        overview.items.firstWhere((i) => i.habit.id == 'a').archiveHint,
        isNull,
      );
    });

    test('a habit whose archive date is reached moves to the archive list', () {
      final ended = makeHabit(id: 'e', title: 'Alt', archivedFrom: today);
      final older = makeHabit(
        id: 'o',
        title: 'Älter',
        archivedFrom: today.addDays(-5),
      );
      final overview = buildHabitsOverview(
        habits: [older, ended, h1],
        checks: HabitCheckIndex.empty,
        today: today,
      );
      expect(overview.items.map((i) => i.habit.id), ['a']);
      expect(overview.archived.map((i) => i.habit.id), [
        'e',
        'o',
      ], reason: 'most recently archived first');
      expect(overview.totalCount, 1);
    });

    test('a habit that starts after today is not listed yet', () {
      final future = makeHabit(id: 'f', startedOn: today.addDays(1));
      final overview = buildHabitsOverview(
        habits: [future],
        checks: HabitCheckIndex.empty,
        today: today,
      );
      expect(overview.items, isEmpty);
      expect(overview.archived, isEmpty);
      expect(overview.isEmpty, isTrue);
      expect(overview.progressText, '0 von 0 erledigt');
    });

    test('the day change moves "today" while the series survives', () {
      final index = checks({
        'a': [today.addDays(-1), today],
      });
      final tomorrow = today.addDays(1);
      final before = buildHabitsOverview(
        habits: [h1],
        checks: index,
        today: today,
      );
      final after = buildHabitsOverview(
        habits: [h1],
        checks: index,
        today: tomorrow,
      );
      expect(before.items.single.checkedToday, isTrue);
      expect(
        after.items.single.checkedToday,
        isFalse,
        reason: 'a new open day',
      );
      expect(
        after.items.single.series.current,
        2,
        reason: 'runs until the day ends',
      );
      final dayAfter = buildHabitsOverview(
        habits: [h1],
        checks: index,
        today: tomorrow.addDays(1),
      );
      expect(
        dayAfter.items.single.series.current,
        0,
        reason: 'the open day broke it',
      );
      expect(dayAfter.items.single.series.longest, 2);
    });

    test('checks of other habits never leak into a habit', () {
      final overview = buildHabitsOverview(
        habits: [h1, h2],
        checks: checks({
          'a': [today],
        }),
        today: today,
      );
      expect(overview.items.map((i) => i.checkedToday), [true, false]);
    });
  });

  group('check index', () {
    test('answers by habit and day and counts all checks', () {
      final index = HabitCheckIndex({
        'a': {today, today.addDays(-1)},
        'b': {today},
      });
      expect(index.isChecked('a', today), isTrue);
      expect(index.isChecked('a', today.addDays(-2)), isFalse);
      expect(index.isChecked('unknown', today), isFalse);
      expect(index.datesOf('a'), hasLength(2));
      expect(index.datesOf('unknown'), isEmpty);
      expect(index.count, 3);
      expect(HabitCheckIndex.empty.count, 0);
    });
  });
}
