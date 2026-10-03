import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../analysis_fixtures.dart';

void main() {
  group('period lengths', () {
    test('only 7, 30 and 90 days exist, labels and selector texts', () {
      expect(AnalysisPeriodLength.values.map((l) => l.days), [7, 30, 90]);
      expect(AnalysisPeriodLength.tryFromDays(7), AnalysisPeriodLength.days7);
      expect(AnalysisPeriodLength.tryFromDays(30), AnalysisPeriodLength.days30);
      expect(AnalysisPeriodLength.tryFromDays(90), AnalysisPeriodLength.days90);
      expect(AnalysisPeriodLength.tryFromDays(14), isNull);
      expect(AnalysisPeriodLength.tryFromDays(0), isNull);
      expect(AnalysisPeriodLength.days7.label, '7 Tage');
      expect(AnalysisPeriodLength.days30.semanticsLabel, 'Zeitraum 30 Tage');
    });

    test('the comparison base is named after its length, never "Vorwoche"', () {
      expect(AnalysisPeriodLength.days7.previousLabel, 'vorherige 7 Tage');
      expect(AnalysisPeriodLength.days30.previousLabel, 'vorherige 30 Tage');
      expect(AnalysisPeriodLength.days90.previousTitle, 'Vorherige 90 Tage');
      expect(
        AnalysisPeriodLength.days30.againstPrevious,
        'gegenüber den vorherigen 30 Tagen',
      );
      expect(AnalysisPeriodLength.days7.currentTitle, 'Letzte 7 Tage');
      for (final length in AnalysisPeriodLength.values) {
        for (final text in [
          length.previousLabel,
          length.previousTitle,
          length.againstPrevious,
          length.previousDative,
          length.currentTitle,
        ]) {
          expect(text.toLowerCase(), isNot(contains('vorwoche')));
        }
      }
    });
  });

  group('period arithmetic for today = Saturday 2026-10-03', () {
    test('7 days: 09-27 .. 10-03, previous 09-20 .. 09-26', () {
      final period = refPeriod(AnalysisPeriodLength.days7);
      expect(period.start, d2026(9, 27));
      expect(period.end, d2026(10, 3));
      expect(period.previousStart, d2026(9, 20));
      expect(period.previousEnd, d2026(9, 26));
      expect(period.windowStart, d2026(9, 20));
      expect(period.currentDays, hasLength(7));
      expect(period.previousDays, hasLength(7));
    });

    test('30 days: 09-04 .. 10-03, previous 08-05 .. 09-03', () {
      final period = refPeriod(AnalysisPeriodLength.days30);
      expect(period.start, d2026(9, 4));
      expect(period.end, d2026(10, 3));
      expect(period.previousStart, d2026(8, 5));
      expect(period.previousEnd, d2026(9, 3));
      expect(period.currentDays, hasLength(30));
      expect(period.previousDays, hasLength(30));
    });

    test('90 days: 07-06 .. 10-03, previous 04-07 .. 07-05', () {
      final period = refPeriod(AnalysisPeriodLength.days90);
      expect(period.start, d2026(7, 6));
      expect(period.end, d2026(10, 3));
      expect(period.previousStart, d2026(4, 7));
      expect(period.previousEnd, d2026(7, 5));
      expect(period.currentDays, hasLength(90));
      expect(period.previousDays, hasLength(90));
    });

    test('the previous period ends the day before the current one starts', () {
      for (final length in AnalysisPeriodLength.values) {
        final period = refPeriod(length);
        expect(period.previousEnd.addDays(1), period.start);
        expect(
          period.previousStart.daysUntil(period.previousEnd) + 1,
          length.days,
        );
        expect(period.start.daysUntil(period.end) + 1, length.days);
      }
    });
  });

  group('boundaries: first and last day of each period', () {
    for (final length in AnalysisPeriodLength.values) {
      final n = length.days;
      test('$n days: day -${n - 1} is in, day -$n is the previous period', () {
        final period = refPeriod(length);
        final firstCurrent = refToday.addDays(-(n - 1));
        final lastPrevious = refToday.addDays(-n);
        expect(period.containsCurrent(firstCurrent), isTrue);
        expect(period.containsCurrent(refToday), isTrue);
        expect(period.containsCurrent(lastPrevious), isFalse);
        expect(period.containsPrevious(lastPrevious), isTrue);
        expect(period.containsPrevious(firstCurrent), isFalse);
        expect(period.containsPrevious(refToday.addDays(-(2 * n - 1))), isTrue);
        expect(period.containsPrevious(refToday.addDays(-(2 * n))), isFalse);
        expect(period.containsCurrent(refToday.addDays(1)), isFalse);
      });
    }
  });

  group('header texts come from the calendar', () {
    test('27.09. bis 03.10.2026, inklusive heute', () {
      final period = refPeriod(AnalysisPeriodLength.days7);
      expect(period.headerText, '27.09. bis 03.10.2026, inklusive heute');
      expect(period.previousRangeText, '20.09. bis 26.09.2026');
      expect(
        period.previousHeaderText,
        'Vorherige 7 Tage: 20.09. bis 26.09.2026',
      );
      expect(
        period.semanticsLabel,
        'Zeitraum 7 Tage, 27.09. bis 03.10.2026, inklusive heute',
      );
    });

    test('30 and 90 days use their own dates', () {
      expect(
        refPeriod(AnalysisPeriodLength.days30).headerText,
        '04.09. bis 03.10.2026, inklusive heute',
      );
      expect(
        refPeriod(AnalysisPeriodLength.days90).headerText,
        '06.07. bis 03.10.2026, inklusive heute',
      );
      expect(
        refPeriod(AnalysisPeriodLength.days90).previousRangeText,
        '07.04. bis 05.07.2026',
      );
    });

    test('a period across the new year keeps both years', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 1, 3),
      );
      expect(period.start, LocalDate(2025, 12, 28));
      expect(period.headerText, '28.12.2025 bis 03.01.2026, inklusive heute');
      expect(period.previousStart, LocalDate(2025, 12, 21));
      expect(period.previousEnd, LocalDate(2025, 12, 27));
      expect(period.previousRangeText, '21.12. bis 27.12.2025');
    });

    test('date helpers: weekday names and ranges', () {
      expect(formatDayMonth(LocalDate(2026, 3, 9)), '09.03.');
      expect(formatFullDate(LocalDate(2026, 3, 9)), '09.03.2026');
      expect(weekdayShort(LocalDate(2026, 10, 3)), 'Sa');
      expect(weekdayLong(LocalDate(2026, 10, 3)), 'Samstag');
      expect(weekdayShort(LocalDate(2026, 9, 28)), 'Mo');
      expect(weekdayLong(LocalDate(2026, 10, 4)), 'Sonntag');
      expect(formatShortWeekdayDate(LocalDate(2026, 9, 30)), 'Mi, 30.09.');
      expect(
        formatLongWeekdayDate(LocalDate(2026, 10, 1)),
        'Donnerstag, 01.10.2026',
      );
      expect(
        formatDateRange(LocalDate(2026, 9, 28), LocalDate(2026, 9, 28)),
        '28.09.2026',
        reason: 'a single day is just the date',
      );
    });
  });

  group('month, year, leap year and daylight saving boundaries', () {
    test('7 days over a month boundary', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 10, 2),
      );
      expect(period.start, LocalDate(2026, 9, 26));
      expect(period.currentDays.map((d) => d.toIso()), [
        '2026-09-26',
        '2026-09-27',
        '2026-09-28',
        '2026-09-29',
        '2026-09-30',
        '2026-10-01',
        '2026-10-02',
      ]);
    });

    test('2028 is a leap year: 29.02. is part of the period', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2028, 3, 2),
      );
      expect(period.start, LocalDate(2028, 2, 25));
      expect(period.currentDays.map((d) => d.toIso()), contains('2028-02-29'));
      expect(period.currentDays, hasLength(7));
      final regular = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2027, 3, 2),
      );
      expect(regular.start, LocalDate(2027, 2, 24));
      expect(
        regular.currentDays.map((d) => d.toIso()),
        isNot(contains('2027-02-29')),
      );
    });

    test('90 days across the year boundary have exactly 90 distinct days', () {
      final period = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days90,
        today: LocalDate(2026, 2, 14),
      );
      final days = period.currentDays;
      expect(days, hasLength(90));
      expect(days.toSet(), hasLength(90));
      expect(days.first, LocalDate(2025, 11, 17));
      for (var i = 1; i < days.length; i++) {
        expect(days[i - 1].addDays(1), days[i]);
      }
    });

    test('the clock change days keep 7 consecutive calendar days', () {
      // 2026-03-29 has only 23 hours, 2026-10-25 has 25 hours in Berlin. The
      // analysis counts calendar days, so both periods still have 7 days.
      final spring = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 3, 31),
      );
      expect(spring.start, LocalDate(2026, 3, 25));
      expect(spring.currentDays.map((d) => d.toIso()), [
        '2026-03-25',
        '2026-03-26',
        '2026-03-27',
        '2026-03-28',
        '2026-03-29',
        '2026-03-30',
        '2026-03-31',
      ]);
      final autumn = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days7,
        today: LocalDate(2026, 10, 27),
      );
      expect(autumn.start, LocalDate(2026, 10, 21));
      expect(autumn.currentDays.map((d) => d.toIso()), [
        '2026-10-21',
        '2026-10-22',
        '2026-10-23',
        '2026-10-24',
        '2026-10-25',
        '2026-10-26',
        '2026-10-27',
      ]);
      expect(autumn.previousEnd, LocalDate(2026, 10, 20));
    });

    test('equality and hash cover length and today', () {
      final a = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days30,
        today: refToday,
      );
      final b = AnalysisPeriodSpec(
        length: AnalysisPeriodLength.days30,
        today: LocalDate(2026, 10, 3),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          AnalysisPeriodSpec(
            length: AnalysisPeriodLength.days7,
            today: refToday,
          ),
        ),
      );
      expect(
        a,
        isNot(
          AnalysisPeriodSpec(
            length: AnalysisPeriodLength.days30,
            today: refToday.addDays(1),
          ),
        ),
      );
    });
  });

  group('usage window of the comparison base', () {
    test('the previous period may start exactly on the usage start', () {
      final period = refPeriod(AnalysisPeriodLength.days7);
      expect(period.baseProblem(d2026(9, 20)), isNull);
      expect(period.baseProblem(d2026(9, 19)), isNull);
    });

    test(
      'a previous period that starts one day before the usage start fails',
      () {
        final period = refPeriod(AnalysisPeriodLength.days7);
        expect(
          period.baseProblem(d2026(9, 21)),
          NoComparisonReason.previousPeriodBeforeStart,
        );
        expect(
          period.baseProblem(d2026(10, 3)),
          NoComparisonReason.previousPeriodBeforeStart,
        );
      },
    );

    test('an unknown usage start allows no comparison', () {
      expect(
        refPeriod(AnalysisPeriodLength.days7).baseProblem(null),
        NoComparisonReason.noUsageStart,
      );
    });

    test('comparisons are possible from usage start + 2N - 1 days', () {
      final start = d2026(9, 20);
      expect(
        refPeriod(AnalysisPeriodLength.days7).comparisonAvailableFrom(start),
        d2026(10, 3),
        reason: 'on 10-03 the previous 7 days start exactly on 09-20',
      );
      expect(
        refPeriod(AnalysisPeriodLength.days30).comparisonAvailableFrom(start),
        d2026(11, 18),
        reason: '2026-09-20 + 59 days',
      );
      expect(
        refPeriod(AnalysisPeriodLength.days90).comparisonAvailableFrom(start),
        LocalDate(2027, 3, 18),
        reason: '2026-09-20 + 179 days',
      );
      expect(
        refPeriod(AnalysisPeriodLength.days7).comparisonAvailableFrom(null),
        isNull,
      );
    });
  });
}
