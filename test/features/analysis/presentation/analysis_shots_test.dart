import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_screen.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_screen.dart';

import '../../../support/pump_app.dart';
import '../analysis_test_support.dart';

void main() {
  for (final (name, size, scale) in <(String, Size, double)>[
    ('393_full', const Size(393, 3600), 1.0),
    ('360_full', const Size(360, 3900), 1.0),
    ('320_full', const Size(320, 4300), 1.0),
    ('320_x2', const Size(320, 9000), 2.0),
  ]) {
    testWidgets('shot: $name', (tester) async {
      final container = analysisContainer();
      addTearDown(container.dispose);
      await pumpApp(
        tester,
        const AnalysisScreen(),
        container: container,
        size: size,
        textScale: scale,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await savePng(tester, 'build/shots/analysis_$name.png', pixelRatio: 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shot: dark', (tester) async {
    final container = analysisContainer();
    addTearDown(container.dispose);
    await pumpApp(
      tester,
      const AnalysisScreen(),
      container: container,
      size: const Size(393, 1500),
      theme: AppThemeVariant.dark,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await savePng(tester, 'build/shots/analysis_dark.png', pixelRatio: 1);
  });

  testWidgets('shot: table 393', (tester) async {
    final container = analysisContainer();
    addTearDown(container.dispose);
    await pumpApp(
      tester,
      const AnalysisTableScreen(),
      container: container,
      size: const Size(393, 1400),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await savePng(tester, 'build/shots/table_393.png', pixelRatio: 1);
  });

  testWidgets('shot: table 320 x2', (tester) async {
    final container = analysisContainer();
    addTearDown(container.dispose);
    await pumpApp(
      tester,
      const AnalysisTableScreen(),
      container: container,
      size: const Size(320, 4200),
      textScale: 2.0,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await savePng(tester, 'build/shots/table_320_x2.png', pixelRatio: 1);
  });

  testWidgets('shot: states', (tester) async {
    for (final (name, modules, days, usage)
        in <(String, Set<ModuleId>, List<AnalysisDay>?, bool)>[
          ('nomodules', <ModuleId>{}, null, false),
          ('empty', ModuleId.values.toSet(), const <AnalysisDay>[], false),
          ('newuser', ModuleId.values.toSet(), null, true),
        ]) {
      final container = analysisContainer(
        modules: modules,
        days: days,
        usageStart: usage ? d2026(10, 1) : null,
      );
      addTearDown(container.dispose);
      await pumpApp(
        tester,
        const AnalysisScreen(),
        container: container,
        size: Size(393, usage ? 2000 : 852),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await savePng(tester, 'build/shots/state_$name.png', pixelRatio: 1);
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final length in <AnalysisPeriodLength>[
    AnalysisPeriodLength.days30,
    AnalysisPeriodLength.days90,
  ]) {
    testWidgets('shot: ${length.days} days', (tester) async {
      final container = analysisContainer(days: syntheticDays(today: refToday));
      addTearDown(container.dispose);
      container.read(analysisPeriodProvider.notifier).select(length);
      await pumpApp(
        tester,
        const AnalysisScreen(),
        container: container,
        size: const Size(393, 3800),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await savePng(
        tester,
        'build/shots/analysis_${length.days}.png',
        pixelRatio: 1,
      );
    });
  }
}
