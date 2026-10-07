import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/features/body/presentation/weight_form_screen.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';

import 'support/app_harness.dart';

/// The app is left in landscape and does not break there (BS-114, D-019, AT33).
///
/// Decision D-019: the app neither locks the orientation nor is it designed for
/// landscape (the draft and the route sweep are portrait). This smoke test
/// shows what is checkable and leaves the rest as a documented limit
/// (docs/known-limitations.md): at 852 x 393 (an iPhone 15 Pro turned) and
/// 393 x 852 every page without an id lays out without an exception or an
/// overflow and keeps its tap targets and labels; a form can be reached by
/// scrolling, is saved, and keeps what was typed when the phone is turned.
///
/// What it does NOT show: that landscape is pleasant to read (the iOS tester
/// found it hard to read on an iPhone), that a keyboard of about 250 px or more
/// fits (it does not: header and pinned action need about 144 of the 393 px), a
/// tablet, a foldable, large text in landscape, or anything on a device. The
/// safe-area insets of the turned iPhone (left and right 59, bottom 21) are an
/// approximation of the iPhone 15 Pro, not a measurement.
const Size _landscape = Size(852, 393);
const Size _portrait = Size(393, 852);
const EdgeInsets _turnedPhone = EdgeInsets.fromLTRB(59, 0, 59, 21);

/// Every page of the app that has no id in its path, read from the route table
/// itself: the tabs, the core pages and the pages of all bundled modules. A new
/// page is covered without touching this file; the hand-kept list it replaces
/// had lost the page "Über die App" (BS-98, R1-05). The onboarding is left out
/// (an onboarded app sends it to Home); the tasks view of the Habits tab is a
/// query and no path of its own, so it is added.
final List<String> _pages = <String>{
  for (final path in allRoutePaths(buildAppRoutes(modules: bundledModules)))
    if (!path.contains(':') && path != AppRoutes.onboarding) path,
  AppRoutes.habitsTasks,
}.toList()..sort();

void main() {
  /// Runs [body] in the running app of the given [size] and takes the app down
  /// again when [body] throws: a failed expectation with a page open would
  /// otherwise hang the test run in its tear down instead of failing it.
  Future<void> inApp(
    WidgetTester tester,
    Size size,
    Future<void> Function(AppFixture app) body, {
    EdgeInsets safeArea = EdgeInsets.zero,
  }) async {
    final app = await pumpFullApp(tester, size: size);
    try {
      tester.view.padding = FakeViewPadding(
        left: safeArea.left,
        right: safeArea.right,
        bottom: safeArea.bottom,
      );
      tester.view.viewPadding = tester.view.padding;
      await app.settle();
      await body(app);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await app.settle();
    }
  }

  Future<void> expectNoProblems(
    WidgetTester tester,
    AppFixture app,
    String page,
    List<String> problems,
  ) async {
    app.router.go(page);
    await app.settle();
    Object? error;
    while ((error = tester.takeException()) != null) {
      problems.add('$page: ${error.toString().split('\n').first}');
    }
    for (final (name, guideline) in <(String, AccessibilityGuideline)>[
      ('tap targets', androidTapTargetGuideline),
      ('labels', labeledTapTargetGuideline),
    ]) {
      final result = await guideline.evaluate(tester);
      if (!result.passed) {
        problems.add('$page: $name: ${result.reason?.split('\n').first}');
      }
    }
  }

  group('every page without an id', () {
    test('the sweep finds the core pages and the pages of the modules', () {
      expect(
        _pages,
        containsAll(<String>['/', '/weight/new', '/water', '/settings']),
      );
      expect(_pages.length, greaterThan(25));
    });

    test('the list has the core pages that a hand-kept list lost: Über die App and Ziele heute (BS-114, R1-05, AT33)', () {
      expect(
        _pages,
        containsAll(<String>[
          AppRoutes.about,
          DashboardRoutes.goalsToday,
          AppRoutes.licenses,
          AppRoutes.habitsTasks,
        ]),
      );
      expect(_pages, isNot(contains(AppRoutes.onboarding)));
      expect(
        _pages.where((path) => path.contains(':')),
        isEmpty,
        reason: 'a page with an id needs a record to open',
      );
    });

    for (final (name, size, safeArea) in <(String, Size, EdgeInsets)>[
      ('landscape 852 x 393', _landscape, EdgeInsets.zero),
      (
        'landscape 852 x 393 with the insets of the turned phone',
        _landscape,
        _turnedPhone,
      ),
      ('portrait 393 x 852', _portrait, EdgeInsets.zero),
    ]) {
      testWidgets(
        'lays out without an exception and keeps tap targets and labels in $name (BS-114, AT33)',
        (tester) async {
          final handle = tester.ensureSemantics();
          try {
            await inApp(tester, size, (app) async {
              final problems = <String>[];
              for (final page in _pages) {
                await expectNoProblems(tester, app, page, problems);
              }
              expect(problems, isEmpty);
            }, safeArea: safeArea);
          } finally {
            handle.dispose();
          }
        },
      );
    }
  });

  group('a form in landscape', () {
    Finder heroField() => find.byType(TextField).first;

    Future<void> openWeightForm(AppFixture app) async {
      app.router.go('/weight/new');
      await app.settle();
      expect(find.byType(WeightFormScreen), findsOneWidget);
    }

    testWidgets('can be scrolled to its last field and saved (BS-114, AT33)', (
      tester,
    ) async {
      await inApp(tester, _landscape, (app) async {
        await openWeightForm(app);

        // The last field is below the fold of 393 px: scrolling brings it in.
        final viewport = tester.getRect(
          find.byType(SingleChildScrollView).first,
        );
        expect(
          tester.getRect(find.text('Notiz')).bottom,
          greaterThan(viewport.bottom),
          reason: 'the note is below the visible part',
        );
        await tester.ensureVisible(find.text('Notiz'));
        await tester.pumpAndSettle();
        final note = tester.getRect(find.text('Notiz'));
        expect(note.top, greaterThanOrEqualTo(viewport.top));
        expect(note.bottom, lessThanOrEqualTo(viewport.bottom));

        await tester.enterText(heroField(), '72,5');
        await tester.pump();
        await tester.tap(
          find.widgetWithText(PrimaryButton, 'Eintrag speichern'),
        );
        await app.settle();
        await app.settle();

        expect(find.byType(WeightFormScreen), findsNothing, reason: 'saved');
      });
    });

    testWidgets(
      'fits above a landscape keyboard of 200 px and is saved from there (BS-114, AT33)',
      (tester) async {
        await inApp(tester, _landscape, (app) async {
          await openWeightForm(app);
          tester.view.viewInsets = const FakeViewPadding(bottom: 200);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'no overflow above the keyboard',
          );

          await tester.enterText(heroField(), '72,5');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final save = find.widgetWithText(PrimaryButton, 'Eintrag speichern');
          final screen = Offset.zero & _landscape;
          expect(
            screen.contains(tester.getCenter(save)),
            isTrue,
            reason: 'the save button is on the screen',
          );
          await tester.tap(save);
          await app.settle();
          await app.settle();

          expect(find.byType(WeightFormScreen), findsNothing, reason: 'saved');
        });
      },
    );

    testWidgets(
      'keeps what was typed when the phone is turned there and back (BS-114, AT33)',
      (tester) async {
        await inApp(tester, _portrait, (app) async {
          await openWeightForm(app);
          await tester.enterText(heroField(), '72,5');
          await tester.pumpAndSettle();
          String typed() =>
              tester.widget<TextField>(heroField()).controller!.text;
          expect(typed(), '72,5');

          tester.view.physicalSize = _landscape;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'turned to landscape');
          expect(find.byType(WeightFormScreen), findsOneWidget);
          expect(typed(), '72,5');

          tester.view.physicalSize = _portrait;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'turned back');
          expect(find.byType(WeightFormScreen), findsOneWidget);
          expect(typed(), '72,5');
        });
      },
    );
  });
}
