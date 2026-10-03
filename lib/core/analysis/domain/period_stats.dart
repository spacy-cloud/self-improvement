/// The aggregates of one period, computed from the per-day inputs.
///
/// Every definition here is the one of the ticket (BS-71) and specification
/// section 12:
///
/// - **Steps**: recorded days are days with an active step record (a recorded
///   0 counts). Average = total / recorded days; no recorded day: no average
///   (`null`), never a fake 0.
/// - **Water**: recorded days are days with at least one active entry; the
///   daily total is the sum of its entries; average = sum of the daily totals
///   / recorded days; none: `null`.
/// - **Weight**: the daily value is the LAST measurement of a day. The change
///   is the last daily value minus the first daily value of the period and
///   needs at least two measured days. Gaps are never filled with zero.
/// - **Workouts**: number of active entries and total minutes (workouts are
///   not focus time).
/// - **Focus**: completed sessions only, by completion day.
/// - **Tasks**: tasks whose current completion date lies in the period.
/// - **Habits**: applicable habit-days (a habit that applied on a day and the
///   tasks module was on) and fulfilled habit-days (a check exists).
/// - **Meals**: meal count, sum of the KNOWN kcal and a completeness status;
///   without any known kcal there is no kcal sum (`null`), not 0.
/// - **Daily goals**: complete days (at least one applicable goal and all of
///   them fulfilled) out of the days with at least one applicable goal, kept
///   strictly apart from active days (at least one goal fulfilled).
library;

import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_math.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Step aggregates of a period.
final class StepsStats {
  const StepsStats({
    required this.periodDays,
    required this.recordedDays,
    required this.totalSteps,
  });

  /// Length N of the period in days.
  final int periodDays;

  /// Days with an active step record (a recorded 0 counts).
  final int recordedDays;

  /// Sum of the recorded daily values.
  final int totalSteps;

  /// Whether at least one day is recorded.
  bool get hasData => recordedDays > 0;

  /// Days without a step record.
  int get unrecordedDays => periodDays - recordedDays;

  /// Total / recorded days as an exact fraction; `null` without a recorded
  /// day.
  Fraction? get averageFraction =>
      hasData ? Fraction(totalSteps, recordedDays) : null;

  /// Average steps per RECORDED day; `null` without a recorded day.
  double? get average => averageFraction?.value;

  /// [average] rounded to whole steps (half up).
  int? get averageRounded => averageFraction?.rounded;
}

/// Water aggregates of a period.
final class WaterStats {
  const WaterStats({
    required this.periodDays,
    required this.recordedDays,
    required this.totalMl,
  });

  final int periodDays;

  /// Days with at least one active water entry.
  final int recordedDays;

  /// Sum of all daily totals in ml.
  final int totalMl;

  bool get hasData => recordedDays > 0;

  int get unrecordedDays => periodDays - recordedDays;

  /// Sum of the daily totals / recorded days; `null` without a recorded day.
  Fraction? get averageFraction =>
      hasData ? Fraction(totalMl, recordedDays) : null;

  /// Average ml per RECORDED day; `null` without a recorded day.
  double? get average => averageFraction?.value;

  /// [average] rounded to whole ml (half up).
  int? get averageRounded => averageFraction?.rounded;
}

/// A daily weight value: the last measurement of [date].
final class WeightDayValue {
  const WeightDayValue({required this.date, required this.grams});

  final LocalDate date;
  final int grams;
}

/// Weight aggregates of a period.
final class WeightStats {
  const WeightStats({
    required this.periodDays,
    required this.measuredDays,
    this.first,
    this.last,
  });

  final int periodDays;

  /// Days with at least one measurement.
  final int measuredDays;

  /// The daily value of the first measured day of the period.
  final WeightDayValue? first;

  /// The daily value of the last measured day of the period.
  final WeightDayValue? last;

  bool get hasData => measuredDays > 0;

  /// Last daily value minus first daily value in grams; `null` with fewer
  /// than two measured days ("Noch kein Vergleich").
  int? get changeGrams {
    final firstValue = first;
    final lastValue = last;
    if (measuredDays < 2 || firstValue == null || lastValue == null) {
      return null;
    }
    return lastValue.grams - firstValue.grams;
  }
}

/// Workout aggregates of a period.
final class WorkoutStats {
  const WorkoutStats({
    required this.entries,
    required this.minutes,
    required this.activeDays,
  });

  /// Number of active workout entries.
  final int entries;

  /// Total minutes of all entries.
  final int minutes;

  /// Days with at least one entry.
  final int activeDays;

  /// A period without any entry has no workout data.
  bool get hasData => entries > 0;
}

/// Focus aggregates of a period (completed sessions only).
final class FocusStats {
  const FocusStats({
    required this.completedSeconds,
    required this.completedSessions,
    required this.activeDays,
  });

  final int completedSeconds;
  final int completedSessions;

  /// Days with at least one completed session.
  final int activeDays;

  /// Whole completed minutes (the same flooring as the focus goal).
  int get completedMinutes => completedSeconds ~/ 60;

  bool get hasData => completedSessions > 0;
}

/// Task aggregates of a period.
final class TaskStats {
  const TaskStats({required this.completed, required this.activeDays});

  /// Tasks whose current completion date lies in the period.
  final int completed;

  /// Days with at least one completion.
  final int activeDays;

  bool get hasData => completed > 0;
}

/// Habit aggregates of a period.
///
/// A "habit-day" is one habit on one day it applied (3 habits over 7 days are
/// at most 21 habit-days).
final class HabitStats {
  const HabitStats({
    required this.applicableHabitDays,
    required this.fulfilledHabitDays,
  });

  final int applicableHabitDays;
  final int fulfilledHabitDays;

  bool get hasData => applicableHabitDays > 0;

  /// Fulfilled / applicable in percent as an exact fraction
  /// (`Fraction(100 * fulfilled, applicable)`); `null` without applicable
  /// habit-days.
  Fraction? get ratioPercentFraction =>
      hasData ? Fraction(100 * fulfilledHabitDays, applicableHabitDays) : null;

  /// The ratio in percent (0 to 100); `null` without applicable habit-days.
  double? get ratioPercent => ratioPercentFraction?.value;

  /// The ratio rounded to a whole percent.
  int? get ratioPercentRounded => ratioPercentFraction?.rounded;
}

/// How complete the calorie information of the meals is.
enum MealCompleteness {
  /// No meal in the period.
  none,

  /// Every meal has a kcal value.
  complete,

  /// At least one meal has no kcal value: "Kalorien unvollständig".
  incomplete,
}

/// Meal aggregates of a period.
final class MealStats {
  const MealStats({
    required this.meals,
    required this.mealsWithKcal,
    required this.knownKcal,
    required this.daysWithMeals,
  });

  final int meals;

  /// Meals that have a kcal value (a deliberate 0 counts).
  final int mealsWithKcal;

  /// Sum of the known kcal values; see [kcalTotal] for the presentable value.
  final int knownKcal;

  /// Days with at least one meal.
  final int daysWithMeals;

  int get mealsWithoutKcal => meals - mealsWithKcal;

  bool get hasData => meals > 0;

  MealCompleteness get completeness {
    if (meals == 0) {
      return MealCompleteness.none;
    }
    return mealsWithoutKcal == 0
        ? MealCompleteness.complete
        : MealCompleteness.incomplete;
  }

  /// The sum of the known kcal, or `null` when no meal has a kcal value
  /// (never an invented 0). A deliberate 0 kcal meal gives a real 0.
  int? get kcalTotal => mealsWithKcal > 0 ? knownKcal : null;
}

/// Daily goal aggregates of a period.
final class GoalStats {
  const GoalStats({
    required this.periodDays,
    required this.daysWithGoals,
    required this.completeDays,
    required this.activeDays,
  });

  final int periodDays;

  /// Days with at least one applicable goal (the denominator).
  final int daysWithGoals;

  /// Complete days: at least one applicable goal and all fulfilled.
  final int completeDays;

  /// Active days: at least one applicable goal fulfilled. Kept apart from
  /// [completeDays]; every complete day is also active, not vice versa.
  final int activeDays;

  bool get hasData => daysWithGoals > 0;

  /// Complete days / days with goals in percent as an exact fraction.
  Fraction? get completeRatioFraction =>
      hasData ? Fraction(100 * completeDays, daysWithGoals) : null;

  /// Active days / days with goals in percent as an exact fraction.
  Fraction? get activeRatioFraction =>
      hasData ? Fraction(100 * activeDays, daysWithGoals) : null;
}

/// All aggregates of one period `[start, end]`.
final class PeriodStats {
  const PeriodStats({
    required this.start,
    required this.end,
    required this.steps,
    required this.water,
    required this.weight,
    required this.workouts,
    required this.focus,
    required this.tasks,
    required this.habits,
    required this.meals,
    required this.goals,
  });

  final LocalDate start;
  final LocalDate end;
  final StepsStats steps;
  final WaterStats water;
  final WeightStats weight;
  final WorkoutStats workouts;
  final FocusStats focus;
  final TaskStats tasks;
  final HabitStats habits;
  final MealStats meals;
  final GoalStats goals;

  /// Length of the period in days.
  int get periodDays => start.daysUntil(end) + 1;
}

/// Aggregates the [days] that lie in `[start, end]` (days outside are
/// ignored; each date must appear at most once).
///
/// One pass over the days, no database access.
PeriodStats computePeriodStats({
  required Iterable<AnalysisDay> days,
  required LocalDate start,
  required LocalDate end,
}) {
  assert(!end.isBefore(start), 'A period has at least one day');
  final periodDays = start.daysUntil(end) + 1;

  var stepsRecordedDays = 0;
  var stepsTotal = 0;
  var waterRecordedDays = 0;
  var waterTotal = 0;
  var weightMeasuredDays = 0;
  WeightDayValue? firstWeight;
  WeightDayValue? lastWeight;
  var workoutEntries = 0;
  var workoutMinutes = 0;
  var workoutDays = 0;
  var focusSeconds = 0;
  var focusSessions = 0;
  var focusDays = 0;
  var tasksCompleted = 0;
  var taskDays = 0;
  var habitsApplicable = 0;
  var habitsFulfilled = 0;
  var meals = 0;
  var mealsWithKcal = 0;
  var knownKcal = 0;
  var mealDays = 0;
  var daysWithGoals = 0;
  var completeDays = 0;
  var activeDays = 0;

  for (final day in days) {
    if (day.date.isBefore(start) || day.date.isAfter(end)) {
      continue;
    }
    final steps = day.stepsRecorded;
    if (steps != null) {
      stepsRecordedDays++;
      stepsTotal += steps;
    }
    if (day.waterIsRecorded) {
      waterRecordedDays++;
      waterTotal += day.waterMl;
    }
    final weight = day.weightGrams;
    if (weight != null) {
      weightMeasuredDays++;
      final value = WeightDayValue(date: day.date, grams: weight);
      if (firstWeight == null || day.date.isBefore(firstWeight.date)) {
        firstWeight = value;
      }
      if (lastWeight == null || day.date.isAfter(lastWeight.date)) {
        lastWeight = value;
      }
    }
    if (day.workoutEntries > 0) {
      workoutDays++;
      workoutEntries += day.workoutEntries;
      workoutMinutes += day.workoutMinutes;
    }
    if (day.focusCompletedSessions > 0) {
      focusDays++;
      focusSessions += day.focusCompletedSessions;
      focusSeconds += day.focusCompletedSeconds;
    }
    if (day.tasksCompleted > 0) {
      taskDays++;
      tasksCompleted += day.tasksCompleted;
    }
    habitsApplicable += day.applicableHabits;
    habitsFulfilled += day.fulfilledHabits;
    if (day.mealEntries > 0) {
      mealDays++;
      meals += day.mealEntries;
      mealsWithKcal += day.mealsWithKcal;
      knownKcal += day.knownKcal;
    }
    if (day.hasApplicableGoals) {
      daysWithGoals++;
      if (day.isCompleteDay) {
        completeDays++;
      }
      if (day.isActiveDay) {
        activeDays++;
      }
    }
  }

  return PeriodStats(
    start: start,
    end: end,
    steps: StepsStats(
      periodDays: periodDays,
      recordedDays: stepsRecordedDays,
      totalSteps: stepsTotal,
    ),
    water: WaterStats(
      periodDays: periodDays,
      recordedDays: waterRecordedDays,
      totalMl: waterTotal,
    ),
    weight: WeightStats(
      periodDays: periodDays,
      measuredDays: weightMeasuredDays,
      first: firstWeight,
      last: lastWeight,
    ),
    workouts: WorkoutStats(
      entries: workoutEntries,
      minutes: workoutMinutes,
      activeDays: workoutDays,
    ),
    focus: FocusStats(
      completedSeconds: focusSeconds,
      completedSessions: focusSessions,
      activeDays: focusDays,
    ),
    tasks: TaskStats(completed: tasksCompleted, activeDays: taskDays),
    habits: HabitStats(
      applicableHabitDays: habitsApplicable,
      fulfilledHabitDays: habitsFulfilled,
    ),
    meals: MealStats(
      meals: meals,
      mealsWithKcal: mealsWithKcal,
      knownKcal: knownKcal,
      daysWithMeals: mealDays,
    ),
    goals: GoalStats(
      periodDays: periodDays,
      daysWithGoals: daysWithGoals,
      completeDays: completeDays,
      activeDays: activeDays,
    ),
  );
}
