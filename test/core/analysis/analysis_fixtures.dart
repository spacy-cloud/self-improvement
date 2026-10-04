import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Non-breaking space between a number and a unit symbol (U+00A0).
const String nb = ' ';

/// The true minus sign (U+2212).
const String minus = '−';

/// Reference "today" of the pure analysis tests: Saturday, 2026-10-03.
final LocalDate refToday = LocalDate(2026, 10, 3);

/// A date in 2026.
LocalDate d2026(int month, int day) => LocalDate(2026, month, day);

/// The period of [length] ending on [refToday].
AnalysisPeriodSpec refPeriod(AnalysisPeriodLength length) =>
    AnalysisPeriodSpec(length: length, today: refToday);

/// The usage start of the reference scenario: long before every period.
final LocalDate refUsageStart = LocalDate(2026, 1, 1);

/// The synthetic reference scenario for a 7 day period ending Saturday
/// 2026-10-03 (current period 2026-09-27 .. 2026-10-03, previous period
/// 2026-09-20 .. 2026-09-26).
///
/// Every expected value in the tests was computed by hand from this table:
///
/// ```text
/// current period                       steps   water      weight  workouts   focus        tasks  meals (n/kcal-n/kcal)  goals  habits
/// Sun 09-27                             8000    -          71800   -          -            -      -                       0/0    0/0
/// Mon 09-28                             0       750 (2)    -       -          1 x 1500 s   2      3/2/1200                6/6    1/1
/// Tue 09-29                             -       2000 (3)   -       1 x 45     -            -      -                       6/2    1/0
/// Wed 09-30                             12000   -          71600   -          1 x 1800 s   1      -                       7/7    2/2
/// Thu 10-01                             -       1500 (3)   -       2 x 90     -            -      2/2/300                 7/3    2/1
/// Fri 10-02                             6000    -          -       -          1 x 600 s    -      -                       4/0    0/0
/// Sat 10-03                             9000    2500 (4)   71500   -          -            3      -                       7/7    2/2
///
/// previous period
/// Sun 09-20                             4000    -          -       -          -            -      -                       6/3    1/0
/// Mon 09-21                             -       2000 (4)   72400   -          -            -      -                       6/6    1/1
/// Tue 09-22                             6000    -          -       1 x 40     -            -      -                       6/6    1/1
/// Wed 09-23                             -       -          -       -          -            4      -                       6/0    1/0
/// Thu 09-24                             -       1000 (2)   -       -          1 x 3000 s   -      2/2/1000                6/4    1/0
/// Fri 09-25                             -       -          -       1 x 50     -            -      -                       6/0    1/0
/// Sat 09-26                             5000    -          71900   -          -            -      -                       6/5    1/0
/// ```
///
/// (goals and habits columns are applicable/fulfilled; "-" is nothing
/// recorded. Mon 09-28 .. Sat 10-03 is the current Monday-to-Sunday week to
/// date, Mon 09-21 .. Sat 09-26 the same weekdays of the previous week.)
///
/// Resulting aggregates (current vs previous):
/// - steps: 5 recorded days (one recorded 0), total 35000, average 7000 vs
///   3 recorded days, total 15000, average 5000 -> +2000, +40 %
/// - water: 4 days, 6750 ml, average 1687.5 ml vs 2 days, 3000 ml, average
///   1500 ml -> +187.5 ml, +12.5 % (13 %)
/// - weight: 3 measured days, 71.8 -> 71.5 kg, change -300 g vs 2 measured
///   days, 72.4 -> 71.9 kg, change -500 g
/// - workouts: 3 entries / 135 min vs 2 entries / 90 min (+50 % / +50 %)
/// - focus: 3 sessions / 3900 s vs 1 session / 3000 s (+30 % / +200 %)
/// - tasks: 6 vs 4 (+50 %)
/// - habits: 6 of 8 habit-days (75 %) vs 2 of 7 (28.57 %) -> +46 points
/// - meals: 5 meals, 4 with kcal, 1500 known kcal (incomplete) vs 2 meals,
///   1000 kcal (complete)
/// - goals: 6 days with goals, 3 complete (50 %), 5 active (83.33 %) vs 7
///   days with goals, 2 complete (28.57 %), 5 active (71.43 %)
List<AnalysisDay> referenceDays() => [
  // ---------------------------------------------------- previous period
  AnalysisDay(
    date: d2026(9, 20),
    stepsRecorded: 4000,
    applicableGoals: 6,
    fulfilledGoals: 3,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  AnalysisDay(
    date: d2026(9, 21),
    waterMl: 2000,
    waterEntries: 4,
    weightGrams: 72400,
    applicableGoals: 6,
    fulfilledGoals: 6,
    applicableHabits: 1,
    fulfilledHabits: 1,
  ),
  AnalysisDay(
    date: d2026(9, 22),
    stepsRecorded: 6000,
    workoutEntries: 1,
    workoutMinutes: 40,
    applicableGoals: 6,
    fulfilledGoals: 6,
    applicableHabits: 1,
    fulfilledHabits: 1,
  ),
  AnalysisDay(
    date: d2026(9, 23),
    tasksCompleted: 4,
    applicableGoals: 6,
    fulfilledGoals: 0,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  AnalysisDay(
    date: d2026(9, 24),
    waterMl: 1000,
    waterEntries: 2,
    focusCompletedSeconds: 3000,
    focusCompletedSessions: 1,
    mealEntries: 2,
    mealsWithKcal: 2,
    knownKcal: 1000,
    applicableGoals: 6,
    fulfilledGoals: 4,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  AnalysisDay(
    date: d2026(9, 25),
    workoutEntries: 1,
    workoutMinutes: 50,
    applicableGoals: 6,
    fulfilledGoals: 0,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  AnalysisDay(
    date: d2026(9, 26),
    stepsRecorded: 5000,
    weightGrams: 71900,
    applicableGoals: 6,
    fulfilledGoals: 5,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  // ----------------------------------------------------- current period
  AnalysisDay(date: d2026(9, 27), stepsRecorded: 8000, weightGrams: 71800),
  AnalysisDay(
    date: d2026(9, 28),
    stepsRecorded: 0,
    waterMl: 750,
    waterEntries: 2,
    focusCompletedSeconds: 1500,
    focusCompletedSessions: 1,
    tasksCompleted: 2,
    mealEntries: 3,
    mealsWithKcal: 2,
    knownKcal: 1200,
    applicableGoals: 6,
    fulfilledGoals: 6,
    applicableHabits: 1,
    fulfilledHabits: 1,
  ),
  AnalysisDay(
    date: d2026(9, 29),
    waterMl: 2000,
    waterEntries: 3,
    workoutEntries: 1,
    workoutMinutes: 45,
    applicableGoals: 6,
    fulfilledGoals: 2,
    applicableHabits: 1,
    fulfilledHabits: 0,
  ),
  AnalysisDay(
    date: d2026(9, 30),
    stepsRecorded: 12000,
    weightGrams: 71600,
    focusCompletedSeconds: 1800,
    focusCompletedSessions: 1,
    tasksCompleted: 1,
    applicableGoals: 7,
    fulfilledGoals: 7,
    applicableHabits: 2,
    fulfilledHabits: 2,
  ),
  AnalysisDay(
    date: d2026(10, 1),
    waterMl: 1500,
    waterEntries: 3,
    workoutEntries: 2,
    workoutMinutes: 90,
    mealEntries: 2,
    mealsWithKcal: 2,
    knownKcal: 300,
    applicableGoals: 7,
    fulfilledGoals: 3,
    applicableHabits: 2,
    fulfilledHabits: 1,
  ),
  AnalysisDay(
    date: d2026(10, 2),
    stepsRecorded: 6000,
    focusCompletedSeconds: 600,
    focusCompletedSessions: 1,
    applicableGoals: 4,
    fulfilledGoals: 0,
  ),
  AnalysisDay(
    date: d2026(10, 3),
    stepsRecorded: 9000,
    waterMl: 2500,
    waterEntries: 4,
    weightGrams: 71500,
    tasksCompleted: 3,
    applicableGoals: 7,
    fulfilledGoals: 7,
    applicableHabits: 2,
    fulfilledHabits: 2,
  ),
];
