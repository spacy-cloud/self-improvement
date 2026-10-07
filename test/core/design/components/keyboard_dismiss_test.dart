import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

/// The keyboard of a form closes on a tap outside the field and on a drag of
/// the page (BS-112, D-018, AT33).
///
/// On iOS the number pad has no key that closes it and the system has no Back
/// gesture, so a tester on an iPhone could not get rid of it. Flutter does
/// nothing by default for a touch on a mobile platform; `AppTextField` and the
/// bare number fields pass `dismissKeyboardOnTapOutside`, and the scroll view
/// of `AppScaffold` closes the keyboard on a drag.
///
/// "Android" and "iOS" are what the pumped screen runs as: the theme carries the
/// platform of the variant, so the scroll physics and the gestures of the text
/// fields are those of that platform, in every order of the tests (BS-98, R1-01).
///
/// The host has no real keyboard: `testTextInput.isVisible` is what the app
/// asked the system for (show or hide). That is the evidence these tests give;
/// how the iPhone keyboard behaves is for the device check.
void main() {
  const platforms = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  bool keyboardShown(WidgetTester tester) => tester.testTextInput.isVisible;

  /// The pumped screen runs as the platform of the variant: the platform of its
  /// theme is the one the test asked for, not the one of the first theme built.
  void expectRunsAsVariant(WidgetTester tester) {
    expect(
      Theme.of(tester.element(find.byType(TextField).first)).platform,
      defaultTargetPlatform,
      reason: 'the theme carries the platform of the variant (BS-98, R1-01)',
    );
  }

  /// Whether the field at [index] (in tree order) has the focus.
  bool hasFocus(WidgetTester tester, [int index = 0]) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .elementAt(index)
      .focusNode
      .hasFocus;

  /// A bare number field of the kind the forms draw (a big value without a
  /// box), with the callback of the app.
  Widget bareField({Key? key}) => TextField(
    key: key,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    onTapOutside: dismissKeyboardOnTapOutside,
  );

  group('a tap outside the field', () {
    testWidgets(
      'closes the keyboard of an AppTextField on Android and on iOS (BS-112, AT33)',
      (tester) async {
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[
              AppTextField(label: 'Notiz'),
              SizedBox(height: 40),
              Text('Irgendwo daneben'),
            ],
          ),
        );
        expectRunsAsVariant(tester);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(keyboardShown(tester), isTrue, reason: 'the tap opened it');
        expect(hasFocus(tester), isTrue);

        await tester.tap(find.text('Irgendwo daneben'));
        await tester.pump();

        expect(keyboardShown(tester), isFalse);
        expect(hasFocus(tester), isFalse);
      },
      variant: platforms,
    );

    testWidgets(
      'closes the keyboard of a bare number field the same way (BS-112, AT33)',
      (tester) async {
        await pumpDesign(
          tester,
          Column(
            children: <Widget>[bareField(), const Text('Irgendwo daneben')],
          ),
        );
        expectRunsAsVariant(tester);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(keyboardShown(tester), isTrue);

        await tester.tap(find.text('Irgendwo daneben'));
        await tester.pump();

        expect(keyboardShown(tester), isFalse);
        expect(hasFocus(tester), isFalse);
      },
      variant: platforms,
    );

    testWidgets(
      'for reference: without the callback the framework keeps the keyboard on a touch screen (BS-112)',
      (tester) async {
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[TextField(), Text('Irgendwo daneben')],
          ),
        );
        expectRunsAsVariant(tester);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.tap(find.text('Irgendwo daneben'));
        await tester.pump();

        expect(
          keyboardShown(tester),
          isTrue,
          reason:
              'this is the reason for dismissKeyboardOnTapOutside; if the '
              'framework changes it, the callback may go',
        );
      },
      variant: platforms,
    );

    testWidgets('inside the field keeps the keyboard (BS-112, AT33)', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const Column(children: <Widget>[AppTextField(label: 'Notiz')]),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(keyboardShown(tester), isTrue);
      expect(hasFocus(tester), isTrue);
    });

    testWidgets(
      'leaves the focus to another field: the keyboard is never hidden on the way (BS-112, AT33)',
      (tester) async {
        await pumpDesign(
          tester,
          Column(
            children: <Widget>[
              const AppTextField(label: 'Titel'),
              const SizedBox(height: 16),
              bareField(key: const Key('number')),
            ],
          ),
        );
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        expect(hasFocus(tester, 0), isTrue);

        tester.testTextInput.log.clear();
        await tester.tap(find.byKey(const Key('number')));
        await tester.pump();

        expect(hasFocus(tester, 1), isTrue);
        expect(hasFocus(tester, 0), isFalse);
        expect(keyboardShown(tester), isTrue);
        expect(
          <String>[for (final call in tester.testTextInput.log) call.method],
          isNot(contains('TextInput.hide')),
          reason: 'a hide and a show in a row would make the keyboard flicker',
        );

        tester.testTextInput.log.clear();
        await tester.tap(find.byType(TextField).first);
        await tester.pump();
        expect(hasFocus(tester, 0), isTrue);
        expect(<String>[
          for (final call in tester.testTextInput.log) call.method,
        ], isNot(contains('TextInput.hide')));
      },
    );

    testWidgets(
      'a tap on a button works the first time, although the keyboard goes away under the finger and the button moves (BS-112, AT33)',
      (tester) async {
        var pressed = 0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        await pumpDesign(
          tester,
          AppScaffold.subpage(
            title: 'Formular',
            primaryAction: PrimaryButton(
              label: 'Speichern',
              onPressed: () => pressed++,
            ),
            body: const AppTextField(label: 'Notiz'),
          ),
          wrapScaffold: false,
          height: 640,
        );
        await tester.enterText(find.byType(TextField), 'Text');
        await tester.pump();
        expect(keyboardShown(tester), isTrue);
        final before = tester.getCenter(find.text('Speichern'));

        // The finger goes down on the button: the keyboard is asked to go.
        final finger = await tester.startGesture(before);
        await tester.pump();
        expect(keyboardShown(tester), isFalse);
        expect(pressed, 0, reason: 'a press is not a tap yet');

        // The system takes the keyboard away and the pinned button moves down
        // while the finger is still on it.
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          tester.getCenter(find.text('Speichern')).dy,
          greaterThan(before.dy + 100),
          reason: 'the layout really moved',
        );
        await finger.up();
        await tester.pump();

        expect(pressed, 1, reason: 'one tap, one action');
      },
    );
  });

  group('a drag of the page', () {
    testWidgets('closes the keyboard of a form in AppScaffold (BS-112, AT33)', (
      tester,
    ) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.reset);
      await pumpDesign(
        tester,
        AppScaffold.subpage(
          title: 'Formular',
          body: const Column(
            children: <Widget>[
              AppTextField(label: 'Notiz'),
              SizedBox(height: 1200),
            ],
          ),
        ),
        wrapScaffold: false,
        height: 640,
      );
      expectRunsAsVariant(tester);
      expect(
        tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      await tester.enterText(find.byType(TextField), 'Text');
      await tester.pump();
      expect(keyboardShown(tester), isTrue);
      final top = tester.getTopLeft(find.byType(SingleChildScrollView)).dy;

      // The drag starts on the field itself: a touch that goes down anywhere
      // else would close the keyboard by the tap outside before it moves.
      await tester.drag(find.byType(TextField), const Offset(0, -120));
      await tester.pump();

      expect(keyboardShown(tester), isFalse);
      expect(hasFocus(tester), isFalse);
      expect(
        tester.getTopLeft(find.byType(AppTextField)).dy,
        lessThan(top + 8),
        reason: 'the page scrolled',
      );
    }, variant: platforms);

    testWidgets('does not touch a scroll view while no field has the focus', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppScaffold.subpage(
          title: 'Liste',
          body: const Column(
            children: <Widget>[
              AppTextField(label: 'Notiz'),
              SizedBox(height: 1500),
            ],
          ),
        ),
        wrapScaffold: false,
        height: 640,
      );
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -120),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(keyboardShown(tester), isFalse);
    });
  });

  group('the screen reader', () {
    testWidgets(
      'activating the save button with a semantics action works with the keyboard open (BS-112, AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        var pressed = 0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        await pumpDesign(
          tester,
          AppScaffold.subpage(
            title: 'Formular',
            primaryAction: PrimaryButton(
              label: 'Speichern',
              onPressed: () => pressed++,
            ),
            body: const AppTextField(label: 'Notiz'),
          ),
          wrapScaffold: false,
          height: 640,
        );
        await tester.enterText(find.byType(TextField), 'Text');
        await tester.pump();

        // TalkBack and VoiceOver activate a control with a semantics action:
        // no touch goes down, so the tap beside the field never runs.
        tester.semantics.tap(find.semantics.byLabel('Speichern'));
        await tester.pump();

        expect(pressed, 1);
        expect(tester.takeException(), isNull);
        handle.dispose();
      },
    );

    testWidgets(
      'finds the field as before and does not hear it focused after the keyboard closed (BS-112, AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[
              AppTextField(label: 'Notiz', requirementLabel: 'optional'),
              SizedBox(height: 40),
              Text('Irgendwo daneben'),
            ],
          ),
        );
        Tristate focused() => tester
            .getSemantics(find.bySemanticsLabel('Notiz, optional'))
            .flagsCollection
            .isFocused;

        await tester.tap(find.byType(TextField));
        await tester.pump();
        expect(focused(), Tristate.isTrue);

        await tester.tap(find.text('Irgendwo daneben'));
        await tester.pump();

        expect(focused(), Tristate.isFalse);
        expect(find.bySemanticsLabel('Notiz, optional'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      },
    );
  });
}
