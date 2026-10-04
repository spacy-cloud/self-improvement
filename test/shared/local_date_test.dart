import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  group('LocalDate parsing', () {
    test('parses a strict ISO date', () {
      final date = LocalDate.parse('2026-10-03');
      expect((date.year, date.month, date.day), (2026, 10, 3));
      expect(date.toIso(), '2026-10-03');
      expect(date.toString(), '2026-10-03');
    });

    test('rejects everything that is not a real YYYY-MM-DD date', () {
      for (final bad in [
        '',
        '2026-1-3',
        '2026-10-3',
        '26-10-03',
        ' 2026-10-03',
        '2026-10-03 ',
        '2026-10-03T00:00:00',
        '2026/10/03',
        '2026-13-01',
        '2026-00-10',
        '2026-02-30',
        '2025-02-29',
        '2026-04-31',
        '0000-01-01',
      ]) {
        expect(LocalDate.tryParse(bad), isNull, reason: bad);
        expect(() => LocalDate.parse(bad), throwsFormatException);
      }
    });

    test('accepts leap days only in leap years', () {
      expect(LocalDate.tryParse('2024-02-29'), isNotNull);
      expect(LocalDate.tryParse('2000-02-29'), isNotNull);
      expect(LocalDate.tryParse('1900-02-29'), isNull);
      expect(LocalDate.tryParse('2100-02-29'), isNull);
    });

    test('constructor rejects invalid dates', () {
      expect(() => LocalDate(2026, 2, 29), throwsArgumentError);
      expect(() => LocalDate(2026, 0, 1), throwsArgumentError);
    });
  });

  group('LocalDate calendar arithmetic', () {
    test('adds days across month, year and leap boundaries', () {
      expect(LocalDate(2026, 1, 31).addDays(1), LocalDate(2026, 2, 1));
      expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
      expect(LocalDate(2024, 2, 28).addDays(1), LocalDate(2024, 2, 29));
      expect(LocalDate(2025, 2, 28).addDays(1), LocalDate(2025, 3, 1));
      expect(LocalDate(2026, 3, 1).addDays(-1), LocalDate(2026, 2, 28));
      expect(LocalDate(2026, 1, 1).addDays(-1), LocalDate(2025, 12, 31));
      expect(LocalDate(2026, 10, 3).addDays(0), LocalDate(2026, 10, 3));
      expect(LocalDate(2026, 10, 3).addDays(-89), LocalDate(2026, 7, 6));
    });

    test('is not affected by daylight saving transitions', () {
      // Europe/Berlin: 2026-03-29 has 23 hours, 2026-10-25 has 25 hours.
      expect(LocalDate(2026, 3, 28).addDays(1), LocalDate(2026, 3, 29));
      expect(LocalDate(2026, 3, 29).addDays(1), LocalDate(2026, 3, 30));
      expect(LocalDate(2026, 10, 24).addDays(1), LocalDate(2026, 10, 25));
      expect(LocalDate(2026, 10, 25).addDays(1), LocalDate(2026, 10, 26));
      expect(LocalDate(2026, 3, 28).daysUntil(LocalDate(2026, 3, 30)), 2);
      expect(LocalDate(2026, 10, 24).daysUntil(LocalDate(2026, 10, 26)), 2);
    });

    test('daysUntil is signed and exact', () {
      final a = LocalDate(2026, 10, 3);
      expect(a.daysUntil(a), 0);
      expect(a.daysUntil(LocalDate(2026, 10, 10)), 7);
      expect(LocalDate(2026, 10, 10).daysUntil(a), -7);
      expect(LocalDate(2025, 12, 31).daysUntil(LocalDate(2026, 1, 1)), 1);
      expect(LocalDate(2024, 1, 1).daysUntil(LocalDate(2025, 1, 1)), 366);
    });

    test('weekday, start of week (Monday) and day of year', () {
      // 2026-10-03 is a Saturday.
      final saturday = LocalDate(2026, 10, 3);
      expect(saturday.weekday, DateTime.saturday);
      expect(saturday.startOfWeek, LocalDate(2026, 9, 28));
      expect(LocalDate(2026, 9, 28).weekday, DateTime.monday);
      expect(LocalDate(2026, 9, 28).startOfWeek, LocalDate(2026, 9, 28));
      expect(LocalDate(2026, 10, 4).weekday, DateTime.sunday);
      expect(LocalDate(2026, 10, 4).startOfWeek, LocalDate(2026, 9, 28));
      expect(LocalDate(2026, 1, 1).dayOfYear, 1);
      expect(LocalDate(2026, 12, 31).dayOfYear, 365);
      expect(LocalDate(2024, 12, 31).dayOfYear, 366);
      expect(LocalDate(2026, 10, 3).startOfMonth, LocalDate(2026, 10, 1));
    });

    test('rangeTo is inclusive and empty for a reversed range', () {
      final days = LocalDate(2026, 2, 27).rangeTo(LocalDate(2026, 3, 2));
      expect(days.map((d) => d.toIso()).toList(), [
        '2026-02-27',
        '2026-02-28',
        '2026-03-01',
        '2026-03-02',
      ]);
      expect(LocalDate(2026, 3, 2).rangeTo(LocalDate(2026, 2, 27)), isEmpty);
      expect(
        LocalDate(2026, 3, 2).rangeTo(LocalDate(2026, 3, 2)),
        hasLength(1),
      );
    });
  });

  group('LocalDate ordering and identity', () {
    test('compares chronologically and by value', () {
      final a = LocalDate(2026, 10, 3);
      final b = LocalDate(2026, 10, 4);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a <= LocalDate(2026, 10, 3), isTrue);
      expect(a >= LocalDate(2026, 10, 3), isTrue);
      expect(a == LocalDate(2026, 10, 3), isTrue);
      expect({a, LocalDate(2026, 10, 3)}, hasLength(1));
      expect(LocalDate.earlier(a, b), a);
      expect(LocalDate.later(a, b), b);
      final sorted = [b, a, LocalDate(2025, 12, 31)]..sort();
      expect(sorted.first, LocalDate(2025, 12, 31));
    });

    test('fromDateTime takes wall clock components', () {
      expect(
        LocalDate.fromDateTime(DateTime(2026, 10, 3, 23, 59)),
        LocalDate(2026, 10, 3),
      );
    });
  });

  group('LocalTime', () {
    test('parses and prints HH:mm strictly', () {
      expect(LocalTime.parse('07:05'), const LocalTime(7, 5));
      expect(const LocalTime(7, 5).toIso(), '07:05');
      expect(const LocalTime(23, 59).minutesOfDay, 23 * 60 + 59);
      for (final bad in ['', '7:05', '24:00', '12:60', '12:5', '12:05:00']) {
        expect(LocalTime.tryParse(bad), isNull, reason: bad);
      }
      expect(() => LocalTime.parse('99:99'), throwsFormatException);
    });

    test('orders by minutes of day', () {
      expect(
        const LocalTime(9, 0).compareTo(const LocalTime(10, 0)),
        lessThan(0),
      );
    });
  });
}
