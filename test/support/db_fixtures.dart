import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Valid synthetic rows for schema and repository tests.
final DateTime fixtureNow = DateTime.utc(2026, 10, 3, 8);
final LocalDate fixtureDate = LocalDate(2026, 10, 3);
const String fixtureZone = 'Europe/Berlin';

ProfileCompanion profileRow({
  Value<String?> displayName = const Value.absent(),
  Value<int?> heightCm = const Value.absent(),
  Value<int?> ageYears = const Value.absent(),
  Value<int?> startWeightGrams = const Value.absent(),
  Value<int?> targetWeightGrams = const Value.absent(),
  Value<String> id = const Value.absent(),
}) => ProfileCompanion.insert(
  id: id,
  displayName: displayName,
  heightCm: heightCm,
  ageYears: ageYears,
  startWeightGrams: startWeightGrams,
  targetWeightGrams: targetWeightGrams,
  startedLocalDate: fixtureDate,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

WeightEntriesCompanion weightRow({
  String id = 'w1',
  int grams = 71500,
  DateTime? at,
  Value<DateTime?> deletedAt = const Value.absent(),
  Value<String?> note = const Value.absent(),
}) => WeightEntriesCompanion.insert(
  id: id,
  weightGrams: grams,
  occurredAtUtc: at ?? fixtureNow,
  localDate: fixtureDate,
  timezoneId: fixtureZone,
  gamificationEligible: true,
  note: note,
  deletedAtUtc: deletedAt,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

StepDaysCompanion stepRow({
  String id = 's1',
  int steps = 7450,
  LocalDate? date,
  Value<DateTime?> deletedAt = const Value.absent(),
}) => StepDaysCompanion.insert(
  id: id,
  localDate: date ?? fixtureDate,
  steps: steps,
  timezoneId: fixtureZone,
  deletedAtUtc: deletedAt,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

WaterEntriesCompanion waterRow({String id = 'wa1', int ml = 250}) =>
    WaterEntriesCompanion.insert(
      id: id,
      amountMl: ml,
      occurredAtUtc: fixtureNow,
      localDate: fixtureDate,
      timezoneId: fixtureZone,
      gamificationEligible: true,
      createdAtUtc: fixtureNow,
      updatedAtUtc: fixtureNow,
    );

MealEntriesCompanion mealRow({
  String id = 'm1',
  String name = 'Haferflocken',
  Value<int?> kcal = const Value.absent(),
}) => MealEntriesCompanion.insert(
  id: id,
  name: name,
  kcal: kcal,
  occurredAtUtc: fixtureNow,
  localDate: fixtureDate,
  timezoneId: fixtureZone,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

FocusSessionsCompanion focusRow({
  String id = 'f1',
  String status = 'paused',
  int planned = 1500,
  int accumulated = 300,
  Value<DateTime?> segmentStartedAt = const Value.absent(),
  Value<LocalDate?> completedDate = const Value.absent(),
  Value<DateTime?> deletedAt = const Value.absent(),
  String category = 'reading',
}) => FocusSessionsCompanion.insert(
  id: id,
  category: category,
  plannedSeconds: planned,
  accumulatedSeconds: Value(accumulated),
  segmentStartedAtUtc: segmentStartedAt,
  startedAtUtc: fixtureNow,
  completedLocalDate: completedDate,
  timezoneId: fixtureZone,
  status: status,
  deletedAtUtc: deletedAt,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

WorkoutEntriesCompanion workoutRow({
  String id = 'wo1',
  String category = 'strength',
  int minutes = 45,
  Value<String?> intensity = const Value.absent(),
  Value<String?> title = const Value.absent(),
}) => WorkoutEntriesCompanion.insert(
  id: id,
  trainingCategory: category,
  durationMinutes: minutes,
  intensity: intensity,
  title: title,
  occurredAtUtc: fixtureNow,
  localDate: fixtureDate,
  timezoneId: fixtureZone,
  gamificationEligible: true,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

TasksCompanion taskRow({
  String id = 't1',
  String title = 'Steuererklärung',
  Value<String> priority = const Value.absent(),
  Value<DateTime?> completedAt = const Value.absent(),
  Value<LocalDate?> completedDate = const Value.absent(),
  Value<bool?> eligibility = const Value.absent(),
}) => TasksCompanion.insert(
  id: id,
  title: title,
  priority: priority,
  completedAtUtc: completedAt,
  completedLocalDate: completedDate,
  completionEligibility: eligibility,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

HabitsCompanion habitRow({
  String id = 'h1',
  String title = 'Lesen',
  Value<String> iconKey = const Value.absent(),
}) => HabitsCompanion.insert(
  id: id,
  title: title,
  iconKey: iconKey,
  startedLocalDate: fixtureDate,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);

HabitChecksCompanion habitCheckRow({
  String id = 'hc1',
  String habitId = 'h1',
  LocalDate? date,
}) => HabitChecksCompanion.insert(
  id: id,
  habitId: habitId,
  localDate: date ?? fixtureDate,
  checkedAtUtc: fixtureNow,
  timezoneId: fixtureZone,
  eligibility: true,
  createdAtUtc: fixtureNow,
  updatedAtUtc: fixtureNow,
);
