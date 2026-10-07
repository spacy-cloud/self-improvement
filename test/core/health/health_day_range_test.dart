import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/health/domain/health_day_range.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The calendar day the comparison asks the health interface for: always the
/// local calendar day in the zone of the clock, never "24 hours" (BS-97,
/// AT25).
void main() {
  setUpAll(TimeZones.ensureInitialized);

  DateTime utc(String iso) => DateTime.parse(iso).toUtc();

  HealthDayRange range(String zone, LocalDate day) => healthDayRange(
    FakeClock.at('2026-10-03T08:00:00Z'),
    day,
    timeZoneId: zone,
  );

  group('one local day', () {
    test('a summer day in Berlin runs from 00:00 to 24:00 local (AT25)', () {
      final day = range('Europe/Berlin', LocalDate(2026, 10, 3));
      expect(day.startUtc, utc('2026-10-02T22:00:00Z'));
      expect(day.endUtc, utc('2026-10-03T22:00:00Z'));
      expect(day.length, const Duration(hours: 24));
    });

    test('a winter day in Berlin has the other offset (AT25)', () {
      final day = range('Europe/Berlin', LocalDate(2026, 1, 15));
      expect(day.startUtc, utc('2026-01-14T23:00:00Z'));
      expect(day.endUtc, utc('2026-01-15T23:00:00Z'));
    });

    test('the day the clocks go forward has 23 hours (AT25)', () {
      final day = range('Europe/Berlin', LocalDate(2026, 3, 29));
      expect(day.startUtc, utc('2026-03-28T23:00:00Z'));
      expect(day.endUtc, utc('2026-03-29T22:00:00Z'));
      expect(day.length, const Duration(hours: 23));
    });

    test('the day the clocks go back has 25 hours (AT25)', () {
      final day = range('Europe/Berlin', LocalDate(2026, 10, 25));
      expect(day.startUtc, utc('2026-10-24T22:00:00Z'));
      expect(day.endUtc, utc('2026-10-25T23:00:00Z'));
      expect(day.length, const Duration(hours: 25));
    });

    test('a zone that skips midnight starts the day at the first minute that '
        'exists (AT25)', () {
      // Lebanon: at 2026-03-29 00:00 the clocks jump to 01:00.
      final day = range('Asia/Beirut', LocalDate(2026, 3, 29));
      expect(day.startUtc, utc('2026-03-28T22:00:00Z'));
      expect(day.endUtc, utc('2026-03-29T21:00:00Z'));
      expect(day.length, const Duration(hours: 23));
    });

    test('a zone whose midnight happens twice starts the day at the first '
        'one (AT25)', () {
      // Cuba: at 2026-11-01 01:00 the clocks go back to 00:00.
      final day = range('America/Havana', LocalDate(2026, 11, 1));
      expect(day.startUtc, utc('2026-11-01T04:00:00Z'));
      expect(day.endUtc, utc('2026-11-02T05:00:00Z'));
      expect(day.length, const Duration(hours: 25));
    });

    test('a change of half an hour gives a day of 24 hours 30 minutes '
        '(AT25)', () {
      // Lord Howe Island changes by 30 minutes.
      final day = range('Australia/Lord_Howe', LocalDate(2026, 4, 5));
      expect(day.length, const Duration(hours: 24, minutes: 30));
    });

    test('UTC is a zone like any other', () {
      final day = range('UTC', LocalDate(2026, 10, 3));
      expect(day.startUtc, utc('2026-10-03T00:00:00Z'));
      expect(day.endUtc, utc('2026-10-04T00:00:00Z'));
    });

    test('a day is equal to another one with the same instants', () {
      final first = range('Europe/Berlin', LocalDate(2026, 10, 3));
      final second = range('Europe/Berlin', LocalDate(2026, 10, 3));
      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(range('UTC', LocalDate(2026, 10, 3))));
    });
  });

  group('the window of seven days', () {
    test('is today and the six days before, oldest first (BS-97)', () {
      final clock = FakeClock.at('2026-10-03T08:00:00Z');
      final window = healthSyncWindow(clock);
      expect(window, hasLength(healthSyncDays));
      expect(healthSyncDays, 7);
      expect(window.first.day, LocalDate(2026, 9, 27));
      expect(window.last.day, LocalDate(2026, 10, 3));
      expect(
        [for (final range in window) range.day],
        [
          for (var back = 6; back >= 0; back--)
            LocalDate(2026, 10, 3).addDays(-back),
        ],
      );
    });

    test('has no gap and no overlap between two days (AT25)', () {
      final clock = FakeClock.at('2026-10-27T08:00:00Z');
      final window = healthSyncWindow(clock);
      for (var i = 1; i < window.length; i++) {
        expect(
          window[i].startUtc,
          window[i - 1].endUtc,
          reason: '${window[i - 1].day} to ${window[i].day}',
        );
      }
      // The window covers the day the clocks went back (2026-10-25).
      expect(
        window.map((range) => range.day),
        contains(LocalDate(2026, 10, 25)),
      );
      expect(
        window
            .firstWhere((range) => range.day == LocalDate(2026, 10, 25))
            .length,
        const Duration(hours: 25),
      );
    });

    test('follows the clock: today changes at local midnight (AT25)', () {
      final clock = FakeClock.at('2026-10-03T21:59:00Z'); // 23:59 in Berlin
      expect(healthSyncWindow(clock).last.day, LocalDate(2026, 10, 3));
      clock.setNow(utc('2026-10-03T22:00:00Z')); // 00:00 in Berlin
      final window = healthSyncWindow(clock);
      expect(window.last.day, LocalDate(2026, 10, 4));
      expect(window.first.day, LocalDate(2026, 9, 28));
    });

    test('follows the zone: the same instant is another day elsewhere '
        '(AT25)', () {
      final clock = FakeClock.at('2026-10-03T23:30:00Z');
      expect(healthSyncWindow(clock).last.day, LocalDate(2026, 10, 4));
      clock.setTimeZone('America/New_York');
      final window = healthSyncWindow(clock);
      expect(window.last.day, LocalDate(2026, 10, 3));
      expect(window.last.startUtc, utc('2026-10-03T04:00:00Z'));
      expect(window.last.endUtc, utc('2026-10-04T04:00:00Z'));
    });

    test('takes the number of days it is asked for', () {
      final clock = FakeClock.at('2026-10-03T08:00:00Z');
      expect(
        healthSyncWindow(clock, days: 1).single.day,
        LocalDate(2026, 10, 3),
      );
      expect(healthSyncWindow(clock, days: 30), hasLength(30));
    });

    test('crosses a month and a year boundary by the calendar (AT25)', () {
      final clock = FakeClock.at('2027-01-02T08:00:00Z');
      final window = healthSyncWindow(clock);
      expect(window.first.day, LocalDate(2026, 12, 27));
      expect(window.last.day, LocalDate(2027, 1, 2));
    });
  });
}
