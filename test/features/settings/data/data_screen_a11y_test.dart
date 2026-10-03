import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_app.dart';
import 'data_test_support.dart';

/// Layout and accessibility of "Daten & Sicherung" and its sheets: no overflow
/// at 320 to 430 px and 100 % to 200 % text, reachable actions with the
/// keyboard open, tap targets, labels and live regions.
void main() {
  group('responsive layout (AT33)', () {
    for (final size in responsiveSizes) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('screen and sheets fit ${size.width.toInt()} px at '
            '${(scale * 100).toInt()} % text (AT33)', (tester) async {
          final env = await createDataEnv(tester);
          final source = await makeSourceBackup(tester);
          await openData(tester, env, size: size, textScale: scale);
          expect(tester.takeException(), isNull, reason: 'main screen');

          // Preview with all areas, the warnings and the replace notice.
          pickFile(env, source.bytes, name: 'sicherung-2026-09-07.json');
          await tapText(tester, 'Sicherung auswählen');
          expect(find.text('Sicherung wiederherstellen?'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'preview');
          // The confirmation is reachable (pinned, or by scrolling).
          await tester.ensureVisible(
            find.text('Ersetzen und wiederherstellen'),
          );
          await tester.pump();
          await tapText(tester, 'Abbrechen');

          // Rejected file with several reasons.
          pickFile(env, Uint8List.fromList('kein json'.codeUnits));
          await tapText(tester, 'Sicherung auswählen');
          expect(find.text('Import nicht möglich'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'rejected');
          await tester.ensureVisible(find.text('Andere Datei wählen'));
          await tester.pump();
          await tapText(tester, 'Schließen');

          // Reset with a near miss (the hint adds a line) and with the word.
          await tapText(tester, 'Zurücksetzen …');
          await tester.enterText(find.byType(TextField), 'löschen');
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'reset near miss');
          await tester.enterText(find.byType(TextField), 'LÖSCHEN');
          await settle(tester);
          await tester.ensureVisible(find.text('Alles löschen'));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'reset');

          // The export notice and the busy export button.
          await tapText(tester, 'Abbrechen');
          await tapText(tester, 'Jetzt exportieren');
          expect(find.text('Sicherung erstellen?'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'export notice');
        });
      }
    }
  });

  group('keyboard and reachability (AT33)', () {
    testWidgets('the reset sheet works above the keyboard at 200 % text', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      const size = Size(360, 640);
      const keyboard = 300.0;
      await openData(
        tester,
        env,
        size: size,
        textScale: 2.0,
        viewInsets: const EdgeInsets.only(bottom: keyboard),
      );

      await tapText(tester, 'Zurücksetzen …');
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await settle(tester);

      final button = find.text('Alles löschen');
      await tester.ensureVisible(button);
      await tester.pump();
      expect(
        tester.getRect(button).bottom,
        lessThanOrEqualTo(size.height - keyboard),
      );

      await tester.tap(button);
      await settle(tester);
      expect(env.listener.calls, 1, reason: 'the reset ran');
    });

    testWidgets('the import confirmation stays reachable on a small screen', (
      tester,
    ) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      const size = Size(320, 480);
      pickFile(env, source.bytes);
      await openData(tester, env, size: size, textScale: 1.0);

      await tapText(tester, 'Sicherung auswählen');
      final confirm = find.text('Ersetzen und wiederherstellen');
      await tester.ensureVisible(confirm);
      await tester.pump();
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(size.height));
      await tester.tap(confirm);
      await settle(tester);

      expect(env.listener.calls, 1);
    });
  });

  group('tap targets, labels and announcements (AT34)', () {
    testWidgets('screen and sheets meet the tap target guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      await openData(tester, env);

      Future<void> check() async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }

      await check();

      pickFile(env, source.bytes);
      await tapText(tester, 'Sicherung auswählen');
      await check();
      await tapText(tester, 'Abbrechen');

      pickFile(env, Uint8List.fromList('kein json'.codeUnits));
      await tapText(tester, 'Sicherung auswählen');
      await check();
      await tapText(tester, 'Schließen');

      await tapText(tester, 'Zurücksetzen …');
      await check();
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await settle(tester);
      await check();
      await tapText(tester, 'Abbrechen');

      await tapText(tester, 'Jetzt exportieren');
      await check();
      handle.dispose();
    });

    testWidgets(
      'sheets are named routes, titles are headings, the field is labelled',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await createDataEnv(tester);
        final source = await makeSourceBackup(tester);
        pickFile(env, source.bytes);
        await openData(tester, env);

        expect(
          tester
              .getSemantics(find.text('Daten exportieren'))
              .flagsCollection
              .isHeader,
          isTrue,
        );

        await tapText(tester, 'Sicherung auswählen');
        expect(
          find.bySemanticsLabel('Sicherung wiederherstellen?'),
          findsWidgets,
        );
        expect(find.bySemanticsLabel('Schließen'), findsWidgets);
        expect(
          find.bySemanticsLabel(RegExp('Datei: sicherung')),
          findsOneWidget,
        );
        await tapText(tester, 'Abbrechen');

        await tapText(tester, 'Zurücksetzen …');
        expect(
          find.bySemanticsLabel(RegExp('Zur Bestätigung „LÖSCHEN“ eingeben')),
          findsWidgets,
        );
        handle.dispose();
      },
    );

    testWidgets('errors are live regions and keep the sheet open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await createDataEnv(tester);
      env.projection.failure = StateError('boom');
      final source = await makeSourceBackup(tester);
      pickFile(env, source.bytes);
      await openData(tester, env);

      await tapText(tester, 'Sicherung auswählen');
      await tapText(tester, 'Ersetzen und wiederherstellen');

      final error = find.bySemanticsLabel(
        RegExp('Das Wiederherstellen ist fehlgeschlagen'),
      );
      expect(error, findsOneWidget);
      expect(tester.getSemantics(error).flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });
  });
}
