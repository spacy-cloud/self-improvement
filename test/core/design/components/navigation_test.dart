import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';

import '../support/design_test_harness.dart';

Widget _nav({
  int selectedIndex = 0,
  ValueChanged<int>? onSelected,
  VoidCallback? onPlus,
  bool plusOpen = false,
}) {
  return AppBottomNavBar(
    selectedIndex: selectedIndex,
    onSelected: onSelected ?? (_) {},
    onPlusPressed: onPlus ?? () {},
    plusOpen: plusOpen,
  );
}

Future<void> _pumpNav(
  WidgetTester tester,
  Widget nav, {
  AppThemeVariant variant = AppThemeVariant.light,
  double width = 393,
  double textScale = 1,
  bool? reduceMotion,
  bool disableAnimations = false,
}) {
  return pumpDesign(
    tester,
    Align(alignment: Alignment.bottomCenter, child: nav),
    variant: variant,
    width: width,
    textScale: textScale,
    scrollable: false,
    reduceMotion: reduceMotion,
    disableAnimations: disableAnimations,
  );
}

void main() {
  setUpAll(loadInterFont);

  group('AppBottomNavBar', () {
    test('has exactly the four destinations Home, Analyse, Habits, Profil', () {
      expect(
        AppBottomNavBar.destinations.map((d) => d.label).toList(),
        <String>['Home', 'Analyse', 'Habits', 'Profil'],
      );
    });

    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: selected tab, labels and plus action', (
        tester,
      ) async {
        await _pumpNav(tester, _nav(selectedIndex: 1), variant: variant);
        for (final label in <String>['Home', 'Analyse', 'Habits', 'Profil']) {
          expect(find.text(label), findsOneWidget);
        }
        // Selected: tinted pill, primary text; others: secondary text.
        expect(textColor(tester, 'Analyse'), colors.primaryText);
        expect(textColor(tester, 'Home'), colors.textSecondary);
        expect(textColor(tester, 'Habits'), colors.textSecondary);
        expect(textColor(tester, 'Profil'), colors.textSecondary);
        final selectedPill = materialOf(
          tester,
          find
              .ancestor(
                of: find.text('Analyse'),
                matching: find.byType(InkSurface),
              )
              .first,
        );
        expect(selectedPill.color, colors.primaryTint);
        final otherPill = materialOf(
          tester,
          find
              .ancestor(
                of: find.text('Home'),
                matching: find.byType(InkSurface),
              )
              .first,
        );
        expect(otherPill.color, Colors.transparent);

        // Selected state is exposed to screen readers.
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Analyse'))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        for (final label in <String>['Home', 'Habits', 'Profil']) {
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(label))
                .flagsCollection
                .isSelected,
            Tristate.isFalse,
          );
        }

        // The plus button is an action, not a tab.
        final plus = tester.getSemantics(
          find.bySemanticsLabel('Eintrag hinzufügen'),
        );
        expect(plus.flagsCollection.isButton, isTrue);
        expect(plus.flagsCollection.isSelected, Tristate.none);
        expect(plus.rect.size, const Size(68, 68));
        expect(find.bySemanticsLabel('Hauptnavigation'), findsOneWidget);
      });
    }

    testSemantics(
      'every tab and the plus button have a tap target of at least 48 x 48',
      (tester) async {
        for (final width in <double>[320, 360, 393, 430]) {
          await _pumpNav(tester, _nav(), width: width);
          for (final label in <String>['Home', 'Analyse', 'Habits', 'Profil']) {
            final size = tester
                .getSemantics(find.bySemanticsLabel(label))
                .rect
                .size;
            expect(
              size.width,
              greaterThanOrEqualTo(48),
              reason: '$label at $width',
            );
            expect(
              size.height,
              greaterThanOrEqualTo(48),
              reason: '$label at $width',
            );
          }
          expect(
            tester
                .getSemantics(find.bySemanticsLabel('Eintrag hinzufügen'))
                .rect
                .size,
            const Size(68, 68),
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('tabs report their index, the plus button its own callback', (
      tester,
    ) async {
      final selected = <int>[];
      var plus = 0;
      await _pumpNav(
        tester,
        _nav(selectedIndex: 0, onSelected: selected.add, onPlus: () => plus++),
      );
      await tester.tap(find.text('Home'));
      await tester.tap(find.text('Analyse'));
      await tester.tap(find.text('Habits'));
      await tester.tap(find.text('Profil'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, <int>[0, 1, 2, 3]);
      expect(plus, 0);

      await tester.tap(find.byIcon(AppIcon.plus.data));
      await tester.pump(const Duration(milliseconds: 400));
      expect(plus, 1);
      expect(selected, <int>[0, 1, 2, 3]);
    });

    testWidgets(
      'the centre plus button sits between Analyse and Habits and above the bar',
      (tester) async {
        await _pumpNav(tester, _nav());
        final analyse = tester.getCenter(find.text('Analyse')).dx;
        final habits = tester.getCenter(find.text('Habits')).dx;
        final plusCenter = tester.getCenter(find.byIcon(AppIcon.plus.data));
        expect(plusCenter.dx, closeTo(393 / 2, 0.5));
        expect(plusCenter.dx, greaterThan(analyse));
        expect(plusCenter.dx, lessThan(habits));
        // The plus halo is raised above the tab labels (Figma composition).
        expect(plusCenter.dy, lessThan(tester.getCenter(find.text('Home')).dy));
      },
    );

    testWidgets('each destination is hit-testable where it is drawn', (
      tester,
    ) async {
      final selected = <int>[];
      await _pumpNav(tester, _nav(onSelected: selected.add));
      for (var i = 0; i < 4; i++) {
        final label = AppBottomNavBar.destinations[i].label;
        final rect = tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkSurface))
              .first,
        );
        await tester.tapAt(rect.center);
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(selected, <int>[0, 1, 2, 3]);
    });

    for (final width in <double>[320, 360, 393, 430]) {
      testWidgets('no overflow at ${width.toInt()} px and 200 % text', (
        tester,
      ) async {
        await _pumpNav(
          tester,
          _nav(selectedIndex: 2),
          width: width,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        // Labels follow the scale only up to 1.3: the pill stays compact.
        final pill = tester.getRect(
          find
              .ancestor(
                of: find.text('Analyse'),
                matching: find.byType(InkSurface),
              )
              .first,
        );
        expect(pill.height, lessThan(80));
      });
    }

    testWidgets(
      'tabs stay inside the screen and do not overlap the plus slot',
      (tester) async {
        for (final width in <double>[320, 393]) {
          await _pumpNav(tester, _nav(), width: width);
          final plus = tester.getRect(
            find
                .ancestor(
                  of: find.byIcon(AppIcon.plus.data),
                  matching: find.byType(InkSurface),
                )
                .first,
          );
          final habits = tester.getRect(
            find
                .ancestor(
                  of: find.text('Habits'),
                  matching: find.byType(InkSurface),
                )
                .first,
          );
          final analyse = tester.getRect(
            find
                .ancestor(
                  of: find.text('Analyse'),
                  matching: find.byType(InkSurface),
                )
                .first,
          );
          final home = tester.getRect(
            find
                .ancestor(
                  of: find.text('Home'),
                  matching: find.byType(InkSurface),
                )
                .first,
          );
          final profil = tester.getRect(
            find
                .ancestor(
                  of: find.text('Profil'),
                  matching: find.byType(InkSurface),
                )
                .first,
          );
          expect(home.left, greaterThanOrEqualTo(0));
          expect(profil.right, lessThanOrEqualTo(width));
          expect(analyse.right, lessThanOrEqualTo(plus.left + 0.01));
          expect(habits.left, greaterThanOrEqualTo(plus.right - 0.01));
        }
      },
    );

    for (final variant in allVariants) {
      final colors = variant.colors;
      testSemantics(
        '${variant.name}: the open plus button is a red close button',
        (tester) async {
          await _pumpNav(tester, _nav(plusOpen: true), variant: variant);
          expect(find.bySemanticsLabel('Schließen'), findsOneWidget);
          expect(find.bySemanticsLabel('Eintrag hinzufügen'), findsNothing);
          final decorated = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(AppBottomNavBar),
              matching: find.byType(AnimatedContainer),
            ),
          );
          expect((decorated.decoration! as BoxDecoration).color, colors.error);
          final rotation = tester.widget<AnimatedRotation>(
            find.byType(AnimatedRotation),
          );
          expect(rotation.turns, 0.125);
          expect(
            tester.widget<Icon>(find.byIcon(AppIcon.plus.data)).color,
            colors.onError,
          );
        },
      );

      testWidgets(
        '${variant.name}: the closed plus button uses the button colour',
        (tester) async {
          await _pumpNav(tester, _nav(), variant: variant);
          final decorated = tester.widget<AnimatedContainer>(
            find.descendant(
              of: find.byType(AppBottomNavBar),
              matching: find.byType(AnimatedContainer),
            ),
          );
          expect(
            (decorated.decoration! as BoxDecoration).color,
            colors.primaryButton,
          );
          expect(
            tester.widget<Icon>(find.byIcon(AppIcon.plus.data)).color,
            colors.onPrimary,
          );
          expect(
            tester
                .widget<AnimatedRotation>(find.byType(AnimatedRotation))
                .turns,
            0,
          );
        },
      );
    }

    testWidgets('the plus rotates in 150 ms, immediately with reduced motion', (
      tester,
    ) async {
      Widget host(bool open) => _nav(plusOpen: open);
      double turns() => tester
          .renderObject<RenderBox>(find.byIcon(AppIcon.plus.data))
          .getTransformTo(null)
          .getRotation()
          .storage[1];

      await _pumpNav(tester, host(false));
      await _pumpNav(tester, host(true));
      await tester.pump(const Duration(milliseconds: 40));
      final mid = turns().abs();
      expect(mid, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 400));
      final end = turns().abs();
      expect(mid, lessThan(end));

      await _pumpNav(tester, host(false), reduceMotion: true);
      await _pumpNav(tester, host(true), reduceMotion: true);
      await tester.pump(const Duration(milliseconds: 1));
      expect(turns().abs(), closeTo(end, 0.001));
    });

    testWidgets(
      'the labels use the Caption/Nav style with a heavier selected label',
      (tester) async {
        await _pumpNav(tester, _nav(selectedIndex: 0));
        final selected = tester.widget<Text>(find.text('Home')).style!;
        final other = tester.widget<Text>(find.text('Analyse')).style!;
        expect(selected.fontSize, 10);
        expect(other.fontSize, 10);
        expect(selected.fontWeight, FontWeight.w600);
        expect(other.fontWeight, FontWeight.w500);
      },
    );

    testWidgets('respects the bottom safe area', (tester) async {
      tester.view.padding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      await _pumpNav(tester, _nav());
      final rect = tester.getRect(find.byType(AppBottomNavBar));
      final pill = tester.getRect(
        find
            .ancestor(of: find.text('Home'), matching: find.byType(InkSurface))
            .first,
      );
      expect(rect.bottom - pill.bottom, greaterThanOrEqualTo(34));
    });
  });

  group('AppHeader', () {
    testSemantics('tab header: title as heading, no back button', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppHeader(title: 'Mein Dashboard'),
        scrollable: false,
      );
      expect(find.text('Mein Dashboard'), findsOneWidget);
      expect(find.byType(AppIconButton), findsNothing);
      final title = tester.getSemantics(
        find.bySemanticsLabel('Mein Dashboard'),
      );
      expect(title.flagsCollection.isHeader, isTrue);
      expect(
        tester.widget<Text>(find.text('Mein Dashboard')).style?.fontSize,
        24,
      );
    });

    for (final variant in allVariants) {
      testSemantics(
        '${variant.name}: subpage header has the labelled back button',
        (tester) async {
          await pumpDesign(
            tester,
            const AppHeader.subpage(title: 'Gewicht eintragen'),
            variant: variant,
            scrollable: false,
          );
          expect(find.byType(AppIconButton), findsOneWidget);
          final back = tester.getSemantics(find.bySemanticsLabel('Zurück'));
          expect(back.flagsCollection.isButton, isTrue);
          expect(back.rect.size, const Size(48, 48));
          expect(
            textColor(tester, 'Gewicht eintragen'),
            variant.colors.textPrimary,
          );
          final decoration =
              tester.widget<Ink>(find.byType(Ink)).decoration! as BoxDecoration;
          expect(decoration.color, variant.colors.surface);
        },
      );
    }

    testWidgets('the back button pops the route by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      body: AppHeader.subpage(title: 'Unterseite'),
                    ),
                  ),
                ),
                child: const Text('weiter'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('weiter'));
      await tester.pumpAndSettle();
      expect(find.text('Unterseite'), findsOneWidget);
      await tester.tap(find.byType(AppIconButton));
      await tester.pumpAndSettle();
      expect(find.text('Unterseite'), findsNothing);
      expect(find.text('weiter'), findsOneWidget);
    });

    testWidgets(
      'a custom back callback and label are used, actions are shown',
      (tester) async {
        var backs = 0;
        await pumpDesign(
          tester,
          AppHeader.subpage(
            title: 'Bearbeiten',
            backLabel: 'Schließen ohne Speichern',
            onBack: () => backs++,
            actions: <Widget>[
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                semanticLabel: 'Löschen',
                onPressed: () {},
              ),
            ],
          ),
          scrollable: false,
        );
        expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
        await tester.tap(find.byType(AppIconButton).first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(backs, 1);
      },
    );

    testWidgets(
      'large text stacks back button and title instead of breaking words',
      (tester) async {
        await pumpDesign(
          tester,
          const AppHeader.subpage(title: 'Gewicht eintragen'),
          width: 320,
          textScale: 2,
          scrollable: false,
        );
        expect(tester.takeException(), isNull);
        final back = tester.getRect(find.byType(AppIconButton));
        final title = tester.getRect(find.text('Gewicht eintragen'));
        // The title sits below the back button and uses the full width.
        expect(title.top, greaterThanOrEqualTo(back.bottom - 1));
        expect(title.left, 24);
        expect(title.width, greaterThan(200));
        // Two lines of 48 px: the word "eintragen" stays whole.
        expect(title.height, lessThan(48 * 1.15 * 2 + 1));
      },
    );

    testWidgets(
      'a tab header without actions keeps its single row on large text',
      (tester) async {
        await pumpDesign(
          tester,
          const AppHeader(title: 'Habits'),
          width: 320,
          textScale: 2,
          scrollable: false,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getTopLeft(find.text('Habits')).dx, 24);
      },
    );

    testWidgets(
      'a tab header with actions stacks the actions above the title on large text',
      (tester) async {
        await pumpDesign(
          tester,
          AppHeader(
            title: 'Mein Dashboard',
            actions: <Widget>[
              AppIconButton(
                icon: Icons.add,
                semanticLabel: 'Hinzufügen',
                onPressed: () {},
              ),
            ],
          ),
          width: 320,
          textScale: 2,
          scrollable: false,
        );
        expect(tester.takeException(), isNull);
        final action = tester.getRect(find.byType(AppIconButton));
        final title = tester.getRect(find.text('Mein Dashboard'));
        expect(title.top, greaterThanOrEqualTo(action.bottom - 1));
        expect(action.right, closeTo(320 - 16, 0.01));
      },
    );

    testWidgets('a long title wraps and the header grows on large text', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppHeader.subpage(
          title: 'Eintrag für den gestrigen Tag bearbeiten',
        ),
        width: 320,
        textScale: 2,
        scrollable: false,
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppHeader)).height, greaterThan(64));
    });
  });

  group('AppScaffold', () {
    for (final variant in allVariants) {
      final colors = variant.colors;
      testWidgets(
        '${variant.name}: page background, surface header including the status bar',
        (tester) async {
          tester.view.padding = const FakeViewPadding(top: 24);
          addTearDown(tester.view.resetPadding);
          await pumpDesign(
            tester,
            const AppScaffold(title: 'Mein Dashboard', body: Text('Inhalt')),
            variant: variant,
            wrapScaffold: false,
          );
          expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            colors.background,
          );
          final header = tester.widget<ColoredBox>(
            find
                .ancestor(
                  of: find.byType(AppHeader),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(header.color, colors.surface);
          // The header band reaches the top edge (behind the status bar).
          final bandRect = tester.getRect(
            find
                .ancestor(
                  of: find.byType(AppHeader),
                  matching: find.byType(ColoredBox),
                )
                .first,
          );
          expect(bandRect.top, 0);
          expect(tester.getTopLeft(find.byType(AppHeader)).dy, 24);
        },
      );
    }

    for (final variant in allVariants) {
      testWidgets(
        '${variant.name}: the status bar is transparent with matching icons',
        (tester) async {
          await pumpDesign(
            tester,
            const AppScaffold(title: 'Mein Dashboard', body: Text('Inhalt')),
            variant: variant,
            wrapScaffold: false,
          );
          final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
            find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          );
          final style = region.value;
          expect(style.statusBarColor, Colors.transparent);
          final dark = variant != AppThemeVariant.light;
          expect(
            style.statusBarIconBrightness,
            dark ? Brightness.light : Brightness.dark,
          );
          // The system navigation bar is not touched.
          expect(style.systemNavigationBarColor, isNull);
        },
      );
    }

    testWidgets('the body scrolls and keeps its margin', (tester) async {
      await pumpDesign(
        tester,
        AppScaffold(
          title: 'Liste',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < 40; i++)
                SizedBox(
                  key: ValueKey<int>(i),
                  height: 60,
                  child: Text('Zeile $i'),
                ),
            ],
          ),
        ),
        wrapScaffold: false,
      );
      expect(tester.getTopLeft(find.byKey(const ValueKey<int>(0))).dx, 16);
      // The last row starts below the screen until the body is scrolled.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<int>(39))).dy,
        greaterThan(852),
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -2000),
      );
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey<int>(39))).dy,
        lessThan(852),
      );
    });

    testWidgets('the primary action stays pinned while the content scrolls', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppScaffold.subpage(
          title: 'Gewicht eintragen',
          body: Column(
            children: <Widget>[
              for (var i = 0; i < 40; i++)
                SizedBox(height: 60, child: Text('Zeile $i')),
            ],
          ),
          primaryAction: PrimaryButton(
            label: 'Eintrag speichern',
            onPressed: () {},
          ),
        ),
        wrapScaffold: false,
      );
      final before = tester.getRect(find.byType(PrimaryButton));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -400),
      );
      await tester.pump();
      expect(tester.getRect(find.byType(PrimaryButton)), before);
      expect(before.bottom, lessThanOrEqualTo(852));
      expect(before.left, 16);
      // 8 px above, 56 px button, 16 px below: the pinned action area.
      expect(852 - before.bottom, 16);
      expect(before.height, 56);
    });

    testWidgets('the primary action moves above the keyboard', (tester) async {
      await pumpDesign(
        tester,
        AppScaffold.subpage(
          title: 'Gewicht eintragen',
          body: const AppTextField(label: 'Gewicht in kg'),
          primaryAction: PrimaryButton(
            label: 'Eintrag speichern',
            onPressed: () {},
          ),
        ),
        wrapScaffold: false,
      );
      final closed = tester.getRect(find.byType(PrimaryButton));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final open = tester.getRect(find.byType(PrimaryButton));
      expect(open.bottom, lessThanOrEqualTo(852 - 300));
      expect(open.bottom, lessThan(closed.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('without resizeToAvoidBottomInset the action stays put', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppScaffold.subpage(
          title: 'Gewicht eintragen',
          resizeToAvoidBottomInset: false,
          body: const AppTextField(label: 'Gewicht in kg'),
          primaryAction: PrimaryButton(
            label: 'Eintrag speichern',
            onPressed: () {},
          ),
        ),
        wrapScaffold: false,
      );
      final closed = tester.getRect(find.byType(PrimaryButton));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.getRect(find.byType(PrimaryButton)), closed);
    });

    testWidgets('content is centred with at most 720 px on wide screens', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppScaffold(
          title: 'Breit',
          body: SizedBox(
            key: ValueKey<String>('content'),
            height: 50,
            width: double.infinity,
          ),
        ),
        width: 1000,
        height: 700,
        wrapScaffold: false,
      );
      final rect = tester.getRect(
        find.byKey(const ValueKey<String>('content')),
      );
      expect(rect.width, 720 - 32);
      expect(rect.center.dx, closeTo(500, 0.01));
    });

    testWidgets('the bottom navigation is shown in the scaffold', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppScaffold(
          title: 'Mein Dashboard',
          body: const Text('Inhalt'),
          bottomNavigationBar: _nav(),
        ),
        wrapScaffold: false,
      );
      expect(find.byType(AppBottomNavBar), findsOneWidget);
      expect(tester.getRect(find.byType(AppBottomNavBar)).bottom, 852);
    });

    testWidgets('scrollable: false hands the body the whole area', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppScaffold(
          title: 'Liste',
          scrollable: false,
          body: ListView(
            children: <Widget>[
              for (var i = 0; i < 30; i++)
                SizedBox(height: 60, child: Text('Zeile $i')),
            ],
          ),
        ),
        wrapScaffold: false,
      );
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'safeAreaBottom: false lets the content reach the screen bottom',
      (tester) async {
        tester.view.padding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.resetPadding);
        Widget page({required bool safe}) => AppScaffold(
          title: 'Liste',
          safeAreaBottom: safe,
          scrollable: false,
          body: const SizedBox.expand(key: ValueKey<String>('fill')),
          padding: EdgeInsets.zero,
        );
        await pumpDesign(tester, page(safe: true), wrapScaffold: false);
        final safeBottom = tester
            .getRect(find.byKey(const ValueKey<String>('fill')))
            .bottom;
        expect(safeBottom, 852 - 34);
        await pumpDesign(tester, page(safe: false), wrapScaffold: false);
        final nestedBottom = tester
            .getRect(find.byKey(const ValueKey<String>('fill')))
            .bottom;
        expect(nestedBottom, 852);
      },
    );

    testWidgets('a sub page scaffold shows the back button', (tester) async {
      await pumpDesign(
        tester,
        const AppScaffold.subpage(title: 'Unterseite', body: Text('Inhalt')),
        wrapScaffold: false,
      );
      expect(find.byType(AppIconButton), findsOneWidget);
    });

    testWidgets(
      'large text scrolls without overflow and keeps the action reachable',
      (tester) async {
        await pumpDesign(
          tester,
          AppScaffold.subpage(
            title: 'Gewicht eintragen',
            body: const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppTextField(
                  label: 'Gewicht in kg',
                  requirementLabel: 'Pflichtfeld',
                ),
                SizedBox(height: 16),
                AppTextField(label: 'Notiz', helperText: 'Optional'),
              ],
            ),
            primaryAction: PrimaryButton(
              label: 'Eintrag speichern',
              onPressed: () {},
            ),
          ),
          width: 320,
          height: 568,
          textScale: 2,
          wrapScaffold: false,
        );
        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(PrimaryButton)).bottom,
          lessThanOrEqualTo(568),
        );
      },
    );
  });
}
