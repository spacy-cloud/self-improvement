import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';

import '../../../support/pump_app.dart';

// BS-104: the day card on Home is one button that opens "Ziele heute": a
// chevron, the pressed look of the design, one spoken label, a tap area of at
// least 48 x 48, in every theme and at large text. Without a tap callback the
// card still only shows.

Future<void> _pump(
  WidgetTester tester, {
  int fulfilled = 2,
  int applicable = 4,
  VoidCallback? onTap,
  String? motivation = 'Stark unterwegs!',
  double scale = 1.0,
  Size size = const Size(393, 852),
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  await pumpApp(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DayOverviewCard(
        fulfilled: fulfilled,
        applicable: applicable,
        motivation: motivation,
        onTap: onTap,
      ),
    ),
    size: size,
    textScale: scale,
    theme: theme,
    wrapInScaffold: true,
  );
  await tester.pumpAndSettle();
}

/// The decoration of the card (fill and border) as the card draws it.
BoxDecoration _decoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(DayOverviewCard),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

/// Whether a surface of the card is filled with [color] right now.
bool _filledWith(WidgetTester tester, Color color) => tester
    .widgetList<Material>(
      find.descendant(
        of: find.byType(DayOverviewCard),
        matching: find.byType(Material),
      ),
    )
    .any((material) => material.color == color);

void main() {
  group('it is a button (BS-104)', () {
    testWidgets('(C04) a tap calls onTap, once', (tester) async {
      var taps = 0;
      await _pump(tester, onTap: () => taps++);
      await tester.tap(find.byType(DayOverviewCard));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('(C04) a tap on the ring, on the title and on the sentence '
        'counts as a tap on the card', (tester) async {
      var taps = 0;
      await _pump(tester, onTap: () => taps++);
      for (final target in <Finder>[
        find.byType(ProgressRing),
        find.text('Stark unterwegs!'),
        find.textContaining('Du hast heute 2 von 4 Zielen'),
      ]) {
        await tester.tap(target);
        await tester.pump();
      }
      expect(taps, 3);
    });

    testWidgets('(C04) without onTap it only shows: no chevron, no button, a '
        'tap does nothing', (tester) async {
      await _pump(tester);
      final handle = tester.ensureSemantics();
      expect(find.byIcon(AppIcon.chevronRight.data), findsNothing);
      expect(
        find.bySemanticsLabel('Ziele heute, 2 von 4 erreicht, Details öffnen'),
        findsNothing,
      );
      await tester.tap(find.byType(DayOverviewCard));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The ring keeps its own spoken text when the card is not a button.
      expect(find.bySemanticsLabel('2 von 4 Zielen erreicht'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('(C04) the chevron shows that the card opens something', (
      tester,
    ) async {
      await _pump(tester, onTap: () {});
      expect(find.byIcon(AppIcon.chevronRight.data), findsOneWidget);
      final chevron = tester.getRect(find.byIcon(AppIcon.chevronRight.data));
      final card = tester.getRect(find.byType(DayOverviewCard));
      // In the top right corner, inside the card.
      expect(chevron.right, lessThanOrEqualTo(card.right));
      expect(chevron.center.dx, greaterThan(card.center.dx));
      expect(chevron.top - card.top, lessThan(40));
      // It touches neither the ring nor a text.
      expect(
        chevron.overlaps(tester.getRect(find.byType(ProgressRing))),
        isFalse,
      );
      expect(
        chevron.overlaps(tester.getRect(find.text('Stark unterwegs!'))),
        isFalse,
      );
    });
  });

  group('what a screen reader hears (BS-104, AT34)', () {
    for (final (fulfilled, applicable) in const <(int, int)>[
      (2, 4),
      (0, 5),
      (5, 5),
      (1, 1),
    ]) {
      testWidgets(
        '$fulfilled of $applicable: one button with one label, the ring and '
        'the texts inside are not read again',
        (tester) async {
          final handle = tester.ensureSemantics();
          await _pump(
            tester,
            fulfilled: fulfilled,
            applicable: applicable,
            onTap: () {},
          );
          final label =
              'Ziele heute, $fulfilled von $applicable erreicht, Details '
              'öffnen';
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(
            node,
            matchesSemantics(label: label, isButton: true, hasTapAction: true),
          );
          // Nothing of the inside is a node of its own.
          expect(
            find.bySemanticsLabel(RegExp('Zielen? erreicht')),
            findsNothing,
          );
          expect(find.bySemanticsLabel('Stark unterwegs!'), findsNothing);
          expect(find.bySemanticsLabel(RegExp('^Du hast heute')), findsNothing);
          handle.dispose();
        },
      );
    }

    testWidgets('the label follows the numbers', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, onTap: () {});
      expect(
        find.bySemanticsLabel('Ziele heute, 2 von 4 erreicht, Details öffnen'),
        findsOneWidget,
      );
      await _pump(tester, fulfilled: 3, onTap: () {});
      expect(
        find.bySemanticsLabel('Ziele heute, 3 von 4 erreicht, Details öffnen'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('(AT33) the tap area is the whole card, at least 48 x 48', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, onTap: () {});
      final node = tester.getSemantics(
        find.bySemanticsLabel('Ziele heute, 2 von 4 erreicht, Details öffnen'),
      );
      expect(node.rect.width, greaterThanOrEqualTo(48));
      expect(node.rect.height, greaterThanOrEqualTo(48));
      final card = tester.getRect(find.byType(DayOverviewCard));
      expect(node.rect.width, greaterThan(card.width - 4));
      expect(node.rect.height, greaterThan(card.height - 4));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('the pressed look of the design (BS-104, AT35)', () {
    for (final theme in AppThemeVariant.values) {
      testWidgets('${theme.name}: pressed it takes the green tint and the '
          'green border, released it is a plain card again', (tester) async {
        final colors = theme.colors;
        var taps = 0;
        await _pump(tester, theme: theme, onTap: () => taps++);
        // At rest.
        var border = (_decoration(tester).border! as Border).top;
        expect(border.color, colors.borderDecorative);
        expect(border.width, 1);
        expect(_filledWith(tester, colors.primaryTint), isFalse);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(DayOverviewCard)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        border = (_decoration(tester).border! as Border).top;
        expect(border.color, colors.primary);
        expect(border.width, 1.5);
        expect(_filledWith(tester, colors.primaryTint), isTrue);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(taps, 1);
        border = (_decoration(tester).border! as Border).top;
        expect(border.color, colors.borderDecorative);
        expect(border.width, 1);
        expect(_filledWith(tester, colors.primaryTint), isFalse);
      });
    }

    testWidgets('a finger that slides away cancels: no tap, normal look', (
      tester,
    ) async {
      var taps = 0;
      await _pump(tester, onTap: () => taps++);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DayOverviewCard)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(_filledWith(tester, AppColors.light.primaryTint), isTrue);
      await gesture.moveBy(const Offset(0, 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
      expect(_filledWith(tester, AppColors.light.primaryTint), isFalse);
    });

    testWidgets('a card without onTap never takes the pressed look', (
      tester,
    ) async {
      await _pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DayOverviewCard)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final border = (_decoration(tester).border! as Border).top;
      expect(border.color, AppColors.light.borderDecorative);
      expect(_filledWith(tester, AppColors.light.primaryTint), isFalse);
      await gesture.up();
    });
  });

  group('four widths and large text (BS-104, AT33, Q02)', () {
    for (final size in responsiveSizes) {
      for (final scale in const <double>[1.0, 2.0]) {
        testWidgets(
          '${size.width.toInt()} px at text scale $scale: no overflow, chevron '
          'free, tap targets',
          (tester) async {
            await _pump(
              tester,
              onTap: () {},
              size: size,
              scale: scale,
              motivation: 'Heute ist ein guter Tag, um anzufangen.',
            );
            final handle = tester.ensureSemantics();
            expect(tester.takeException(), isNull);
            final chevron = tester.getRect(
              find.byIcon(AppIcon.chevronRight.data),
            );
            final card = tester.getRect(find.byType(DayOverviewCard));
            expect(chevron.right, lessThanOrEqualTo(card.right));
            expect(
              chevron.overlaps(tester.getRect(find.byType(ProgressRing))),
              isFalse,
            );
            expect(
              chevron.overlaps(
                tester.getRect(
                  find.text('Heute ist ein guter Tag, um anzufangen.'),
                ),
              ),
              isFalse,
              reason: 'the chevron never covers the first line',
            );
            tester.view.physicalSize = Size(size.width, 4000);
            await tester.pump();
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            handle.dispose();
          },
        );
      }
    }

    for (final theme in AppThemeVariant.values) {
      testWidgets('${theme.name}: the text stays readable (also pressed)', (
        tester,
      ) async {
        await _pump(tester, theme: theme, onTap: () {});
        final handle = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(DayOverviewCard)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await gesture.cancel();
        handle.dispose();
      });
    }
  });
}
