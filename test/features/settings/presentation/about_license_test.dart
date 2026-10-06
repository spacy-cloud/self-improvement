import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/external_link_opener.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';
import 'package:self_improvement/features/settings/application/own_license.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';
import '../support/about_support.dart';

/// The licence of the own code at the end of the page "Über die App" (BS-120).
/// The page reads the file `LICENSE` from the app's assets; by default these
/// tests use the real asset, so what they see is what the app shows.

/// The file LICENSE as the repository has it.
String licenseFile() => File('LICENSE').readAsStringSync();

/// Every run of white space collapsed to one blank (the file is wrapped at 80
/// columns, the card wraps to the screen).
String normalized(String text) =>
    text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');

Future<ScreenEnv> open(
  WidgetTester tester, {
  List<Override> overrides = const <Override>[],
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  final env = await createScreenEnv(
    tester,
    overrides: [
      externalLinkOpenerProvider.overrideWithValue(FakeExternalLinkOpener()),
      licenseSourceProvider.overrideWithValue(
        () => Stream.fromIterable([
          LicenseEntryWithLineBreaks(['Inter'], 'SIL OPEN FONT LICENSE'),
        ]),
      ),
      ...overrides,
    ],
  );
  await openScreen(
    tester,
    env,
    SettingsRoutes.about,
    size: size,
    textScale: textScale,
    theme: theme,
  );
  return env;
}

/// Waits until the card of the licence shows (the asset is read in real time).
Future<void> untilLoaded(WidgetTester tester) => tester.pumpUntil(
  () => find.text('MIT License').evaluate().isNotEmpty,
  reason: 'the licence text did not load',
);

/// The card of the licence: the last card of the page.
Finder licenseCard() => find.byType(AppCard).last;

/// The texts in the card of the licence, in order.
List<String> cardTexts(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(
    find.descendant(of: licenseCard(), matching: find.byType(Text)),
  ))
    text.data!,
];

ScrollPosition pagePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// Scrolls the page to its end.
Future<void> scrollToEnd(WidgetTester tester) async {
  final position = pagePosition(tester);
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}

void main() {
  group('text', () {
    testWidgets(
      'shows the heading "Lizenz" and the card of the licence below the '
      'licences row, at the very end of the page (BS-120)',
      (tester) async {
        await open(tester);
        await untilLoaded(tester);

        final row = tester.getTopLeft(find.text('Lizenzen')).dy;
        final heading = tester.getTopLeft(find.text('LIZENZ')).dy;
        final card = tester.getTopLeft(licenseCard()).dy;
        expect(row, lessThan(heading), reason: 'the licences row comes first');
        expect(
          heading,
          lessThan(card),
          reason: 'the heading is above the card',
        );

        expect(
          find.byType(AppCard),
          findsNWidgets(3),
          reason: 'the two groups and the licence card, nothing after it',
        );
        await scrollToEnd(tester);
        await savePng(tester, 'build/profile_shots/about_license.png');
      },
    );

    testWidgets(
      'the card shows the full text of the file LICENSE, in its order, '
      'nothing added and nothing dropped (BS-120)',
      (tester) async {
        await open(tester);
        await untilLoaded(tester);

        expect(
          normalized(cardTexts(tester).join(' ')),
          normalized(licenseFile()),
        );
        expect(find.text('MIT License'), findsOneWidget);
        expect(find.text('Copyright (c) 2026 Spacy.cloud'), findsOneWidget);
      },
    );

    testWidgets(
      'every paragraph of the file is one text of the card (BS-120)',
      (tester) async {
        await open(tester);
        await untilLoaded(tester);

        final expected = parseOwnLicense(licenseFile());
        expect(cardTexts(tester), <String>[
          expected.title,
          ...expected.paragraphs,
        ]);
      },
    );

    testWidgets(
      'the page shows what the source delivers: there is no second copy of the '
      'text in the code (BS-120)',
      (tester) async {
        await open(
          tester,
          overrides: [
            ownLicenseSourceProvider.overrideWithValue(
              () async =>
                  'MIT License\n\nCopyright (c) 2099 Example Holder\n\n'
                  'Permission text\nover two lines.\n',
            ),
          ],
        );
        await untilLoaded(tester);

        expect(cardTexts(tester), <String>[
          'MIT License',
          'Copyright (c) 2099 Example Holder',
          'Permission text over two lines.',
        ]);
        expect(
          find.textContaining('Spacy.cloud'),
          findsOneWidget,
          reason: 'author row',
        );
      },
    );

    testWidgets('has the styles of the draft: strong name, small paragraphs '
        '(BS-120)', (tester) async {
      await open(tester);
      await untilLoaded(tester);
      final colors = AppTokens.forVariant(AppThemeVariant.light).colors;

      final title = tester.widget<Text>(find.text('MIT License'));
      expect(title.style?.fontSize, 15);
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(title.style?.color, colors.textPrimary);

      final copyright = tester.widget<Text>(
        find.text('Copyright (c) 2026 Spacy.cloud'),
      );
      expect(copyright.style?.fontSize, 12);
      expect(copyright.style?.fontWeight, FontWeight.w400);
      expect(copyright.style?.color, colors.textSecondary);
      expect(
        tester.getTopLeft(find.text('Copyright (c) 2026 Spacy.cloud')).dy -
            tester.getBottomLeft(find.text('MIT License')).dy,
        10,
        reason: 'paragraphs are 10 px apart',
      );
    });
  });

  group('states', () {
    testWidgets('shows a short note while the text loads, then the card '
        '(BS-120)', (tester) async {
      final gate = Completer<String>();
      await open(
        tester,
        overrides: [
          ownLicenseSourceProvider.overrideWithValue(() => gate.future),
        ],
      );
      expect(find.text('Lizenztext wird geladen …'), findsOneWidget);
      expect(find.text('MIT License'), findsNothing);
      expect(find.text('Autor'), findsOneWidget, reason: 'the page is usable');

      gate.complete('MIT License\n\nCopyright (c) 2026 Spacy.cloud\n');
      await untilLoaded(tester);
      expect(find.text('Lizenztext wird geladen …'), findsNothing);
      expect(find.text('Copyright (c) 2026 Spacy.cloud'), findsOneWidget);
    });

    testWidgets('an unreadable text shows an error with a retry, the rest of '
        'the page stays (BS-120)', (tester) async {
      var reads = 0;
      await open(
        tester,
        overrides: [
          ownLicenseSourceProvider.overrideWithValue(() async {
            reads++;
            if (reads == 1) {
              throw StateError('asset missing');
            }
            return 'MIT License\n\nCopyright (c) 2026 Spacy.cloud\n';
          }),
        ],
      );
      await tester.pumpUntil(
        () => find
            .text('Lizenztext konnte nicht geladen werden')
            .evaluate()
            .isNotEmpty,
        reason: 'the error did not show',
      );
      expect(
        find.text('Der Lizenztext ist Teil der App. Versuche es noch einmal.'),
        findsOneWidget,
      );
      expect(find.text('Autor'), findsOneWidget);
      expect(find.text('MIT License'), findsNothing);

      await tester.ensureVisible(find.text('Erneut versuchen'));
      await tester.tap(find.text('Erneut versuchen'));
      await untilLoaded(tester);
      expect(reads, 2);
      expect(find.text('Lizenztext konnte nicht geladen werden'), findsNothing);
      expect(find.text('Copyright (c) 2026 Spacy.cloud'), findsOneWidget);
    });

    testWidgets('a file without a text counts as an error, not as an empty '
        'card (BS-120)', (tester) async {
      await open(
        tester,
        overrides: [
          ownLicenseSourceProvider.overrideWithValue(() async => '\n\n'),
        ],
      );
      await tester.pumpUntil(
        () => find
            .text('Lizenztext konnte nicht geladen werden')
            .evaluate()
            .isNotEmpty,
        reason: 'the error did not show',
      );
      expect(find.text('MIT License'), findsNothing);
    });
  });

  group('accessibility', () {
    testWidgets('the section has the heading "Lizenz" and the paragraphs are '
        'readable one by one (AT34, BS-120)', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      await untilLoaded(tester);

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('LIZENZ'))
            .flagsCollection
            .isHeader,
        isTrue,
      );
      final expected = parseOwnLicense(licenseFile());
      for (final text in <String>[expected.title, ...expected.paragraphs]) {
        expect(
          find.bySemanticsLabel(text),
          findsOneWidget,
          reason:
              'one node per paragraph: "${text.split(' ').take(3).join(' ')}"',
        );
      }
      handle.dispose();
    });

    testWidgets('the English text is marked as English for a screen reader '
        '(BS-120)', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      await untilLoaded(tester);

      final paragraph = parseOwnLicense(licenseFile()).paragraphs[1];
      final data = tester
          .getSemantics(find.bySemanticsLabel(paragraph))
          .getSemanticsData();
      expect(data.locale, const Locale('en'));
      final heading = tester
          .getSemantics(find.bySemanticsLabel('LIZENZ'))
          .getSemanticsData();
      expect(heading.locale, isNot(const Locale('en')));
      handle.dispose();
    });

    testWidgets('the card has no control: nothing to tap in the licence text '
        '(BS-120)', (tester) async {
      await open(tester);
      await untilLoaded(tester);
      expect(
        find.descendant(of: licenseCard(), matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.descendant(of: licenseCard(), matching: find.byType(Switch)),
        findsNothing,
      );
    });
  });

  group('layout', () {
    testWidgets(
      'at 200 % text on a small screen the page scrolls to the last line of '
      'the licence and nothing is cut off (AT33, BS-120)',
      (tester) async {
        await open(tester, size: const Size(320, 568), textScale: 2);
        await untilLoaded(tester);
        expect(tester.takeException(), isNull, reason: 'no overflow');

        final position = pagePosition(tester);
        expect(
          position.maxScrollExtent,
          greaterThan(600),
          reason: 'a long page',
        );
        await scrollToEnd(tester);
        expect(position.pixels, position.maxScrollExtent);

        final last = parseOwnLicense(licenseFile()).paragraphs.last;
        final lastText = find.text(last);
        final rect = tester.getRect(lastText);
        expect(
          rect.bottom,
          lessThanOrEqualTo(568 - 16 - 16 + 0.5),
          reason: 'the last line ends above card padding and page margin',
        );
        // The paragraph is taller than the screen at this size: its top is
        // above the edge, its end is what has to be visible.
        expect(rect.height, greaterThan(568), reason: 'the page has to scroll');
        expect(
          tester.getRect(licenseCard()).bottom,
          lessThanOrEqualTo(568 - 16 + 0.5),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the first lines of the licence are readable at 200 % too '
        '(AT33, BS-120)', (tester) async {
      await open(tester, size: const Size(320, 640), textScale: 2);
      await untilLoaded(tester);
      await tester.scrollUntilVisible(
        find.text('Copyright (c) 2026 Spacy.cloud'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final rect = tester.getRect(find.text('Copyright (c) 2026 Spacy.cloud'));
      expect(rect.left, greaterThanOrEqualTo(16 + 16 - 0.5));
      expect(rect.right, lessThanOrEqualTo(320 - 16 - 16 + 0.5));
    });

    for (final variant in AppThemeVariant.values) {
      testWidgets('follows the ${variant.name} theme: card, border and text '
          'colours come from its tokens (AT35, BS-120)', (tester) async {
        await open(tester, theme: variant);
        await untilLoaded(tester);
        final colors = AppTokens.forVariant(variant).colors;

        final container = tester.widget<Container>(
          find
              .descendant(of: licenseCard(), matching: find.byType(Container))
              .first,
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.surface);
        expect(
          (decoration.border! as Border).top.color,
          colors.borderDecorative,
        );

        expect(
          tester.widget<Text>(find.text('MIT License')).style?.color,
          colors.textPrimary,
        );
        expect(
          tester
              .widget<Text>(find.text('Copyright (c) 2026 Spacy.cloud'))
              .style
              ?.color,
          colors.textSecondary,
        );
        await scrollToEnd(tester);
        await savePng(
          tester,
          'build/profile_shots/about_license_${variant.name}.png',
        );
      });
    }
  });
}
