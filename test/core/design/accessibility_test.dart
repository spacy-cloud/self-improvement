import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/component_gallery.dart';
import 'support/design_test_harness.dart';

void main() {
  setUpAll(loadInterFont);

  for (final variant in allVariants) {
    group('gallery in ${variant.name}', () {
      testWidgets('meets the Android tap target guideline (48 x 48)', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpDesign(
          tester,
          const ComponentGallery(),
          variant: variant,
          height: 4800,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('meets the labeled tap target guideline', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDesign(
          tester,
          const ComponentGallery(),
          variant: variant,
          height: 4800,
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('meets the text contrast guideline', (tester) async {
        // The 10 px navigation labels are covered by contrast_test.dart: the
        // guideline samples anti-aliased pixels and reports false failures for
        // text that small.
        final handle = tester.ensureSemantics();
        await pumpDesign(
          tester,
          const ComponentGallery(includeNavigation: false),
          variant: variant,
          height: 4800,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    });
  }

  testWidgets('tap targets at 200 % text on 320 px still meet the guideline', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpDesign(
      tester,
      const ComponentGallery(),
      width: 320,
      height: 12000,
      textScale: 2,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  for (final variant in allVariants) {
    testWidgets('navigation labels at 130 % text in ${variant.name}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpDesign(
        tester,
        const Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomNavBar(
            selectedIndex: 0,
            onSelected: _noopInt,
            onPlusPressed: _noop,
          ),
        ),
        variant: variant,
        textScale: 1.3,
        scrollable: false,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }
}

void _noop() {}
void _noopInt(int index) {}
