import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/dashboard/domain/day_browser.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The rules of the day Home shows (BS-93, D-029): today and up to seven days
/// before it, never a day before the profile started, never the future; pure
/// calendar arithmetic, so a day with a daylight saving change is one day like
/// any other.
void main() {
  final today = LocalDate(2026, 10, 7); // a Wednesday

  BrowsedDay shown({
    LocalDate? choice,
    LocalDate? today_,
    LocalDate? profileStart,
  }) => BrowsedDay.resolve(
    today: today_ ?? today,
    choice: choice,
    profileStart: profileStart,
  );

  group('the days that can be reached (BS-93)', () {
    test('(BS-93) without a choice Home shows today and can go back seven '
        'days, not further', () {
      final day = shown();
      expect(day.date, today);
      expect(day.isToday, isTrue);
      expect(day.oldest, LocalDate(2026, 9, 30));
      expect(day.days, hasLength(8), reason: 'seven days before, and today');
      expect(day.days.first, LocalDate(2026, 9, 30));
      expect(day.days.last, today);
      expect(day.canGoForward, isFalse);
      expect(day.next, isNull);
      expect(day.canGoBack, isTrue);
      expect(day.previous, LocalDate(2026, 10, 6));
    });

    test('(BS-93) the oldest day is "vor 7 Tagen" and has no previous day', () {
      final day = shown(choice: LocalDate(2026, 9, 30));
      expect(day.date, LocalDate(2026, 9, 30));
      expect(day.daysAgo, 7);
      expect(day.canGoBack, isFalse);
      expect(day.previous, isNull);
      expect(day.canGoForward, isTrue);
      expect(day.next, LocalDate(2026, 10, 1));
    });

    test('(BS-93) a day older than seven days is not reachable: Home shows '
        'today', () {
      expect(shown(choice: LocalDate(2026, 9, 29)).date, today);
      expect(shown(choice: LocalDate(2026, 1, 1)).date, today);
    });

    test('(BS-93) a day in the future is not reachable: Home shows today', () {
      expect(shown(choice: LocalDate(2026, 10, 8)).date, today);
      expect(shown(choice: LocalDate(2027, 10, 7)).date, today);
    });

    test('(BS-93) every day of the window can be shown, in order', () {
      for (var back = 0; back <= 7; back++) {
        final choice = today.addDays(-back);
        final day = shown(choice: choice);
        expect(day.date, choice, reason: '$back days back');
        expect(day.daysAgo, back);
        expect(day.isToday, back == 0);
      }
    });

    test('(BS-93) the profile start limits the way back: nothing was recorded '
        'before it, so there is no day to show', () {
      final start = LocalDate(2026, 10, 5);
      final day = shown(profileStart: start);
      expect(day.oldest, start);
      expect(day.days, <LocalDate>[
        LocalDate(2026, 10, 5),
        LocalDate(2026, 10, 6),
        today,
      ]);
      expect(
        shown(choice: LocalDate(2026, 10, 4), profileStart: start).date,
        today,
      );
      expect(shown(choice: start, profileStart: start).date, start);
      expect(shown(choice: start, profileStart: start).canGoBack, isFalse);
    });

    test(
      '(BS-93) a profile that started long ago does not widen the window',
      () {
        final day = shown(profileStart: LocalDate(2025, 1, 1));
        expect(day.oldest, LocalDate(2026, 9, 30));
      },
    );

    test('(BS-93) on the first day of the profile there is nothing to page '
        'through (no arrows, no swipe)', () {
      final day = shown(profileStart: today);
      expect(day.isBrowsable, isFalse);
      expect(day.canGoBack, isFalse);
      expect(day.canGoForward, isFalse);
      expect(day.days, <LocalDate>[today]);
    });

    test('(BS-93) the day after the profile start can page back one day', () {
      final day = shown(profileStart: LocalDate(2026, 10, 6));
      expect(day.isBrowsable, isTrue);
      expect(day.days, <LocalDate>[LocalDate(2026, 10, 6), today]);
    });

    test('(BS-93) a profile start in the future (a clock set back) shows '
        'today only', () {
      final day = shown(profileStart: LocalDate(2026, 11, 1));
      expect(day.date, today);
      expect(day.isBrowsable, isFalse);
    });

    test('(BS-93) a day equals another by its values', () {
      expect(
        shown(choice: LocalDate(2026, 10, 5)),
        shown(choice: LocalDate(2026, 10, 5)),
      );
      expect(shown(choice: LocalDate(2026, 10, 5)) == shown(), isFalse);
      expect(
        shown(choice: LocalDate(2026, 10, 5)).hashCode,
        shown(choice: LocalDate(2026, 10, 5)).hashCode,
      );
    });
  });

  group('how the day is named (BS-93, AT34)', () {
    test('(BS-93, AT34) the date as Home writes it', () {
      expect(
        shown(choice: LocalDate(2026, 10, 5)).dateText,
        'Montag, 5. Oktober',
      );
      expect(shown().dateText, 'Mittwoch, 7. Oktober');
    });

    test('(BS-93, AT34) a screen reader hears the date and how long ago it '
        'was', () {
      expect(shown().spoken, 'Mittwoch, 7. Oktober, heute');
      expect(
        shown(choice: LocalDate(2026, 10, 6)).spoken,
        'Dienstag, 6. Oktober, gestern',
      );
      expect(
        shown(choice: LocalDate(2026, 10, 5)).spoken,
        'Montag, 5. Oktober, vor 2 Tagen',
      );
      expect(
        shown(choice: LocalDate(2026, 9, 30)).spoken,
        'Mittwoch, 30. September, vor 7 Tagen',
      );
    });
  });

  group('days with a daylight saving change (BS-93, AT25)', () {
    test('(BS-93, AT25) spring (29 March 2026): the day is one day of the '
        'window, nothing is skipped or doubled', () {
      final monday = LocalDate(2026, 3, 30);
      final window = shown(today_: monday).days;
      expect(window, <LocalDate>[
        LocalDate(2026, 3, 23),
        LocalDate(2026, 3, 24),
        LocalDate(2026, 3, 25),
        LocalDate(2026, 3, 26),
        LocalDate(2026, 3, 27),
        LocalDate(2026, 3, 28),
        LocalDate(2026, 3, 29),
        monday,
      ]);
      // Paging back from Monday passes the 29th exactly once.
      var day = shown(today_: monday);
      final seen = <LocalDate>[];
      // At most 20 steps: a bug that never ends the row must fail this test,
      // not hang it.
      for (var step = 0; step < 20 && day.previous != null; step++) {
        day = shown(today_: monday, choice: day.previous);
        seen.add(day.date);
      }
      expect(seen.where((d) => d == LocalDate(2026, 3, 29)), hasLength(1));
      expect(seen, hasLength(7));
      expect(seen.last, LocalDate(2026, 3, 23));
    });

    test('(BS-93, AT25) autumn (25 October 2026): the 25-hour day is one day '
        'of the window, and the way forward passes it once', () {
      final monday = LocalDate(2026, 10, 26);
      var day = shown(today_: monday, choice: LocalDate(2026, 10, 19));
      expect(day.date, LocalDate(2026, 10, 19));
      final seen = <LocalDate>[day.date];
      for (var step = 0; step < 20 && day.next != null; step++) {
        day = shown(today_: monday, choice: day.next);
        seen.add(day.date);
      }
      expect(seen, <LocalDate>[
        for (var d = 19; d <= 26; d++) LocalDate(2026, 10, d),
      ]);
      expect(seen.where((d) => d == LocalDate(2026, 10, 25)), hasLength(1));
    });

    test('(BS-93, AT25) the windows across both changes have eight days', () {
      for (final date in <LocalDate>[
        LocalDate(2026, 3, 29),
        LocalDate(2026, 3, 30),
        LocalDate(2026, 10, 25),
        LocalDate(2026, 10, 26),
        LocalDate(2026, 12, 31),
        LocalDate(2028, 3, 1), // after a leap day
      ]) {
        expect(shown(today_: date).days, hasLength(8), reason: '$date');
      }
    });
  });
}
