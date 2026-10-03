import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  setUpAll(TimeZones.ensureInitialized);

  group('today and local date conversion (Europe/Berlin)', () {
    test('uses the zone calendar day, not the UTC day', () {
      // 2026-10-03 22:30 UTC is already 2026-10-04 00:30 in CEST.
      final clock = FakeClock.at('2026-10-03T22:30:00Z');
      expect(clock.today(), LocalDate(2026, 10, 4));
      expect(clock.localDateOf(clock.nowUtc()), LocalDate(2026, 10, 4));
      expect(
        clock.localDateOf(clock.nowUtc(), timeZoneId: 'UTC'),
        LocalDate(2026, 10, 3),
      );
    });

    test('day boundary follows DST: 23 and 25 hour days', () {
      final clock = FakeClock.at('2026-03-28T22:59:00Z');
      // 2026-03-29 is the spring-forward day (CET -> CEST at 01:00 UTC).
      expect(clock.today(), LocalDate(2026, 3, 28));
      clock.setNow(DateTime.utc(2026, 3, 28, 23, 0));
      expect(clock.today(), LocalDate(2026, 3, 29));
      clock.setNow(DateTime.utc(2026, 3, 29, 21, 59));
      expect(clock.today(), LocalDate(2026, 3, 29));
      clock.setNow(DateTime.utc(2026, 3, 29, 22, 0));
      expect(clock.today(), LocalDate(2026, 3, 30));
      // 2026-10-25 is the fall-back day (CEST -> CET at 01:00 UTC).
      clock.setNow(DateTime.utc(2026, 10, 24, 22, 0));
      expect(clock.today(), LocalDate(2026, 10, 25));
      clock.setNow(DateTime.utc(2026, 10, 25, 22, 59));
      expect(clock.today(), LocalDate(2026, 10, 25));
      clock.setNow(DateTime.utc(2026, 10, 25, 23, 0));
      expect(clock.today(), LocalDate(2026, 10, 26));
    });

    test('year and month boundaries', () {
      final clock = FakeClock.at('2026-12-31T22:59:59Z');
      expect(clock.today(), LocalDate(2026, 12, 31));
      clock.advance(const Duration(seconds: 1));
      expect(clock.today(), LocalDate(2027, 1, 1));
    });

    test('toLocal returns wall clock components', () {
      final clock = FakeClock.at('2026-07-01T10:15:00Z');
      final local = clock.toLocal(clock.nowUtc());
      expect(local.date, LocalDate(2026, 7, 1));
      expect(local.time, const LocalTime(12, 15));
    });

    test('zone change does not rewrite frozen dates (caller keeps them)', () {
      final clock = FakeClock.at('2026-10-03T23:30:00Z');
      final frozen = clock.today(); // Berlin: already 2026-10-04
      clock.setTimeZone('America/New_York');
      expect(clock.today(), LocalDate(2026, 10, 3));
      expect(frozen, LocalDate(2026, 10, 4));
    });
  });

  group('wall clock to UTC', () {
    final clock = FakeClock.at('2026-10-03T08:00:00Z');

    test('regular time uses the offset in effect', () {
      final summer = clock.toUtc(LocalDate(2026, 7, 1), const LocalTime(12, 0));
      expect(summer, isA<ZonedResolved>());
      expect((summer as ZonedResolved).utc, DateTime.utc(2026, 7, 1, 10, 0));
      expect(summer.wasAmbiguous, isFalse);
      final winter = clock.toUtc(
        LocalDate(2026, 12, 1),
        const LocalTime(12, 0),
      ) as ZonedResolved;
      expect(winter.utc, DateTime.utc(2026, 12, 1, 11, 0));
    });

    test('nonexistent time in the spring gap is reported', () {
      final gap = clock.toUtc(LocalDate(2026, 3, 29), const LocalTime(2, 30));
      expect(gap, isA<ZonedNonexistent>());
      expect((gap as ZonedNonexistent).nextValid, const LocalTime(3, 0));
      // The minute before and after the gap exist.
      expect(
        clock.toUtc(LocalDate(2026, 3, 29), const LocalTime(1, 59)),
        isA<ZonedResolved>(),
      );
      expect(
        clock.toUtc(LocalDate(2026, 3, 29), const LocalTime(3, 0)),
        isA<ZonedResolved>(),
      );
    });

    test('ambiguous time in the autumn overlap uses the earlier offset', () {
      final overlap = clock.toUtc(
        LocalDate(2026, 10, 25),
        const LocalTime(2, 30),
      ) as ZonedResolved;
      expect(overlap.wasAmbiguous, isTrue);
      // Earlier occurrence is still CEST (UTC+2): 00:30 UTC.
      expect(overlap.utc, DateTime.utc(2026, 10, 25, 0, 30));
    });

    test('round trips through local conversion', () {
      final resolved = clock.toUtc(
        LocalDate(2026, 5, 17),
        const LocalTime(7, 45),
      ) as ZonedResolved;
      final local = clock.toLocal(resolved.utc);
      expect(local.date, LocalDate(2026, 5, 17));
      expect(local.time, const LocalTime(7, 45));
    });

    test('works for other zones', () {
      final tokyo = clock.toUtc(
        LocalDate(2026, 1, 1),
        const LocalTime(9, 0),
        timeZoneId: 'Asia/Tokyo',
      ) as ZonedResolved;
      expect(tokyo.utc, DateTime.utc(2026, 1, 1, 0, 0));
    });
  });

  test('FakeClock advance and setNow control time', () {
    final clock = FakeClock.at('2026-10-03T08:00:00Z');
    clock.advance(const Duration(hours: 1));
    expect(clock.nowUtc(), DateTime.utc(2026, 10, 3, 9));
    clock.setNow(DateTime.utc(2026, 1, 1));
    expect(clock.nowUtc().isUtc, isTrue);
  });

  test('SystemClock delegates the zone to its provider', () {
    final clock = SystemClock(timeZoneIdProvider: () => 'Europe/Berlin');
    expect(clock.timeZoneId, 'Europe/Berlin');
    expect(clock.nowUtc().isUtc, isTrue);
    expect(TimeZones.isKnown('Europe/Berlin'), isTrue);
    expect(TimeZones.isKnown('Mars/Olympus'), isFalse);
  });
}
