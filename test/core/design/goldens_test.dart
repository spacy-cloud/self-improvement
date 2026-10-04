@Tags(<String>['golden'])
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/component_gallery.dart';
import 'support/design_test_harness.dart';

/// Compares golden images with a tiny tolerance (0.4 % of the pixels) so that
/// anti-aliasing differences between machines do not break the build, while a
/// real change in a component still fails.
///
/// Update with: `flutter test --update-goldens --tags golden`.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  static const double tolerance = 0.004;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void _noop() {}
void _noopBool(bool value) {}
void _noopInt(int value) {}

/// Compact sample for the large text golden: header, a stacked metric grid,
/// chips, the primary action and the navigation.
class _LargeTextSample extends StatelessWidget {
  const _LargeTextSample();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AppHeader.subpage(title: 'Gewicht eintragen'),
        SizedBox(height: 8),
        AdaptiveGrid(
          children: <Widget>[
            MetricCard(
              title: 'Schritte',
              value: '7.450',
              target: '/ 10.000',
              subtitle: '75 % erreicht',
              icon: Icons.directions_walk_rounded,
              accent: AppAccent.steps,
              progress: 0.75,
              progressVariant: AppProgressVariant.steps,
              onTap: _noop,
            ),
            MetricCard(
              title: 'Workout',
              value: 'Upper Body',
              subtitle: 'Brust, Schulter, Rücken',
              icon: Icons.fitness_center_rounded,
              accent: AppAccent.workout,
              onTap: _noop,
              quickAction: MetricCardAction(
                label: 'Training eintragen',
                icon: Icons.add_rounded,
                onPressed: _noop,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            AppChoiceChip(
              label: 'Kraft',
              selected: true,
              onSelected: _noopBool,
            ),
            AppChoiceChip(
              label: 'Cardio',
              selected: false,
              onSelected: _noopBool,
            ),
          ],
        ),
        SizedBox(height: 16),
        QuantityStepper(
          valueText: '71,5',
          unit: 'kg',
          onIncrease: _noop,
          onDecrease: _noop,
          expand: true,
        ),
        SizedBox(height: 16),
        PrimaryButton(label: 'Eintrag speichern', onPressed: _noop),
        SizedBox(height: 24),
        AppBottomNavBar(
          selectedIndex: 0,
          onSelected: _noopInt,
          onPlusPressed: _noop,
        ),
      ],
    );
  }
}

void main() {
  late GoldenFileComparator previousComparator;

  setUpAll(() async {
    await loadInterFont();
    previousComparator = goldenFileComparator;
    final local = goldenFileComparator as LocalFileComparator;
    goldenFileComparator = _TolerantComparator(
      local.basedir.resolve('goldens_test.dart'),
    );
  });

  tearDownAll(() {
    goldenFileComparator = previousComparator;
  });

  /// Pumps [sample] once with a tall view to measure it, then again with a view
  /// of exactly that height so that the golden has no blank area.
  Future<void> pumpExact(
    WidgetTester tester,
    Widget sample, {
    required AppThemeVariant variant,
    required double width,
    double textScale = 1,
  }) async {
    await pumpDesign(
      tester,
      sample,
      variant: variant,
      width: width,
      height: 12000,
      textScale: textScale,
    );
    final content = tester.getSize(find.byType(SingleChildScrollView).first);
    final height = content.height;
    await pumpDesign(
      tester,
      sample,
      variant: variant,
      width: width,
      height: height,
      textScale: textScale,
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final variant in allVariants) {
    testWidgets('component gallery in ${variant.name} at 393 px', (
      tester,
    ) async {
      await pumpExact(
        tester,
        const ComponentGallery(),
        variant: variant,
        width: 393,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/gallery_${variant.name}.png'),
      );
    });
  }

  testWidgets('large text (200 %) on 320 px in Light', (tester) async {
    await pumpExact(
      tester,
      const _LargeTextSample(),
      variant: AppThemeVariant.light,
      width: 320,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/large_text_light.png'),
    );
  });
}
