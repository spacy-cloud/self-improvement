import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The choice of the day Home shows (BS-93, D-029) with the real profile, the
/// fake clock and the real providers: paging, the limits, and what a new
/// calendar day does to a choice.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;

  // 2026-10-07 is a Wednesday.
  final today = LocalDate(2026, 10, 7);

  Future<void> start({
    LocalDate? profileStart,
    String nowIso = '2026-10-07T08:00:00Z',
    String timeZoneId = 'Europe/Berlin',
  }) async {
    harness = await DataHarness.create(
      nowIso: nowIso,
      timeZoneId: timeZoneId,
      realProjection: true,
    );
    await harness.seedOnboarded(
      startedOn: profileStart ?? LocalDate(2026, 9, 1),
    );
    container = harness.createContainer();
    container.listen(browsedDayProvider, (_, _) {});
    // The profile arrives by a stream: wait for it, or the first read would
    // not know the first day yet.
    await container.read(profileProvider.future);
  }

  tearDown(() => harness.dispose());

  LocalDate shown() => container.read(browsedDayProvider).date;
  SelectedDayController days() => container.read(selectedDayProvider.notifier);

  group('paging (BS-93)', () {
    test('(BS-93) Home follows today until a day is chosen', () async {
      await start();
      expect(container.read(selectedDayProvider), isNull);
      expect(shown(), today);
      expect(container.read(browsedDayProvider).isToday, isTrue);
    });

    test('(BS-93) previous goes back one day at a time, next comes forward '
        'again, and the way back ends after seven days', () async {
      await start();
      for (var back = 1; back <= 7; back++) {
        days().previous();
        expect(shown(), today.addDays(-back), reason: '$back days back');
      }
      days().previous();
      expect(shown(), today.addDays(-7), reason: 'no day before the oldest');
      for (var forward = 6; forward >= 0; forward--) {
        days().next();
        expect(shown(), today.addDays(-forward));
      }
      days().next();
      expect(shown(), today, reason: 'no day after today');
    });

    test('(BS-93) coming forward to today follows today again (no choice is '
        'kept)', () async {
      await start();
      days().previous();
      expect(container.read(selectedDayProvider), today.addDays(-1));
      days().next();
      expect(container.read(selectedDayProvider), isNull);
    });

    test(
      '(BS-93) select shows a reachable day and ignores the others',
      () async {
        await start();
        days().select(LocalDate(2026, 10, 3));
        expect(shown(), LocalDate(2026, 10, 3));
        days().select(LocalDate(2026, 9, 29)); // eight days back
        expect(
          shown(),
          LocalDate(2026, 10, 3),
          reason: 'older than seven days',
        );
        days().select(LocalDate(2026, 10, 8)); // tomorrow
        expect(shown(), LocalDate(2026, 10, 3), reason: 'the future');
        days().select(today);
        expect(shown(), today);
        expect(container.read(selectedDayProvider), isNull);
      },
    );

    test('(BS-93) "Zurück zu heute" shows today from any day', () async {
      await start();
      days().select(LocalDate(2026, 10, 1));
      expect(shown(), LocalDate(2026, 10, 1));
      days().backToToday();
      expect(shown(), today);
      expect(container.read(browsedDayProvider).isToday, isTrue);
    });

    test('(BS-93) the profile start limits the way back', () async {
      await start(profileStart: LocalDate(2026, 10, 5));
      days().previous();
      days().previous();
      expect(shown(), LocalDate(2026, 10, 5));
      days().previous();
      expect(
        shown(),
        LocalDate(2026, 10, 5),
        reason: 'no day before the start',
      );
      days().select(LocalDate(2026, 10, 4));
      expect(shown(), LocalDate(2026, 10, 5));
    });

    test('(BS-93) on the first day of the profile there is nothing to page '
        'through', () async {
      await start(profileStart: today);
      final day = container.read(browsedDayProvider);
      expect(day.isBrowsable, isFalse);
      days().previous();
      expect(shown(), today);
    });
  });

  group('a new calendar day (BS-93, D-029)', () {
    test('(BS-93) Home on today moves with the clock past midnight', () async {
      await start(nowIso: '2026-10-07T21:59:30Z'); // 23:59:30 in Berlin
      expect(shown(), today);
      harness.clock.advance(const Duration(seconds: 60));
      container.read(todayProvider.notifier).refresh();
      expect(shown(), LocalDate(2026, 10, 8));
      expect(container.read(browsedDayProvider).isToday, isTrue);
    });

    test('(BS-93) a day chosen before midnight is dropped: after midnight Home '
        'shows the new today, never a stale day', () async {
      await start(nowIso: '2026-10-07T21:59:30Z');
      days().select(LocalDate(2026, 10, 5));
      expect(shown(), LocalDate(2026, 10, 5));
      harness.clock.advance(const Duration(seconds: 60));
      container.read(todayProvider.notifier).refresh();
      expect(shown(), LocalDate(2026, 10, 8));
      expect(container.read(selectedDayProvider), isNull);
    });

    test('(BS-93) the app in the background over midnight: on return the '
        'choice is gone and the window moved by a day', () async {
      await start();
      days().select(today.addDays(-7)); // the oldest day
      expect(shown(), LocalDate(2026, 9, 30));
      // The device slept for 14 hours, over midnight, and the app comes back.
      harness.clock.advance(const Duration(hours: 14));
      container.read(todayProvider.notifier).refresh();
      final day = container.read(browsedDayProvider);
      expect(day.date, LocalDate(2026, 10, 8));
      expect(day.oldest, LocalDate(2026, 10, 1));
      expect(
        day.canGoBack,
        isTrue,
        reason: 'the new window is seven days again',
      );
    });

    test('(BS-93) without a new day nothing changes (a refresh within the '
        'day keeps the choice)', () async {
      await start();
      days().select(LocalDate(2026, 10, 4));
      harness.clock.advance(const Duration(hours: 3));
      container.read(todayProvider.notifier).refresh();
      expect(shown(), LocalDate(2026, 10, 4));
    });
  });

  group('days with a daylight saving change (BS-93, AT25)', () {
    test('(BS-93, AT25) spring: past midnight of 29 March the new today is the '
        '29th, the window has eight days and the 28th is "gestern"', () async {
      // 2026-03-28 23:30 in Berlin (CET, UTC+1), the night the clocks go
      // forward at 02:00.
      await start(
        nowIso: '2026-03-28T22:30:00Z',
        profileStart: LocalDate(2026, 3, 1),
      );
      expect(shown(), LocalDate(2026, 3, 28));
      harness.clock.advance(const Duration(hours: 1)); // 00:30 CET, the 29th
      container.read(todayProvider.notifier).refresh();
      var day = container.read(browsedDayProvider);
      expect(day.date, LocalDate(2026, 3, 29));
      days().previous();
      day = container.read(browsedDayProvider);
      expect(day.date, LocalDate(2026, 3, 28));
      expect(day.spoken, 'Samstag, 28. März, gestern');
      // After the change (04:30 CEST) it is still the 29th; 24 hours after
      // 00:30 CET it is the 30th (the 29th had only 23 hours), not the 31st.
      harness.clock.advance(const Duration(hours: 3));
      container.read(todayProvider.notifier).refresh();
      expect(container.read(browsedDayProvider).today, LocalDate(2026, 3, 29));
      harness.clock.advance(const Duration(hours: 21));
      container.read(todayProvider.notifier).refresh();
      expect(container.read(browsedDayProvider).today, LocalDate(2026, 3, 30));
    });

    test('(BS-93, AT25) autumn: the 25-hour day of 25 October is one day, the '
        'next midnight is the 26th', () async {
      // 2026-10-24 23:30 in Berlin (CEST, UTC+2); the clocks go back at 03:00.
      await start(
        nowIso: '2026-10-24T21:30:00Z',
        profileStart: LocalDate(2026, 10, 1),
      );
      expect(shown(), LocalDate(2026, 10, 24));
      harness.clock.advance(const Duration(hours: 1)); // 00:30 CEST, the 25th
      container.read(todayProvider.notifier).refresh();
      expect(shown(), LocalDate(2026, 10, 25));
      // The 25th has 25 hours: 24 hours after 00:30 CEST it is 23:30 CET and
      // still the 25th.
      harness.clock.advance(const Duration(hours: 24));
      container.read(todayProvider.notifier).refresh();
      expect(container.read(browsedDayProvider).today, LocalDate(2026, 10, 25));
      harness.clock.advance(const Duration(hours: 1));
      container.read(todayProvider.notifier).refresh();
      expect(container.read(browsedDayProvider).today, LocalDate(2026, 10, 26));
    });
  });

  group('travelling (BS-93, AT25)', () {
    test('(BS-93, AT25) travelling west: today is a day earlier, and no day '
        'after it can be shown or chosen', () async {
      // 03:00 on Saturday, 3 October in Berlin.
      await start(nowIso: '2026-10-03T01:00:00Z');
      expect(shown(), LocalDate(2026, 10, 3));
      // 21:00 on Friday, 2 October in New York (the same instant).
      harness.clock.setTimeZone('America/New_York');
      container.read(todayProvider.notifier).refresh();
      final day = container.read(browsedDayProvider);
      expect(day.today, LocalDate(2026, 10, 2));
      expect(day.date, LocalDate(2026, 10, 2));
      expect(day.canGoForward, isFalse);
      // The 3rd, in which records were made at home, lies in the future now.
      days().select(LocalDate(2026, 10, 3));
      expect(shown(), LocalDate(2026, 10, 2));
      expect(day.oldest, LocalDate(2026, 9, 25));
    });

    test('(BS-93, AT25) travelling east: the choice is dropped and the day '
        'that was today is "gestern"', () async {
      // 14:00 on Saturday, 3 October in Berlin.
      await start(nowIso: '2026-10-03T12:00:00Z');
      days().select(LocalDate(2026, 10, 1));
      // 02:00 on Sunday, 4 October on Kiritimati (UTC+14).
      harness.clock.setTimeZone('Pacific/Kiritimati');
      container.read(todayProvider.notifier).refresh();
      expect(container.read(selectedDayProvider), isNull);
      days().previous();
      final day = container.read(browsedDayProvider);
      expect(day.today, LocalDate(2026, 10, 4));
      expect(day.date, LocalDate(2026, 10, 3));
      expect(day.relativeText, 'gestern');
    });
  });
}
