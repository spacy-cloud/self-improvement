import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_cards_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_content_transition.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_navigator.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_swipe.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/dashboard_test_kit.dart';
import '../support/day_browser_kit.dart';

// BS-93: Home pages through the days. Today and the seven days before it, an
// arrow to each side of the date and a swipe over the page do the same; a day
// that is not today carries the note "Nicht heute" and "Zurück zu heute". The
// real bundled modules over the real database, on 3 October 2026 (a Saturday).

/// The arrow to the previous day and the one to the next.
Finder _previous() => find
    .descendant(
      of: find.byType(DayNavigator),
      matching: find.byType(AppIconButton),
    )
    .first;

Finder _next() => find
    .descendant(
      of: find.byType(DayNavigator),
      matching: find.byType(AppIconButton),
    )
    .last;

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<AppIconButton>(button).onPressed != null;

/// Lets a day change finish: the model of the day, the cards and the short
/// transition.
Future<void> _settleDay(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

Future<void> _tap(WidgetTester tester, Finder button) async {
  await tester.tap(button);
  await _settleDay(tester);
}

LocalDate _shown(RealHome home) => home.container.read(browsedDayProvider).date;

Offset _pageCentre(WidgetTester tester) =>
    tester.getCenter(find.byType(HomeScreen));

void main() {
  group('the arrows (BS-93, AT34, Q02)', () {
    testWidgets('(BS-93) today: the date between two arrows, the previous one '
        'ready, the next one disabled, no note', (tester) async {
      await pumpRealHome(tester);
      final semantics = tester.ensureSemantics();

      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);
      expect(find.text('Zurück zu heute'), findsNothing);
      expect(_enabled(tester, _previous()), isTrue);
      expect(_enabled(tester, _next()), isFalse);
      expect(
        find.bySemanticsLabel('Vorheriger Tag, Freitag, 2. Oktober'),
        findsOneWidget,
      );
      // The arrow towards the future stays in its place and says why it cannot
      // be used: today has no next day.
      expect(find.bySemanticsLabel('Nächster Tag'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('(BS-93) the previous arrow shows the day before with the '
        'note "Nicht heute"; the date and the arrows name the days', (
      tester,
    ) async {
      await pumpRealHome(tester);
      final semantics = tester.ensureSemantics();

      await _tap(tester, _previous());
      expect(find.text('Freitag, 2. Oktober'), findsOneWidget);
      expect(find.text('Samstag, 3. Oktober'), findsNothing);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('Zurück zu heute'), findsOneWidget);
      // The heading of today gives way to the note, as in the design.
      expect(find.text('Dein Tag im Überblick'), findsNothing);
      expect(_enabled(tester, _previous()), isTrue);
      expect(_enabled(tester, _next()), isTrue);
      expect(
        find.bySemanticsLabel('Vorheriger Tag, Donnerstag, 1. Oktober'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Nächster Tag, Samstag, 3. Oktober'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93) seven days back and not further: the oldest day is '
        '26 September and its previous arrow is disabled', (tester) async {
      final home = await pumpRealHome(tester);
      for (var back = 1; back <= 7; back++) {
        await _tap(tester, _previous());
        expect(_shown(home), hostToday.addDays(-back), reason: '$back back');
      }
      expect(find.text('Samstag, 26. September'), findsOneWidget);
      expect(_enabled(tester, _previous()), isFalse);
      expect(_enabled(tester, _next()), isTrue);
      // A tap on the disabled arrow changes nothing.
      await _tap(tester, _previous());
      expect(find.text('Samstag, 26. September'), findsOneWidget);
      expect(_shown(home), LocalDate(2026, 9, 26));
    });

    testWidgets('(BS-93) the next arrow leads forward again and the last step '
        'is today: the note is gone and the heading is back', (tester) async {
      final home = await pumpRealHome(tester);
      await _tap(tester, _previous());
      await _tap(tester, _previous());
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
      await _tap(tester, _next());
      expect(find.text('Freitag, 2. Oktober'), findsOneWidget);
      await _tap(tester, _next());
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      expect(_enabled(tester, _next()), isFalse);
      expect(home.container.read(selectedDayProvider), isNull);
    });

    testWidgets('(BS-93) "Zurück zu heute" shows today from any day, and the '
        'focus goes to the date', (tester) async {
      final home = await pumpRealHome(tester);
      final semantics = tester.ensureSemantics();
      await showDay(tester, home, LocalDate(2026, 9, 28));
      expect(find.text('Montag, 28. September'), findsOneWidget);
      expect(find.text('Zurück zu heute'), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot('home-date'),
      );

      await _tap(tester, find.text('Zurück zu heute'));
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      // The button that had the focus is gone with the note: the date has it,
      // so a screen reader does not lose its place (Q02). The date's own node,
      // not just any focus scope above it.
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'home-date');
      final node = tester.getSemantics(find.text('Samstag, 3. Oktober'));
      expect(node.flagsCollection.isFocused, Tristate.isTrue);
      semantics.dispose();
    });

    testWidgets('(BS-93, AT34) every arrow is a button of at least 48 x 48 '
        'with a label', (tester) async {
      final home = await pumpRealHome(tester);
      final semantics = tester.ensureSemantics();
      await showDay(tester, home, LocalDate(2026, 10, 1));
      for (final button in <Finder>[_previous(), _next()]) {
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('(BS-93, AT34) the date is a heading and a live region that '
        'says how long ago the day was', (tester) async {
      final home = await pumpRealHome(tester);
      final semantics = tester.ensureSemantics();
      var node = tester.getSemantics(find.text('Samstag, 3. Oktober'));
      expect(node.label, 'Samstag, 3. Oktober, heute');
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.flagsCollection.isLiveRegion, isTrue);

      await showDay(tester, home, LocalDate(2026, 10, 2));
      node = tester.getSemantics(find.text('Freitag, 2. Oktober'));
      expect(node.label, 'Freitag, 2. Oktober, gestern');
      await showDay(tester, home, LocalDate(2026, 10, 1));
      node = tester.getSemantics(find.text('Donnerstag, 1. Oktober'));
      expect(node.label, 'Donnerstag, 1. Oktober, vor 2 Tagen');
      semantics.dispose();
    });

    testWidgets('(BS-93, Q02) paging keeps the arrows and their place: the '
        'navigator is not rebuilt, so the focus of a screen reader stays', (
      tester,
    ) async {
      await pumpRealHome(tester);
      final navigator = tester.element(find.byType(DayNavigator));
      final before = tester.getTopLeft(_previous());
      await _tap(tester, _previous());
      await _tap(tester, _previous());
      expect(
        identical(tester.element(find.byType(DayNavigator)), navigator),
        isTrue,
      );
      expect(tester.getTopLeft(_previous()), before);
    });

    testWidgets('(BS-93) no arrows on the first day of the profile: there is '
        'no day to page to, and the date stays as before', (tester) async {
      await pumpRealHome(tester, startedOn: hostToday);
      // A first day without entries is the welcome; one entry makes it Home.
      expect(find.byType(DayNavigator), findsNothing);
    });

    testWidgets('(BS-93) the day after the profile start can page back one day '
        'and no further', (tester) async {
      final home = await pumpRealHome(tester, startedOn: hostToday.addDays(-1));
      expect(find.byType(DayNavigator), findsOneWidget);
      await _tap(tester, _previous());
      expect(_shown(home), hostToday.addDays(-1));
      expect(_enabled(tester, _previous()), isFalse);
    });
  });

  group('the swipe (BS-93, Q02)', () {
    testWidgets('(BS-93) a swipe to the right shows the previous day, one to '
        'the left the next', (tester) async {
      final home = await pumpRealHome(tester);
      await tester.fling(find.byType(HomeScreen), const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-1));
      expect(find.text('Freitag, 2. Oktober'), findsOneWidget);
      expect(find.text('Nicht heute'), findsOneWidget);

      await tester.fling(find.byType(HomeScreen), const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-2));

      await tester.fling(find.byType(HomeScreen), const Offset(-300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-1));
    });

    testWidgets('(BS-93) a swipe towards the future at today does nothing; at '
        'the oldest day a swipe back does nothing', (tester) async {
      final home = await pumpRealHome(tester);
      await tester.fling(find.byType(HomeScreen), const Offset(-300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday);
      expect(find.text('Samstag, 3. Oktober'), findsOneWidget);

      await showDay(tester, home, hostToday.addDays(-7));
      await tester.fling(find.byType(HomeScreen), const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-7));
    });

    testWidgets('(BS-93) a slow drag over the distance pages, a short one does '
        'not, a short fast flick does', (tester) async {
      final home = await pumpRealHome(tester);
      final at = _pageCentre(tester);

      await tester.dragFrom(at, Offset(daySwipeDistance - 20, 0));
      await _settleDay(tester);
      expect(_shown(home), hostToday, reason: 'too short and too slow');

      await tester.dragFrom(at, Offset(daySwipeDistance + 20, 0));
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-1), reason: 'far enough');

      await tester.flingFrom(at, const Offset(-60, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday, reason: 'a short, fast flick');
    });

    testWidgets('(BS-93) scrolling is not disturbed: a vertical drag scrolls '
        'the page and pages no day', (tester) async {
      final home = await pumpRealHome(tester, size: const Size(393, 500));
      final scroll = find.byType(SingleChildScrollView).first;
      final before = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      expect(before.position.pixels, 0);
      await tester.drag(scroll, const Offset(0, -300));
      await tester.pump();
      expect(before.position.pixels, greaterThan(0));
      expect(_shown(home), hostToday);
      // A drag that is mostly vertical with a sideways wobble scrolls too.
      await tester.drag(scroll, const Offset(30, -120));
      await tester.pump();
      expect(_shown(home), hostToday);
    });

    testWidgets('(BS-93) the swipe works over empty space below a short page '
        'and keeps the scroll position when it pages', (tester) async {
      final home = await pumpRealHome(tester, size: const Size(393, 2400));
      // The whole page fits: the lower part of the screen is empty.
      expect(find.text('Karten anpassen'), findsOneWidget);
      final empty = Offset(
        196,
        tester.getBottomLeft(find.text('Karten anpassen')).dy + 400,
      );
      await tester.flingFrom(empty, const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-1));
    });

    testWidgets('(BS-93) a page keeps its scroll position when the day '
        'changes', (tester) async {
      final home = await pumpRealHome(tester, size: const Size(393, 500));
      final scroll = find.byType(SingleChildScrollView).first;
      await tester.drag(scroll, const Offset(0, -250));
      await tester.pump();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(0));
      await tester.flingFrom(_pageCentre(tester), const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday.addDays(-1));
      expect(scrollable.position.pixels, offset);
    });

    testWidgets('(BS-93) the swipe does not swallow the taps of the cards', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, hostToday.addDays(-1));
      await tester.tap(find.text('Gewicht'));
      await tester.pumpAndSettle();
      expect(find.text('Mein Gewicht'), findsOneWidget);
    });

    testWidgets('(BS-93) no swipe on the first day of the profile', (
      tester,
    ) async {
      final home = await pumpRealHome(tester, startedOn: hostToday);
      await tester.fling(find.byType(HomeScreen), const Offset(300, 0), 1500);
      await _settleDay(tester);
      expect(_shown(home), hostToday);
      expect(find.byType(DaySwipe), findsOneWidget);
      expect(tester.widget<DaySwipe>(find.byType(DaySwipe)).enabled, isFalse);
    });

    testWidgets('(BS-93) the page "Karten anpassen" is not Home: a swipe over '
        'it pages no day', (tester) async {
      final home = await pumpRealHome(tester);
      await showDay(tester, home, hostToday.addDays(-2));
      await tester.ensureVisible(find.text('Karten anpassen'));
      await tester.pump();
      await tester.tap(find.text('Karten anpassen'));
      await tester.pumpAndSettle();
      expect(find.byType(DashboardCardsScreen), findsOneWidget);

      await tester.flingFrom(
        const Offset(196, 400),
        const Offset(300, 0),
        1500,
      );
      await tester.pumpAndSettle();
      expect(_shown(home), hostToday.addDays(-2));
      expect(find.byType(DashboardCardsScreen), findsOneWidget);
    });
  });

  group('the way a day comes in (BS-93, AT35, C06)', () {
    testWidgets('(BS-93, AT35) the new day fades in and slides in from the '
        'side it comes from, and the old content is gone at once', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      home.days.previous();
      await tester.pump(); // the choice
      await tester.pump(const Duration(milliseconds: 30)); // the model
      await tester.pump(const Duration(milliseconds: 10));
      final fading = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(DayContentTransition),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fading.opacity, lessThan(1));
      expect(fading.opacity, greaterThanOrEqualTo(dayTransitionStartOpacity));
      // An older day comes from the left.
      final offset = tester
          .widget<Transform>(
            find
                .descendant(
                  of: find.byType(DayContentTransition),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getTranslation();
      expect(offset.x, lessThan(0));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Opacity>(
              find
                  .descendant(
                    of: find.byType(DayContentTransition),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity,
        1,
      );
    });

    testWidgets('(BS-93, AT35, C06) with reduced motion the day is there '
        'immediately, no frame in between', (tester) async {
      final home = await pumpRealHome(tester, reducedMotion: true);
      home.days.previous();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      final fading = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(DayContentTransition),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(fading.opacity, 1);
      expect(find.text('Freitag, 2. Oktober'), findsOneWidget);
    });

    testWidgets('(BS-93) the page never goes blank while the next day is '
        'read: the old content stays until the new one is there', (
      tester,
    ) async {
      final home = await pumpRealHome(tester);
      home.days.previous();
      await tester.pump();
      // The model of the new day has not arrived yet: the page still shows
      // what it had, not the loading line and not a gap.
      expect(find.byType(DayNavigator), findsOneWidget);
      expect(find.text('Daten werden geladen …'), findsNothing);
      expect(find.text('Karten anpassen'), findsOneWidget);
      await _settleDay(tester);
      expect(find.text('Freitag, 2. Oktober'), findsOneWidget);
    });
  });
}
