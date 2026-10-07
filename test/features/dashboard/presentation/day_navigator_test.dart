import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/day_browser.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_navigator.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';

// BS-93: the row above the day on Home: arrow, date, arrow. Alone, without the
// page: the labels, the ends of the row of days, the focus node of the date and
// the layout with large text.

final LocalDate _today = LocalDate(2026, 10, 7); // a Wednesday

BrowsedDay _day(LocalDate? choice) =>
    BrowsedDay.resolve(today: _today, choice: choice);

Future<void> _pump(
  WidgetTester tester,
  BrowsedDay day, {
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  FocusNode? focus,
  double textScale = 1.0,
  Size size = const Size(393, 852),
  AppThemeVariant theme = AppThemeVariant.light,
}) => pumpApp(
  tester,
  Padding(
    padding: const EdgeInsets.all(16),
    child: DayNavigator(
      day: day,
      onPrevious: onPrevious ?? () {},
      onNext: onNext ?? () {},
      dateFocusNode: focus,
    ),
  ),
  wrapInScaffold: true,
  textScale: textScale,
  size: size,
  theme: theme,
);

Finder _arrows() => find.byType(AppIconButton);

void main() {
  group('the labels name the days (BS-93, AT34, Q02)', () {
    testWidgets('(BS-93, AT34) today: the previous arrow names yesterday, the '
        'next arrow is disabled and has no day to name', (tester) async {
      await _pump(tester, _day(null));
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Vorheriger Tag, Dienstag, 6. Oktober'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Nächster Tag'), findsOneWidget);
      expect(
        tester.widget<AppIconButton>(_arrows().first).onPressed,
        isNotNull,
      );
      expect(tester.widget<AppIconButton>(_arrows().last).onPressed, isNull);
      semantics.dispose();
    });

    testWidgets('(BS-93, AT34) in the middle both arrows name their day', (
      tester,
    ) async {
      await _pump(tester, _day(LocalDate(2026, 10, 4)));
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Vorheriger Tag, Samstag, 3. Oktober'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Nächster Tag, Montag, 5. Oktober'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93, AT34) the oldest day: no previous day to name, the '
        'arrow is disabled', (tester) async {
      await _pump(tester, _day(LocalDate(2026, 9, 30)));
      expect(tester.widget<AppIconButton>(_arrows().first).onPressed, isNull);
      expect(tester.widget<AppIconButton>(_arrows().last).onPressed, isNotNull);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Vorheriger Tag'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('(BS-93, AT34) the arrows call back, and a disabled arrow '
        'does not', (tester) async {
      var previous = 0;
      var next = 0;
      await _pump(
        tester,
        _day(null),
        onPrevious: () => previous++,
        onNext: () => next++,
      );
      await tester.tap(_arrows().first);
      await tester.tap(_arrows().last);
      expect((previous, next), (1, 0));
    });

    testWidgets('(BS-93, AT34) the date is a heading and a live region with '
        'the distance to today in its spoken text', (tester) async {
      await _pump(tester, _day(LocalDate(2026, 10, 5)));
      final semantics = tester.ensureSemantics();
      final node = tester.getSemantics(find.text('Montag, 5. Oktober'));
      expect(node.label, 'Montag, 5. Oktober, vor 2 Tagen');
      expect(node.flagsCollection.isHeader, isTrue);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      semantics.dispose();
    });
  });

  group('the focus (BS-93, Q02)', () {
    testWidgets('(BS-93, Q02) the date takes the focus when asked, and says '
        'so', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pump(tester, _day(null), focus: focus);
      final semantics = tester.ensureSemantics();
      expect(focus.hasFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(
        tester
            .getSemantics(find.text('Mittwoch, 7. Oktober'))
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
      );
      semantics.dispose();
    });

    testWidgets('(BS-93) the date is no stop of the keyboard: Tab goes from '
        'arrow to arrow', (tester) async {
      await _pump(tester, _day(LocalDate(2026, 10, 4)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final first = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final second = FocusManager.instance.primaryFocus;
      expect(first, isNot(second));
      expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
    });
  });

  group('the layout (BS-93, AT33, Q02)', () {
    for (final size in responsiveSizes) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('(BS-93, AT33, Q02) ${size.width.toInt()} px at '
            '${(scale * 100).toInt()} %: no overflow, arrows of 48 x 48, '
            'labelled', (tester) async {
          await _pump(
            tester,
            _day(LocalDate(2026, 10, 3)),
            textScale: scale,
            size: size,
          );
          final semantics = tester.ensureSemantics();
          expect(tester.takeException(), isNull);
          for (var i = 0; i < 2; i++) {
            final box = tester.getSize(_arrows().at(i));
            expect(box.width, greaterThanOrEqualTo(48));
            expect(box.height, greaterThanOrEqualTo(48));
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
        });
      }
    }

    testWidgets('(BS-93, AT33) with large text the arrows take a row above '
        'the date, so a long weekday never breaks inside a word', (
      tester,
    ) async {
      await _pump(
        tester,
        _day(LocalDate(2026, 10, 1)), // a Thursday
        textScale: 2.0,
        size: const Size(320, 640),
      );
      final arrowsBottom = tester.getBottomLeft(_arrows().first).dy;
      final dateTop = tester.getTopLeft(find.textContaining('Donnerstag')).dy;
      expect(dateTop, greaterThanOrEqualTo(arrowsBottom - 1));
      // The date has the whole width: the longest word stays on one line.
      final box = tester.getSize(find.textContaining('Donnerstag'));
      expect(box.width, greaterThan(150));
      expect(tester.takeException(), isNull);
    });

    testWidgets('(BS-93) with normal text the arrows flank the date on one '
        'line', (tester) async {
      await _pump(tester, _day(LocalDate(2026, 10, 1)));
      final first = tester.getCenter(_arrows().first).dy;
      final last = tester.getCenter(_arrows().last).dy;
      final date = tester.getCenter(find.text('Donnerstag, 1. Oktober')).dy;
      expect((first - last).abs(), lessThan(1));
      expect((first - date).abs(), lessThan(2));
      expect(
        tester.getCenter(find.text('Donnerstag, 1. Oktober')).dx,
        closeTo(196.5, 1),
      );
    });

    for (final theme in AppThemeVariant.values) {
      testWidgets('(BS-93, AT35, C06) the row is readable in the ${theme.name} '
          'theme, with an arrow disabled', (tester) async {
        await _pump(tester, _day(null), theme: theme);
        final semantics = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  });
}
