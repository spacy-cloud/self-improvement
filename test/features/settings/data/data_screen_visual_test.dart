import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/pump_app.dart';
import 'data_test_support.dart';

/// Renders the screen and its sheets to PNG files below `build/screens/data/`
/// for the visual comparison with the Figma frames (the folder is ignored by
/// git). The test only fails when rendering throws.
void main() {
  Future<void> shot(WidgetTester tester, String name) =>
      savePng(tester, 'build/screens/data/$name.png');

  for (final spec in <(String, double, double, double)>[
    ('393', 393, 852, 1.0),
    ('320_x2', 320, 640, 2.0),
  ]) {
    testWidgets('renders main screen and sheets at ${spec.$1}', (tester) async {
      final env = await createDataEnv(tester);
      final source = await makeSourceBackup(tester);
      final size = Size(spec.$2, spec.$3);
      await openData(tester, env, size: size, textScale: spec.$4);
      await shot(tester, 'main_${spec.$1}');
      expect(tester.takeException(), isNull);

      pickFile(env, source.bytes, name: 'sicherung-2026-09-07.json');
      await tapText(tester, 'Sicherung auswählen');
      await shot(tester, 'preview_${spec.$1}');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Abbrechen');

      pickFile(
        env,
        Uint8List.fromList('kein json'.codeUnits),
        name: 'fotos.zip',
      );
      await tapText(tester, 'Sicherung auswählen');
      await shot(tester, 'invalid_${spec.$1}');
      expect(tester.takeException(), isNull);
      await tapText(tester, 'Schließen');

      await tapText(tester, 'Zurücksetzen …');
      await shot(tester, 'reset_${spec.$1}');
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'LÖSCHEN');
      await settle(tester);
      await shot(tester, 'reset_typed_${spec.$1}');
      expect(tester.takeException(), isNull);
    });
  }
}
