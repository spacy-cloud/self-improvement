import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_day.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/habit_test_support.dart';

void main() {
  final today = LocalDate(2026, 10, 3);

  HabitCheckIndex checks(Map<String, List<LocalDate>> byHabit) =>
      HabitCheckIndex({
        for (final entry in byHabit.entries) entry.key: entry.value.toSet(),
      });

  group('effectiveHabitDay', () {
    test('follows today without a selection', () {
      expect(effectiveHabitDay(null, today), today);
    });

    test('keeps a day of the strip, today and the oldest day included', () {
      expect(effectiveHabitDay(today, today), today);
      expect(effectiveHabitDay(today.addDays(-6), today), today.addDays(-6));
    });

    test('falls back to today for a day that left the strip or is ahead', () {
      expect(effectiveHabitDay(today.addDays(-7), today), today);
      expect(effectiveHabitDay(today.addDays(1), today), today);
    });
  });

  group('week strip', () {
    test('has seven days, oldest first, today last and marked', () {
      final day = buildHabitDay(
        habits: [makeHabit()],
        checks: HabitCheckIndex.empty,
        date: today,
        today: today,
      );
      expect(day.week, hasLength(habitWeekDays));
      expect(day.week.first.date, today.addDays(-6));
      expect(day.week.last.date, today);
      expect(day.week.map((d) => d.isToday), [...List.filled(6, false), true]);
    });

    test('counts the applicable and the checked habits per day', () {
      final a = makeHabit(id: 'a', startedOn: LocalDate(2026, 9, 1));
      final b = makeHabit(
        id: 'b',
        startedOn: LocalDate(2026, 10, 1),
        createdAtUtc: DateTime.utc(2026, 9, 2),
      );
      final day = buildHabitDay(
        habits: [a, b],
        checks: checks({
          'a': [today, today.addDays(-1), today.addDays(-5)],
          'b': [today],
        }),
        date: today,
        today: today,
      );
      HabitWeekDay at(int back) => day.week[6 - back];
      // b starts on 2026-10-01: before that only a applies.
      expect(at(0).applicableCount, 2);
      expect(at(0).checkedCount, 2);
      expect(at(0).completion, HabitDayCompletion.complete);
      expect(at(1).applicableCount, 2);
      expect(at(1).checkedCount, 1);
      expect(at(1).completion, HabitDayCompletion.partial);
      expect(at(2).applicableCount, 2);
      expect(at(2).completion, HabitDayCompletion.none);
      expect(at(3).applicableCount, 1);
      expect(at(5).applicableCount, 1);
      expect(at(5).completion, HabitDayCompletion.complete);
    });

    test('a day without any applicable habit is noHabits with a text', () {
      final day = buildHabitDay(
        habits: [makeHabit(startedOn: today)],
        checks: HabitCheckIndex.empty,
        date: today,
        today: today,
      );
      final yesterday = day.week[5];
      expect(yesterday.completion, HabitDayCompletion.noHabits);
      expect(yesterday.statusText, 'Keine Gewohnheit');
      expect(yesterday.semanticsLabel, 'Fr., 02.10.: Keine Gewohnheit');
      expect(
        day.week.last.semanticsLabel,
        'Heute, Sa., 03.10.: 0 von 1 erledigt',
      );
    });

    test('an archived habit counts up to the day before its archive date', () {
      final habit = makeHabit(
        startedOn: LocalDate(2026, 9, 1),
        archivedFrom: LocalDate(2026, 10, 1),
      );
      final day = buildHabitDay(
        habits: [habit],
        checks: HabitCheckIndex.empty,
        date: today,
        today: today,
      );
      expect(day.week[2].date, LocalDate(2026, 9, 29));
      expect(day.week[2].applicableCount, 1);
      expect(day.week[3].date, LocalDate(2026, 9, 30));
      expect(day.week[3].applicableCount, 1);
      expect(day.week[4].date, LocalDate(2026, 10, 1));
      expect(day.week[4].applicableCount, 0);
    });
  });

  group('habits of a day', () {
    test('lists the habits that apply, oldest habit first, with the state', () {
      final first = makeHabit(
        id: 'a',
        title: 'Lesen',
        createdAtUtc: DateTime.utc(2026, 9, 1),
      );
      final second = makeHabit(
        id: 'b',
        title: 'Dehnen',
        createdAtUtc: DateTime.utc(2026, 9, 2),
      );
      final day = buildHabitDay(
        habits: [second, first],
        checks: checks({
          'a': [today],
        }),
        date: today,
        today: today,
      );
      expect(day.items.map((i) => i.habit.title), ['Lesen', 'Dehnen']);
      expect(day.items.map((i) => i.checked), [true, false]);
      expect(day.doneCount, 1);
      expect(day.totalCount, 2);
      expect(day.progressText, '1 von 2 erledigt');
      expect(day.progress, 0.5);
      expect(day.completion, HabitDayCompletion.partial);
      expect(day.items.every((i) => i.editable), isTrue);
    });

    test('today carries the series and the archive hint, a past day not', () {
      final habit = makeHabit(
        startedOn: LocalDate(2026, 9, 25),
        archivedFrom: today.addDays(1),
      );
      final index = checks({
        'h1': [today, today.addDays(-1), today.addDays(-3)],
      });
      final now = buildHabitDay(
        habits: [habit],
        checks: index,
        date: today,
        today: today,
      );
      expect(now.isToday, isTrue);
      expect(now.items.single.series!.current, 2);
      expect(now.items.single.seriesText, '2 Tage in Folge');
      expect(now.items.single.archivePending, isTrue);
      expect(now.items.single.archiveHint, 'Ab morgen archiviert');
      expect(
        now.items.single.semanticsLabel,
        'Lesen, erledigt, 2 Tage in Folge, Ab morgen archiviert',
      );

      final past = buildHabitDay(
        habits: [habit],
        checks: index,
        date: today.addDays(-1),
        today: today,
      );
      expect(past.isToday, isFalse);
      expect(past.items.single.series, isNull);
      expect(past.items.single.seriesText, isNull);
      expect(past.items.single.archivePending, isFalse);
      expect(past.items.single.semanticsLabel, 'Lesen, erledigt');
    });

    test('a past day lists a habit that has applied then, but not before', () {
      final started = makeHabit(startedOn: today.addDays(-2));
      final past = buildHabitDay(
        habits: [started],
        checks: HabitCheckIndex.empty,
        date: today.addDays(-3),
        today: today,
      );
      expect(past.isEmpty, isTrue);
      expect(past.completion, HabitDayCompletion.noHabits);
      final onStart = buildHabitDay(
        habits: [started],
        checks: HabitCheckIndex.empty,
        date: today.addDays(-2),
        today: today,
      );
      expect(onStart.items, hasLength(1));
      expect(onStart.items.single.editable, isTrue);
    });

    test(
      'an ended habit still appears on the days before its archive date',
      () {
        final ended = makeHabit(
          startedOn: LocalDate(2026, 9, 1),
          archivedFrom: today.addDays(-1),
        );
        expect(
          buildHabitDay(
            habits: [ended],
            checks: HabitCheckIndex.empty,
            date: today,
            today: today,
          ).isEmpty,
          isTrue,
        );
        final before = buildHabitDay(
          habits: [ended],
          checks: HabitCheckIndex.empty,
          date: today.addDays(-3),
          today: today,
        );
        expect(before.items, hasLength(1));
        expect(before.items.single.editable, isTrue);
      },
    );

    test('the encouragement inputs: nothing to do is not "complete"', () {
      final day = buildHabitDay(
        habits: const [],
        checks: HabitCheckIndex.empty,
        date: today,
        today: today,
      );
      expect(day.isEmpty, isTrue);
      expect(day.progress, 0);
      expect(day.completion, HabitDayCompletion.noHabits);
    });
  });
}
