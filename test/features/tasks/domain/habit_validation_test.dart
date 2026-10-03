import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/habit_test_support.dart';
import '../support/task_test_support.dart';

void main() {
  Map<String, String> errorsOf(HabitDraft draft) {
    try {
      validateHabitDraft(draft);
      return const {};
    } on ValidationFailure catch (failure) {
      return failure.fieldErrors;
    }
  }

  group('title (1 to 80 characters after trimming)', () {
    test('an empty or blank title is rejected with a hint', () {
      for (final title in ['', ' ', ' \t ']) {
        expect(errorsOf(HabitDraft(title: title)), {
          HabitFields.title: 'Bitte gib einen Titel ein.',
        }, reason: '"$title"');
      }
    });

    test('1 and 80 characters are accepted, 81 are rejected', () {
      expect(errorsOf(HabitDraft(title: 'a')), isEmpty);
      expect(errorsOf(HabitDraft(title: 'a' * 80)), isEmpty);
      expect(errorsOf(HabitDraft(title: 'a' * 81)), {
        HabitFields.title: 'Der Titel darf höchstens 80 Zeichen lang sein.',
      });
    });

    test('the title is trimmed before counting and stored trimmed', () {
      final result = validateHabitDraft(HabitDraft(title: '  ${'a' * 80}  '));
      expect(result.title, 'a' * 80);
    });

    test('characters are counted like the database does (code points)', () {
      expect(errorsOf(HabitDraft(title: astralChar * 80)), isEmpty);
      expect(errorsOf(HabitDraft(title: astralChar * 81)), isNotEmpty);
    });
  });

  group('icon key (book, moon, drop, check, flame, heart)', () {
    test('every known key is accepted, the default is book', () {
      for (final key in SchemaKeys.habitIcons) {
        expect(errorsOf(HabitDraft(title: 'x', iconKey: key)), isEmpty);
      }
      expect(const HabitDraft(title: 'x').iconKey, 'book');
      expect(defaultHabitIcon, HabitIcon.book);
    });

    test('an unknown key is rejected with a field error, never replaced', () {
      for (final key in ['rocket', '', 'Book', ' book', 'BOOK', 'star']) {
        expect(errorsOf(HabitDraft(title: 'x', iconKey: key)), {
          HabitFields.icon: 'Bitte wähle ein Symbol aus der Liste.',
        }, reason: '"$key"');
      }
    });

    test('title and icon errors are reported together', () {
      expect(errorsOf(const HabitDraft(title: '', iconKey: 'rocket')).keys, {
        HabitFields.title,
        HabitFields.icon,
      });
    });

    test('the enum equals the database contract and has German labels', () {
      expect(
        HabitIcon.values.map((i) => i.key).toList(),
        SchemaKeys.habitIcons,
      );
      expect(HabitIcon.values.map((i) => i.label).toList(), [
        'Buch',
        'Mond',
        'Tropfen',
        'Haken',
        'Flamme',
        'Herz',
      ]);
      expect(HabitIcon.tryParse('flame'), HabitIcon.flame);
      expect(HabitIcon.tryParse('rocket'), isNull);
    });

    test('withIcon builds the draft from the enum', () {
      expect(
        HabitDraft.withIcon(title: 'x', icon: HabitIcon.heart).iconKey,
        'heart',
      );
      expect(HabitDraft.withIcon(title: 'x').iconKey, 'book');
    });
  });

  group('reminder time', () {
    test('is off by default and passes through when set', () {
      expect(
        validateHabitDraft(const HabitDraft(title: 'x')).reminderTime,
        isNull,
      );
      expect(
        validateHabitDraft(
          const HabitDraft(title: 'x', reminderTime: LocalTime(7, 30)),
        ).reminderTime,
        const LocalTime(7, 30),
      );
      expect(defaultHabitReminderTime, const LocalTime(20, 0));
    });
  });

  group('check dates (30 day window, specification 9.2)', () {
    final today = LocalDate(2026, 10, 3);
    final started = LocalDate(2026, 8, 1);

    HabitCheckDateError? errorOn(LocalDate date, {LocalDate? archivedFrom}) =>
        checkDateError(
          habit: makeHabit(startedOn: started, archivedFrom: archivedFrom),
          date: date,
          today: today,
        );

    test('today is allowed', () {
      expect(errorOn(today), isNull);
    });

    test('day -30 is allowed, day -31 is too old', () {
      expect(errorOn(today.addDays(-30)), isNull);
      expect(errorOn(today.addDays(-31)), HabitCheckDateError.tooOld);
      expect(errorOn(today.addDays(-29)), isNull);
    });

    test('tomorrow and later are the future', () {
      expect(errorOn(today.addDays(1)), HabitCheckDateError.future);
      expect(errorOn(today.addDays(400)), HabitCheckDateError.future);
    });

    test('the start day is allowed, the day before it is not', () {
      final young = makeHabit(startedOn: today.addDays(-5));
      expect(
        checkDateError(habit: young, date: today.addDays(-5), today: today),
        isNull,
      );
      expect(
        checkDateError(habit: young, date: today.addDays(-6), today: today),
        HabitCheckDateError.beforeStart,
      );
    });

    test('before the start wins over "too old"', () {
      final young = makeHabit(startedOn: today.addDays(-2));
      expect(
        checkDateError(habit: young, date: today.addDays(-40), today: today),
        HabitCheckDateError.beforeStart,
      );
    });

    test('the archive date and every later day are rejected, the day before is fine', () {
      final archivedFrom = today.addDays(-3);
      expect(
        errorOn(archivedFrom.addDays(-1), archivedFrom: archivedFrom),
        isNull,
      );
      expect(
        errorOn(archivedFrom, archivedFrom: archivedFrom),
        HabitCheckDateError.archived,
      );
      expect(
        errorOn(today, archivedFrom: archivedFrom),
        HabitCheckDateError.archived,
      );
    });

    test('archived from tomorrow still allows today', () {
      expect(errorOn(today, archivedFrom: today.addDays(1)), isNull);
    });

    test('the future wins over every other reason', () {
      expect(
        errorOn(today.addDays(1), archivedFrom: today.addDays(-5)),
        HabitCheckDateError.future,
      );
    });

    test('the window is calendar based across DST days and year ends', () {
      final spring = LocalDate(2026, 3, 29);
      final habit = makeHabit(startedOn: LocalDate(2026, 1, 1));
      expect(
        checkDateError(
          habit: habit,
          date: LocalDate(2026, 2, 27),
          today: LocalDate(2026, 3, 29),
        ),
        isNull,
        reason: '30 days before the 23-hour day',
      );
      expect(
        checkDateError(
          habit: habit,
          date: LocalDate(2026, 2, 26),
          today: spring,
        ),
        HabitCheckDateError.tooOld,
      );
      final yearEnd = makeHabit(startedOn: LocalDate(2026, 11, 1));
      expect(
        checkDateError(
          habit: yearEnd,
          date: LocalDate(2026, 12, 6),
          today: LocalDate(2027, 1, 5),
        ),
        isNull,
        reason: '2027-01-05 minus 30 days is 2026-12-06',
      );
      expect(
        checkDateError(
          habit: yearEnd,
          date: LocalDate(2026, 12, 5),
          today: LocalDate(2027, 1, 5),
        ),
        HabitCheckDateError.tooOld,
      );
    });

    test('validateCheckDate throws a field error with the German message', () {
      final habit = makeHabit(startedOn: started);
      expect(
        () => validateCheckDate(
          habit: habit,
          date: today.addDays(1),
          today: today,
        ),
        throwsA(
          isA<ValidationFailure>().having((f) => f.fieldErrors, 'fieldErrors', {
            HabitFields.date:
                'Für zukünftige Tage kann nichts abgehakt werden.',
          }),
        ),
      );
      validateCheckDate(habit: habit, date: today, today: today);
    });

    test('all hints are German sentences', () {
      expect(HabitCheckDateError.values.map((e) => e.message).toList(), [
        'Für zukünftige Tage kann nichts abgehakt werden.',
        'Vor dem Start der Gewohnheit kann nichts abgehakt werden.',
        'Ab dem Archivierungstag kann nichts mehr abgehakt werden.',
        'Rückwirkend sind nur die letzten 30 Tage möglich.',
      ]);
    });
  });

  group('Habit calendar facts', () {
    final start = LocalDate(2026, 10, 1);

    test('an active habit applies from its start day on', () {
      final habit = makeHabit(startedOn: start);
      expect(habit.appliesOn(start.addDays(-1)), isFalse);
      expect(habit.appliesOn(start), isTrue);
      expect(habit.appliesOn(start.addDays(1000)), isTrue);
      expect(habit.isArchivePendingOn(start), isFalse);
      expect(habit.hasEndedOn(start), isFalse);
    });

    test('archived from tomorrow: applicable today, pending, then ended', () {
      final today = LocalDate(2026, 10, 3);
      final habit = makeHabit(startedOn: start, archivedFrom: today.addDays(1));
      expect(habit.appliesOn(today), isTrue, reason: 'through the archive day');
      expect(habit.isArchivePendingOn(today), isTrue);
      expect(habit.hasEndedOn(today), isFalse);
      final tomorrow = today.addDays(1);
      expect(habit.appliesOn(tomorrow), isFalse);
      expect(habit.isArchivePendingOn(tomorrow), isFalse);
      expect(habit.hasEndedOn(tomorrow), isTrue);
    });

    test('the reminder is off without a time', () {
      expect(makeHabit().hasReminder, isFalse);
      expect(
        makeHabit(reminderTime: const LocalTime(8, 0)).hasReminder,
        isTrue,
      );
    });
  });
}
