import 'package:flutter/widgets.dart';
import 'package:self_improvement/core/analysis/domain/analysis_metric.dart';
import 'package:self_improvement/core/design/design.dart';

/// Icon and accent of a metric card. Decorative: the title carries the
/// meaning, the colour never does.
class MetricVisual {
  const MetricVisual(this.icon, this.accent);

  final AppIcon icon;
  final AppAccent accent;
}

/// The visual of [metric] (Figma node 4033:2: one tinted icon tile per card).
MetricVisual metricVisual(AnalysisMetric metric) => switch (metric) {
  AnalysisMetric.dailyGoals => const MetricVisual(
    AppIcon.check,
    AppAccent.primary,
  ),
  AnalysisMetric.steps => const MetricVisual(AppIcon.steps, AppAccent.steps),
  AnalysisMetric.water => const MetricVisual(AppIcon.water, AppAccent.water),
  AnalysisMetric.weight => const MetricVisual(AppIcon.weight, AppAccent.weight),
  AnalysisMetric.workouts || AnalysisMetric.workoutWeek => const MetricVisual(
    AppIcon.workout,
    AppAccent.workout,
  ),
  AnalysisMetric.focus => const MetricVisual(AppIcon.focus, AppAccent.focus),
  AnalysisMetric.tasks => const MetricVisual(AppIcon.task, AppAccent.primary),
  AnalysisMetric.habits => const MetricVisual(AppIcon.habit, AppAccent.habits),
  AnalysisMetric.meals => const MetricVisual(AppIcon.meal, AppAccent.nutrition),
};

/// The order of the period cards in the grid (Figma: steps, water, workouts,
/// focus, tasks, habits, weight, meals). The daily goals card is the hero and
/// the workout week card sits below the grid.
const List<AnalysisMetric> analysisGridOrder = <AnalysisMetric>[
  AnalysisMetric.steps,
  AnalysisMetric.water,
  AnalysisMetric.workouts,
  AnalysisMetric.focus,
  AnalysisMetric.tasks,
  AnalysisMetric.habits,
  AnalysisMetric.weight,
  AnalysisMetric.meals,
];

/// The direction glyph of a change text: the sign of the visible text decides
/// (`+` up, true minus down, otherwise unchanged), so arrow and text can never
/// disagree, also for a change that rounds to zero in the shown precision.
String changeArrow(String changeText) {
  if (changeText.startsWith('+')) {
    return '↑';
  }
  if (changeText.startsWith('−')) {
    return '↓';
  }
  return '→';
}

/// The effective text scale (also for non-linear font scaling).
double textScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

/// Whether large text asks for the stacked layout (the threshold of the design
/// system: above 130 %).
bool useStackedLayout(BuildContext context) =>
    textScaleOf(context) > AppSizes.stackTextScale;
