import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/value_field_row.dart';

import '../../../support/pump_app.dart';

/// The rows of the onboarding close the keyboard on a tap beside them and let
/// the user move from row to row without the keyboard going away and coming
/// back (BS-112, D-018, AT33).
///
/// A row is a card that focuses its field when it is tapped anywhere. For the
/// keyboard the card counts as part of the field (`TextFieldTapRegion`); without
/// that, a tap on the card of the next row would be a tap outside the field
/// that has the focus: the keyboard would be hidden at the touch and shown
/// again at the lift.
void main() {
  late TextEditingController ageText;
  late TextEditingController heightText;
  late FocusNode ageFocus;
  late FocusNode heightFocus;

  Future<void> pumpRows(WidgetTester tester) async {
    ageText = TextEditingController();
    heightText = TextEditingController();
    ageFocus = FocusNode();
    heightFocus = FocusNode();
    addTearDown(() {
      ageText.dispose();
      heightText.dispose();
      ageFocus.dispose();
      heightFocus.dispose();
    });
    await pumpApp(
      tester,
      Column(
        children: <Widget>[
          ValueFieldRow(
            label: 'Alter',
            semanticLabel: 'Alter in Jahren, optional',
            unit: 'Jahre',
            controller: ageText,
            focusNode: ageFocus,
            keyboardType: TextInputType.number,
            onChanged: (_) {},
          ),
          const SizedBox(height: 12),
          ValueFieldRow(
            label: 'Größe',
            semanticLabel: 'Größe in Zentimetern, optional',
            unit: 'cm',
            controller: heightText,
            focusNode: heightFocus,
            keyboardType: TextInputType.number,
            onChanged: (_) {},
          ),
          const SizedBox(height: 40),
          const Text('Irgendwo daneben'),
        ],
      ),
      wrapInScaffold: true,
    );
  }

  List<String> keyboardCalls(WidgetTester tester) => <String>[
    for (final call in tester.testTextInput.log) call.method,
  ];

  testWidgets(
    'a tap on the card of the next row moves the focus and the keyboard never goes away (BS-112, AT33)',
    (tester) async {
      await pumpRows(tester);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(ageFocus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      // The label of the next row is on its card but beside its field.
      tester.testTextInput.log.clear();
      await tester.tap(find.text('Größe'));
      await tester.pump();

      expect(heightFocus.hasFocus, isTrue);
      expect(ageFocus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        keyboardCalls(tester),
        isNot(contains('TextInput.hide')),
        reason: 'a hide and a show in a row would make the keyboard flicker',
      );
    },
  );

  testWidgets(
    'a tap on the own card keeps the focus and the keyboard (BS-112, AT33)',
    (tester) async {
      await pumpRows(tester);
      await tester.tap(find.byType(TextField).first);
      await tester.pump();

      tester.testTextInput.log.clear();
      await tester.tap(find.text('Alter'));
      await tester.pump();

      expect(ageFocus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(keyboardCalls(tester), isNot(contains('TextInput.hide')));
    },
  );

  testWidgets('a tap beside the rows closes the keyboard (BS-112, AT33)', (
    tester,
  ) async {
    await pumpRows(tester);
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    expect(heightFocus.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Irgendwo daneben'));
    await tester.pump();

    expect(heightFocus.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
