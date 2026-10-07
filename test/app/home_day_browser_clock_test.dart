import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_navigator.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/pump_app.dart';
import 'support/app_harness.dart';

// BS-93: the day Home shows and the clock, in the whole app (shell, router,
// wiring): midnight while the app runs, the app in the background over
// midnight and the return, and the two days of the year with a daylight saving
// change (Europe/Berlin: 29 March and 25 October 2026). The days and the
// records on them are calendar days of the zone, never 24 hour steps of UTC.

/// The arrows of the day navigator.
Finder _arrows() => find.descendant(
  of: find.byType(DayNavigator),
  matching: find.byType(AppIconButton),
);

/// A water record at [atUtc] (the local date is that of the instant in the zone
/// of the harness), like the app freezes it.
Future<void> _water(DataHarness h, String id, String atUtc, int ml) async {
  final at = DateTime.parse(atUtc).toUtc();
  await h.database
      .into(h.database.waterEntries)
      .insert(
        WaterEntriesCompanion.insert(
          id: id,
          amountMl: ml,
          occurredAtUtc: at,
          localDate: h.clock.localDateOf(at),
          timezoneId: h.clock.timeZoneId,
          gamificationEligible: true,
          createdAtUtc: at,
          updatedAtUtc: at,
        ),
      );
}

Future<AppFixture> _pump(
  WidgetTester tester, {
  required String nowIso,
  required LocalDate startedOn,
  Future<void> Function(DataHarness h)? records,
}) async {
  final harness = await createTestHarness(
    tester,
    onboarded: false,
    nowIso: nowIso,
    realProjection: true,
  );
  return pumpFullApp(
    tester,
    reuse: harness,
    onboarded: false,
    nowIso: nowIso,
    seed: (h) async {
      await h.seedOnboarded(startedOn: startedOn);
      await records?.call(h);
      if (records != null) {
        await h.projections.syncDays(<LocalDate>{
          for (var d = startedOn; !d.isAfter(h.clock.today()); d = d.addDays(1))
            d,
        });
      }
    },
  );
}

Future<void> _page(AppFixture app, int arrow) async {
  await app.tester.tap(_arrows().at(arrow));
  await app.tester.pump(const Duration(milliseconds: 300));
  await app.settle();
}

LocalDate _shown(AppFixture app) => app.container.read(browsedDayProvider).date;

void main() {
  group('midnight (BS-93, D-029)', () {
    testWidgets('(BS-93) Home on today moves to the new day when the clock '
        'passes midnight while the app runs', (tester) async {
      // 23:59 in Berlin on Saturday, 3 October.
      final app = await _pump(
        tester,
        nowIso: '2026-10-03T21:59:00Z',
        startedOn: LocalDate(2026, 9, 1),
      );
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      app.harness.clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await app.settle();
      expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
      expect(_shown(app), LocalDate(2026, 10, 4));
      // The new today has its own yesterday: the day that just ended.
      await _page(app, 0);
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsOneWidget);
    });

    testWidgets('(BS-93) a day chosen before midnight is dropped at midnight: '
        'Home shows the new today', (tester) async {
      final app = await _pump(
        tester,
        nowIso: '2026-10-03T21:59:00Z',
        startedOn: LocalDate(2026, 9, 1),
      );
      await _page(app, 0);
      await _page(app, 0);
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
      app.harness.clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await app.settle();
      expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      expect(app.container.read(selectedDayProvider), isNull);
    });

    testWidgets('(BS-93) the app in the background over midnight: on return '
        'Home shows the new today and the window of the new days', (
      tester,
    ) async {
      final app = await _pump(
        tester,
        nowIso: '2026-10-03T08:00:00Z',
        startedOn: LocalDate(2026, 9, 1),
      );
      // The oldest day: seven days before Saturday, 3 October.
      app.container
          .read(selectedDayProvider.notifier)
          .select(LocalDate(2026, 9, 26));
      await app.settle();
      expect(find.text('Samstag, 26. September'), findsOneWidget);
      expect(tester.widget<AppIconButton>(_arrows().first).onPressed, isNull);

      // The phone sleeps for 30 hours: the timer of midnight never ran.
      app.harness.clock.advance(const Duration(hours: 30));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await app.settle();
      await app.settle();

      expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);
      expect(app.container.read(selectedDayProvider), isNull);
      // The way back is seven days again from the new today.
      expect(
        tester.widget<AppIconButton>(_arrows().first).onPressed,
        isNotNull,
      );
      for (var i = 0; i < 7; i++) {
        await _page(app, 0);
      }
      expect(find.text('Sonntag, 27. September'), findsOneWidget);
      expect(tester.widget<AppIconButton>(_arrows().first).onPressed, isNull);
    });
  });

  group('days with a daylight saving change (BS-93, AT25)', () {
    testWidgets('(BS-93, AT25) spring: a record shortly after midnight of '
        '30 March belongs to the 30th although it is still the 29th in UTC', (
      tester,
    ) async {
      final app = await _pump(
        tester,
        nowIso: '2026-03-30T08:00:00Z', // 10:00 CEST on Monday, 30 March
        startedOn: LocalDate(2026, 3, 1),
        records: (h) async {
          // 00:30 CET on the 29th, the night of the change (UTC 28th, 23:30).
          await _water(h, 'a', '2026-03-28T23:30:00Z', 500);
          // 01:30 CEST on the 30th (UTC 29th, 23:30).
          await _water(h, 'b', '2026-03-29T23:30:00Z', 700);
        },
      );
      expect(find.text('Montag, 30. März'), findsOneWidget);
      expect(find.text('0,7 / 2,5 l', findRichText: true), findsOneWidget);

      await _page(app, 0);
      expect(find.text('Sonntag, 29. März'), findsOneWidget);
      expect(find.text('0,5 / 2,5 l', findRichText: true), findsOneWidget);
      expect(find.text('0,7 / 2,5 l', findRichText: true), findsNothing);

      await _page(app, 0);
      expect(find.text('Samstag, 28. März'), findsOneWidget);
      expect(find.text('Nichts eingetragen'), findsOneWidget);
    });

    testWidgets('(BS-93, AT25) spring: the window across the change has eight '
        'days and the 29th is one of them', (tester) async {
      final app = await _pump(
        tester,
        nowIso: '2026-03-30T08:00:00Z',
        startedOn: LocalDate(2026, 3, 1),
      );
      final seen = <String>[];
      for (var i = 0; i < 7; i++) {
        await _page(app, 0);
        seen.add(_shown(app).toIso());
      }
      expect(seen, <String>[
        '2026-03-29',
        '2026-03-28',
        '2026-03-27',
        '2026-03-26',
        '2026-03-25',
        '2026-03-24',
        '2026-03-23',
      ]);
      expect(tester.widget<AppIconButton>(_arrows().first).onPressed, isNull);
    });

    testWidgets('(BS-93, AT25) autumn: the 25-hour day of 25 October shows '
        'both its midnights\' records and none of the 26th', (tester) async {
      final app = await _pump(
        tester,
        nowIso: '2026-10-26T08:00:00Z', // 09:00 CET on Monday, 26 October
        startedOn: LocalDate(2026, 10, 1),
        records: (h) async {
          // 00:30 CEST on the 25th (UTC 24th, 22:30).
          await _water(h, 'c', '2026-10-24T22:30:00Z', 300);
          // 23:30 CET on the 25th (UTC 25th, 22:30).
          await _water(h, 'd', '2026-10-25T22:30:00Z', 400);
          // 00:30 CET on the 26th (UTC 25th, 23:30).
          await _water(h, 'e', '2026-10-25T23:30:00Z', 200);
        },
      );
      expect(find.text('Montag, 26. Oktober'), findsOneWidget);
      expect(find.text('0,2 / 2,5 l', findRichText: true), findsOneWidget);

      await _page(app, 0);
      expect(find.text('Sonntag, 25. Oktober'), findsOneWidget);
      expect(find.text('0,7 / 2,5 l', findRichText: true), findsOneWidget);

      await _page(app, 0);
      expect(find.text('Samstag, 24. Oktober'), findsOneWidget);
      expect(find.text('Nichts eingetragen'), findsOneWidget);
    });

    testWidgets('(BS-93, AT25) autumn: the way forward passes the 25th once '
        'and ends at today', (tester) async {
      final app = await _pump(
        tester,
        nowIso: '2026-10-26T08:00:00Z',
        startedOn: LocalDate(2026, 10, 1),
      );
      app.container
          .read(selectedDayProvider.notifier)
          .select(LocalDate(2026, 10, 19));
      await app.settle();
      final seen = <String>[_shown(app).toIso()];
      for (var i = 0; i < 7; i++) {
        await _page(app, 1);
        seen.add(_shown(app).toIso());
      }
      expect(seen, <String>[for (var d = 19; d <= 26; d++) '2026-10-$d']);
      expect(tester.widget<AppIconButton>(_arrows().last).onPressed, isNull);
    });

    testWidgets('(BS-93, AT25) the midnight of the change itself: the app '
        'open on the evening of 28 March shows the 29th after midnight, '
        'though the night has 23 hours', (tester) async {
      final app = await _pump(
        tester,
        nowIso: '2026-03-28T22:50:00Z', // 23:50 CET
        startedOn: LocalDate(2026, 3, 1),
      );
      expect(find.text('Samstag, 28. März'), findsOneWidget);
      app.harness.clock.advance(const Duration(minutes: 30));
      await tester.pump(const Duration(minutes: 30));
      await app.settle();
      expect(find.text('Sonntag, 29. März'), findsOneWidget);
      // 24 hours later the 30th, not the 31st: the 29th had 23 hours.
      app.harness.clock.advance(const Duration(hours: 24));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await app.settle();
      await app.settle();
      expect(find.text('Montag, 30. März'), findsOneWidget);
    });
  });
}
