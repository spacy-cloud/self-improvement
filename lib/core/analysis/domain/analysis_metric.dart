import 'package:self_improvement/core/modules/module_id.dart';

/// The metrics of the analysis. Each one is a card (and a chart series where
/// the ticket asks for one).
enum AnalysisMetric {
  /// Complete days and active days of the daily goals (cross module).
  dailyGoals,

  /// Manual steps (module `body`).
  steps,

  /// Water (module `nutrition`).
  water,

  /// Weight (module `body`).
  weight,

  /// Workout entries and minutes (module `focus`).
  workouts,

  /// Completed focus time (module `focus`).
  focus,

  /// Completed tasks (module `tasks`).
  tasks,

  /// Habit-days (module `tasks`).
  habits,

  /// Meals and known calories (module `nutrition`).
  meals,

  /// The Monday-to-Sunday workout week card (module `focus`); separate from
  /// the period cards.
  workoutWeek;

  /// The module that has to be active for this metric, or `null` for the
  /// cross-module daily goals card.
  ModuleId? get module => switch (this) {
    AnalysisMetric.dailyGoals => null,
    AnalysisMetric.steps || AnalysisMetric.weight => ModuleId.body,
    AnalysisMetric.water || AnalysisMetric.meals => ModuleId.nutrition,
    AnalysisMetric.workouts ||
    AnalysisMetric.focus ||
    AnalysisMetric.workoutWeek => ModuleId.focus,
    AnalysisMetric.tasks || AnalysisMetric.habits => ModuleId.tasks,
  };

  /// The modules that have analysis metrics (body, nutrition, focus, tasks).
  /// Gamification has none: with only that module on there is nothing to
  /// analyse.
  static final Set<ModuleId> analysedModules = Set.unmodifiable(<ModuleId>{
    for (final metric in values) ?metric.module,
  });

  /// German title of the card.
  String get title => switch (this) {
    AnalysisMetric.dailyGoals => 'Tagesziele',
    AnalysisMetric.steps => 'Schritte',
    AnalysisMetric.water => 'Wasser',
    AnalysisMetric.weight => 'Gewicht',
    AnalysisMetric.workouts => 'Workouts',
    AnalysisMetric.focus => 'Fokuszeit',
    AnalysisMetric.tasks => 'Aufgaben',
    AnalysisMetric.habits => 'Gewohnheiten',
    AnalysisMetric.meals => 'Mahlzeiten',
    AnalysisMetric.workoutWeek => 'Workouts diese Woche',
  };
}

/// A line of text with its spoken variant (units spelled out, no slashes).
final class AnalysisLine {
  const AnalysisLine(this.text, {String? spoken}) : spoken = spoken ?? text;

  /// The visible text.
  final String text;

  /// The text for screen readers.
  final String spoken;

  @override
  bool operator ==(Object other) =>
      other is AnalysisLine && other.text == text && other.spoken == spoken;

  @override
  int get hashCode => Object.hash(text, spoken);

  @override
  String toString() => text;
}
