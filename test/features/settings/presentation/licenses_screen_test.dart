import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';

LicenseEntry entry(List<String> packages, String text) =>
    LicenseEntryWithLineBreaks(packages, text);

final String longText = [
  for (var i = 1; i <= 60; i++)
    'Paragraph $i of a long licence text that has to wrap on a narrow '
        'screen and must stay readable when the text is enlarged to 200 percent.',
].join('\n\n');

List<LicenseEntry> sample() => [
  entry([
    'Inter',
  ], 'SIL OPEN FONT LICENSE Version 1.1\n\nPermission is granted.'),
  entry(['flutter'], 'Copyright The Flutter Authors.\n\nBSD text.'),
  entry(['zeta'], 'Zeta license text'),
  entry(['alpha_pkg'], 'Alpha first text'),
  entry(['alpha_pkg'], 'Alpha second text'),
  entry(['Beta'], longText),
];

Future<ScreenEnv> open(
  WidgetTester tester, {
  Stream<LicenseEntry> Function()? source,
  Size size = const Size(393, 852),
  double textScale = 1.0,
}) async {
  final env = await createScreenEnv(
    tester,
    overrides: [
      licenseSourceProvider.overrideWithValue(
        source ?? () => Stream.fromIterable(sample()),
      ),
    ],
  );
  await openScreen(
    tester,
    env,
    SettingsRoutes.licenses,
    size: size,
    textScale: textScale,
  );
  return env;
}

Future<void> tapBack(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is AppIconButton && w.semanticLabel == 'Zurück',
    ),
  );
  await settle(tester);
}

void main() {
  group('list', () {
    testWidgets('names the font, the SDK and the real number of packages', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Inter (Schrift)'), findsOneWidget);
      expect(find.text('SIL Open Font License 1.1'), findsOneWidget);
      expect(find.text('Flutter SDK'), findsOneWidget);
      expect(find.text('BSD-3-Clause'), findsOneWidget);
      expect(find.text('Open-Source-Pakete'), findsOneWidget);
      expect(
        find.text('3 Pakete'),
        findsOneWidget,
        reason: 'zeta, alpha, Beta',
      );
      expect(find.textContaining('Material Icons'), findsOneWidget);
      await savePng(tester, 'build/profile_shots/licenses.png');
    });

    testWidgets('shows what the registry has, also without the SDK entry', (
      tester,
    ) async {
      await open(
        tester,
        source: () => Stream.fromIterable([
          entry(['Inter'], 'OFL text'),
        ]),
      );
      expect(find.text('Inter (Schrift)'), findsOneWidget);
      expect(find.text('Flutter SDK'), findsNothing);
      expect(find.text('Open-Source-Pakete'), findsNothing);
    });

    testWidgets('says "1 Paket" for a single package', (tester) async {
      await open(
        tester,
        source: () => Stream.fromIterable([
          entry(['only'], 'Text'),
        ]),
      );
      expect(find.text('1 Paket'), findsOneWidget);
    });

    testWidgets('an unreadable rest is reported, the rest is shown', (
      tester,
    ) async {
      Stream<LicenseEntry> failing() async* {
        yield entry(['Inter'], 'OFL');
        throw StateError('asset missing');
      }

      await open(tester, source: failing);
      expect(find.text('Inter (Schrift)'), findsOneWidget);
      expect(find.textContaining('nicht vollständig gelesen'), findsOneWidget);
    });

    testWidgets('an empty registry shows an honest empty state', (
      tester,
    ) async {
      await open(tester, source: () => const Stream<LicenseEntry>.empty());
      expect(find.text('Keine Lizenztexte gefunden'), findsOneWidget);
    });

    testWidgets('shows a short loading note while the registry is read', (
      tester,
    ) async {
      final controller = StreamController<LicenseEntry>();
      await open(tester, source: () => controller.stream);
      expect(find.text('Lizenzen werden geladen …'), findsOneWidget);

      controller.add(entry(['Inter'], 'OFL'));
      unawaited(controller.close());
      await settle(tester);
      expect(find.text('Lizenzen werden geladen …'), findsNothing);
      expect(find.text('Inter (Schrift)'), findsOneWidget);
    });

    testWidgets('a registry without any entry that fails offers a retry', (
      tester,
    ) async {
      var reads = 0;
      Stream<LicenseEntry> source() {
        reads++;
        if (reads == 1) {
          return Stream<LicenseEntry>.error(StateError('no registry'));
        }
        return Stream.fromIterable(sample());
      }

      await open(tester, source: source);
      expect(
        find.text('Lizenzen konnten nicht geladen werden'),
        findsOneWidget,
      );
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Flutter SDK'), findsOneWidget);
    });
  });

  group('texts', () {
    testWidgets('the font opens with its full text and back returns', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Inter (Schrift)'));
      await settle(tester);
      expect(find.text('SIL Open Font License 1.1'), findsOneWidget);
      expect(find.text('SIL OPEN FONT LICENSE Version 1.1'), findsOneWidget);
      expect(find.text('Permission is granted.'), findsOneWidget);

      await tapBack(tester);
      expect(find.text('Open-Source-Pakete'), findsOneWidget);
    });

    testWidgets('packages are listed alphabetically and open their texts', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text('Open-Source-Pakete'));
      await settle(tester);
      final titles = [
        for (final name in ['alpha_pkg', 'Beta', 'zeta'])
          tester.getTopLeft(find.text(name)).dy,
      ];
      expect(titles, orderedEquals([...titles]..sort()), reason: 'a, B, z');
      expect(find.text('2 Lizenztexte'), findsOneWidget);

      await tester.tap(find.text('alpha_pkg'));
      await settle(tester);
      expect(find.text('Lizenztext 1 von 2'), findsOneWidget);
      expect(find.text('Alpha first text'), findsOneWidget);
      expect(find.text('Lizenztext 2 von 2'), findsOneWidget);
      expect(find.text('Alpha second text'), findsOneWidget);
    });

    testWidgets('a long text scrolls to its end on a small screen at 200 %', (
      tester,
    ) async {
      await open(tester, size: const Size(320, 640), textScale: 2.0);
      await tester.tap(find.text('Open-Source-Pakete'));
      await settle(tester);
      await tester.tap(find.text('Beta'));
      await settle(tester);
      expect(find.textContaining('Paragraph 1 of'), findsOneWidget);
      expect(
        find.textContaining('Paragraph 60 of'),
        findsNothing,
        reason: 'lazy',
      );

      await tester.dragUntilVisible(
        find.textContaining('Paragraph 60 of'),
        find.byType(ListView),
        const Offset(0, -400),
        maxIteration: 400,
      );
      expect(find.textContaining('Paragraph 60 of'), findsOneWidget);
      // Nothing overflowed on the way (a RenderFlex error would fail the test).
    });
  });

  testWidgets('the entries have spoken labels (AT34)', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(
      find.bySemanticsLabel('Inter (Schrift), SIL Open Font License 1.1'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Open-Source-Pakete, 3 Pakete'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
