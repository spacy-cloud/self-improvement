import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/license_providers.dart';

import '../../../support/pump_app.dart';
import '../../profile/support/screen_env.dart';

const scales = [1.0, 2.0];

/// The licences of the font and the SDK without reading assets: a long text
/// that has to wrap on the narrowest screen.
Stream<LicenseEntry> licenseSource() => Stream.fromIterable([
  LicenseEntryWithLineBreaks(
    ['Inter'],
    'SIL OPEN FONT LICENSE Version 1.1\n\n'
    'PREAMBLE The goals of the Open Font License (OFL) are to stimulate '
    'worldwide development of collaborative font projects.',
  ),
  LicenseEntryWithLineBreaks(['flutter'], 'Copyright The Flutter Authors.'),
]);

Future<ScreenEnv> newEnv(WidgetTester tester) => createScreenEnv(
  tester,
  overrides: [licenseSourceProvider.overrideWithValue(licenseSource)],
);

void main() {
  for (final size in responsiveSizes) {
    for (final scale in scales) {
      final name = '${size.width.toInt()} px, text ${(scale * 100).toInt()} %';

      group(name, () {
        testWidgets(
          'settings fits without overflow, tap targets 48 px and labelled (AT33)',
          (tester) async {
            final handle = tester.ensureSemantics();
            final env = await newEnv(tester);
            await saveProfile(
              tester,
              env,
              name: 'Maximilian Alexander Mustermann-Schmidt',
            );
            await openScreen(
              tester,
              env,
              SettingsRoutes.settings,
              size: size,
              textScale: scale,
            );
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            // Scroll to the end: the last rows are reachable too.
            await tester.scrollUntilVisible(
              find.text('Lizenzen'),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            expect(find.text('Lizenzen'), findsOneWidget);
            handle.dispose();
          },
        );

        testWidgets('the theme sheet keeps its close button reachable', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final env = await newEnv(tester);
          await openScreen(
            tester,
            env,
            SettingsRoutes.settings,
            size: size,
            textScale: scale,
          );
          await tester.tap(find.text('Design'));
          await settle(tester);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          final close = find.widgetWithText(SecondaryButton, 'Schließen');
          await tester.ensureVisible(close);
          await tester.tap(close);
          await settle(tester);
          expect(find.text('Design wählen'), findsNothing);
          handle.dispose();
        });

        testWidgets('the licence list fits and its texts wrap (AT33)', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final env = await newEnv(tester);
          await openScreen(
            tester,
            env,
            SettingsRoutes.licenses,
            size: size,
            textScale: scale,
          );
          expect(find.text('Inter (Schrift)'), findsOneWidget);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await tester.tap(find.text('Inter (Schrift)'));
          await settle(tester);
          expect(find.textContaining('SIL OPEN FONT LICENSE'), findsWidgets);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          handle.dispose();
        });
      });
    }
  }
}
