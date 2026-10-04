import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/modules/module_id.dart';

import '../analysis_fixtures.dart';

void main() {
  AnalysisReport report(Set<ModuleId> modules) => buildAnalysisReport(
    period: refPeriod(AnalysisPeriodLength.days7),
    days: referenceDays(),
    usageStart: refUsageStart,
    activeModules: modules,
  );

  test('the analysed modules are exactly those that own a metric', () {
    expect(AnalysisMetric.analysedModules, {
      ModuleId.body,
      ModuleId.nutrition,
      ModuleId.focus,
      ModuleId.tasks,
    });
  });

  test('every module with metrics alone is an analysed module', () {
    for (final module in AnalysisMetric.analysedModules) {
      expect(report({module}).hasAnalysedModule, isTrue, reason: '$module');
    }
  });

  test('no module and gamification alone have nothing to analyse', () {
    expect(report(<ModuleId>{}).hasAnalysedModule, isFalse);
    expect(report(<ModuleId>{}).noModuleActive, isTrue);
    final onlyGamification = report({ModuleId.gamification});
    expect(onlyGamification.hasAnalysedModule, isFalse);
    // Gamification is a module, so "no module active" stays false.
    expect(onlyGamification.noModuleActive, isFalse);
  });

  test('gamification next to a data module changes nothing', () {
    expect(
      report({ModuleId.gamification, ModuleId.body}).hasAnalysedModule,
      isTrue,
    );
  });
}
