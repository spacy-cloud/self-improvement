import 'package:self_improvement/shared/local_date.dart';

/// Everything the analysis needs to know about ONE local calendar day.
///
/// The data layer fills it from the stored facts (active records only, frozen
/// business dates) and the day status of the goal engine; the pure functions
/// of the analysis never touch a database. A day without any record is simply
/// `AnalysisDay(date: day)`: the defaults mean "nothing recorded".
///
/// The distinction between "recorded 0" and "not recorded" lives in
/// [stepsRecorded] (`null` is not recorded, `0` is a recorded zero) and in
/// [waterEntries] / [weightGrams] / [mealEntries] (counts and `null`).
final class AnalysisDay {
  const AnalysisDay({
    required this.date,
    this.stepsRecorded,
    this.waterMl = 0,
    this.waterEntries = 0,
    this.weightGrams,
    this.workoutEntries = 0,
    this.workoutMinutes = 0,
    this.focusCompletedSeconds = 0,
    this.focusCompletedSessions = 0,
    this.tasksCompleted = 0,
    this.mealEntries = 0,
    this.mealsWithKcal = 0,
    this.knownKcal = 0,
    this.applicableGoals = 0,
    this.fulfilledGoals = 0,
    this.applicableHabits = 0,
    this.fulfilledHabits = 0,
  });

  final LocalDate date;

  /// The manual step total of the day: `null` when no step record exists, a
  /// recorded 0 is a value.
  final int? stepsRecorded;

  /// Sum of the active water entries in ml (0 without entries).
  final int waterMl;

  /// Number of active water entries; a day counts as recorded with at least
  /// one.
  final int waterEntries;

  /// The LAST measurement of the day (by measurement time), in grams; `null`
  /// without a measurement.
  final int? weightGrams;

  /// Number of active workout entries.
  final int workoutEntries;

  /// Sum of the workout minutes (workouts are not focus time).
  final int workoutMinutes;

  /// Sum of the seconds of completed focus sessions that were completed on
  /// this day (aborted and discarded sessions excluded).
  final int focusCompletedSeconds;

  /// Number of completed focus sessions completed on this day.
  final int focusCompletedSessions;

  /// Number of tasks whose current completion date is this day.
  final int tasksCompleted;

  /// Number of active meals.
  final int mealEntries;

  /// Number of meals with a kcal value (a deliberate 0 counts).
  final int mealsWithKcal;

  /// Sum of the KNOWN kcal values (0 when no meal has one: check
  /// [mealsWithKcal] before presenting it as a value).
  final int knownKcal;

  /// Number of goals that applied on this day (daily goals and habits; the
  /// weekly workout goal is no daily goal). 0 for days without a snapshot.
  final int applicableGoals;

  /// Number of applicable goals that were fulfilled.
  final int fulfilledGoals;

  /// Number of habits that applied (a snapshot item `habit:<id>` that is
  /// applicable: the habit applied and the tasks module was on). Habits that
  /// were deleted never count.
  final int applicableHabits;

  /// Number of applicable habits that have a check on this day.
  final int fulfilledHabits;

  /// Whether a step record exists (also a recorded 0).
  bool get stepsAreRecorded => stepsRecorded != null;

  /// Whether at least one water entry exists.
  bool get waterIsRecorded => waterEntries > 0;

  /// Whether the day has at least one applicable goal.
  bool get hasApplicableGoals => applicableGoals >= 1;

  /// A complete day: at least one applicable goal and all of them fulfilled.
  /// Identical to `DayStatus.isComplete` of the goal engine.
  bool get isCompleteDay =>
      applicableGoals >= 1 && fulfilledGoals == applicableGoals;

  /// An active day (streak): at least one applicable goal fulfilled.
  /// Identical to `DayStatus.isActive`. Not the same as [isCompleteDay].
  bool get isActiveDay => fulfilledGoals >= 1;

  @override
  bool operator ==(Object other) =>
      other is AnalysisDay &&
      other.date == date &&
      other.stepsRecorded == stepsRecorded &&
      other.waterMl == waterMl &&
      other.waterEntries == waterEntries &&
      other.weightGrams == weightGrams &&
      other.workoutEntries == workoutEntries &&
      other.workoutMinutes == workoutMinutes &&
      other.focusCompletedSeconds == focusCompletedSeconds &&
      other.focusCompletedSessions == focusCompletedSessions &&
      other.tasksCompleted == tasksCompleted &&
      other.mealEntries == mealEntries &&
      other.mealsWithKcal == mealsWithKcal &&
      other.knownKcal == knownKcal &&
      other.applicableGoals == applicableGoals &&
      other.fulfilledGoals == fulfilledGoals &&
      other.applicableHabits == applicableHabits &&
      other.fulfilledHabits == fulfilledHabits;

  @override
  int get hashCode => Object.hash(
    date,
    stepsRecorded,
    waterMl,
    waterEntries,
    weightGrams,
    workoutEntries,
    workoutMinutes,
    focusCompletedSeconds,
    focusCompletedSessions,
    tasksCompleted,
    mealEntries,
    mealsWithKcal,
    knownKcal,
    applicableGoals,
    fulfilledGoals,
    applicableHabits,
    fulfilledHabits,
  );

  @override
  String toString() =>
      'AnalysisDay($date, steps: $stepsRecorded, water: $waterMl/$waterEntries, '
      'weight: $weightGrams, workouts: $workoutEntries/$workoutMinutes, '
      'focus: $focusCompletedSessions/$focusCompletedSeconds, '
      'tasks: $tasksCompleted, meals: $mealEntries/$mealsWithKcal/$knownKcal, '
      'goals: $fulfilledGoals/$applicableGoals, '
      'habits: $fulfilledHabits/$applicableHabits)';
}
