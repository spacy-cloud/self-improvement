import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/field_reader.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/shared/local_date.dart';

/// One weight measurement (integer grams, steps of 100 g).
@immutable
final class WeightEntryDto {
  const WeightEntryDto({
    required this.id,
    required this.weightGrams,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.beforeToilet,
    required this.afterDrinking,
    required this.afterEating,
    required this.gamificationEligible,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.note,
  });

  factory WeightEntryDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.weightEntries, json, read);

  factory WeightEntryDto.fromRow(WeightEntryRow row) => WeightEntryDto(
    id: row.id,
    weightGrams: row.weightGrams,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    beforeToilet: row.beforeToilet,
    afterDrinking: row.afterDrinking,
    afterEating: row.afterEating,
    note: row.note,
    gamificationEligible: row.gamificationEligible,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static WeightEntryDto read(FieldReader r) => WeightEntryDto(
    id: r.uuid('id', 'ID'),
    weightGrams: r.integer(
      'weight_grams',
      'Gewicht',
      min: 20000,
      max: 350000,
      multipleOf: 100,
    ),
    occurredAtUtc: r.instant('occurred_at_utc', 'Messzeitpunkt'),
    localDate: r.date('local_date', 'Datum'),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    beforeToilet: r.boolean('before_toilet', 'Bedingung vor dem Toilettengang'),
    afterDrinking: r.boolean('after_drinking', 'Bedingung nach dem Trinken'),
    afterEating: r.boolean('after_eating', 'Bedingung nach dem Essen'),
    note: r.optionalText('note', 'Notiz', max: 500),
    gamificationEligible: r.boolean(
      'gamification_eligible',
      'Gamification-Berechtigung',
    ),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final int weightGrams;
  final DateTime occurredAtUtc;
  final LocalDate localDate;
  final String timezoneId;
  final bool beforeToilet;
  final bool afterDrinking;
  final bool afterEating;
  final String? note;
  final bool gamificationEligible;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'weight_grams': weightGrams,
    'occurred_at_utc': BackupValues.formatInstant(occurredAtUtc),
    'local_date': localDate.toIso(),
    'timezone_id': timezoneId,
    'before_toilet': beforeToilet,
    'after_drinking': afterDrinking,
    'after_eating': afterEating,
    'note': note,
    'gamification_eligible': gamificationEligible,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  WeightEntriesCompanion toCompanion() => WeightEntriesCompanion.insert(
    id: id,
    weightGrams: weightGrams,
    occurredAtUtc: occurredAtUtc,
    localDate: localDate,
    timezoneId: timezoneId,
    beforeToilet: Value(beforeToilet),
    afterDrinking: Value(afterDrinking),
    afterEating: Value(afterEating),
    note: Value(note),
    gamificationEligible: gamificationEligible,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// The step total of one day, typed in by hand or taken from the health app
/// ([source], schema 2).
@immutable
final class StepDayDto {
  const StepDayDto({
    required this.id,
    required this.localDate,
    required this.steps,
    required this.timezoneId,
    required this.source,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.reachedGoalEligible,
    this.xpGoalTargetSteps,
  });

  factory StepDayDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.stepDays, json, read);

  factory StepDayDto.fromRow(StepDayRow row) => StepDayDto(
    id: row.id,
    localDate: row.localDate,
    steps: row.steps,
    timezoneId: row.timezoneId,
    reachedGoalEligible: row.reachedGoalEligible,
    xpGoalTargetSteps: row.xpGoalTargetSteps,
    source: row.source,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static StepDayDto read(FieldReader r) {
    final dto = StepDayDto(
      id: r.uuid('id', 'ID'),
      localDate: r.date('local_date', 'Datum'),
      steps: r.integer('steps', 'Schritte', min: 0, max: 100000),
      timezoneId: r.timezone('timezone_id', 'Zeitzone'),
      reachedGoalEligible: r.optionalBoolean(
        'reached_goal_eligible',
        'Berechtigung bei Zielerreichung',
      ),
      xpGoalTargetSteps: r.optionalInteger(
        'xp_goal_target_steps',
        'Erreichter Schwellenwert',
        min: 1,
      ),
      source: r.choice('source', 'Quelle', SchemaKeys.stepSources),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
    // Both are set together when the day's goal is reached the first time.
    if (!r.hasProblems &&
        (dto.reachedGoalEligible == null) != (dto.xpGoalTargetSteps == null)) {
      r.fail(
        'xp_goal_target_steps',
        'Zielerreichung unvollständig '
            '(Berechtigung und Schwellenwert gehören zusammen)',
      );
    }
    return dto;
  }

  final String id;
  final LocalDate localDate;
  final int steps;
  final String timezoneId;
  final bool? reachedGoalEligible;
  final int? xpGoalTargetSteps;

  /// `manual` or `health` (see `SchemaKeys.stepSources`).
  final String source;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'local_date': localDate.toIso(),
    'steps': steps,
    'timezone_id': timezoneId,
    'reached_goal_eligible': reachedGoalEligible,
    'xp_goal_target_steps': xpGoalTargetSteps,
    'source': source,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  StepDaysCompanion toCompanion() => StepDaysCompanion.insert(
    id: id,
    localDate: localDate,
    steps: steps,
    timezoneId: timezoneId,
    reachedGoalEligible: Value(reachedGoalEligible),
    xpGoalTargetSteps: Value(xpGoalTargetSteps),
    source: Value(source),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// One drink in millilitres.
@immutable
final class WaterEntryDto {
  const WaterEntryDto({
    required this.id,
    required this.amountMl,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.gamificationEligible,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.note,
  });

  factory WaterEntryDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.waterEntries, json, read);

  factory WaterEntryDto.fromRow(WaterEntryRow row) => WaterEntryDto(
    id: row.id,
    amountMl: row.amountMl,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    note: row.note,
    gamificationEligible: row.gamificationEligible,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static WaterEntryDto read(FieldReader r) => WaterEntryDto(
    id: r.uuid('id', 'ID'),
    amountMl: r.integer('amount_ml', 'Menge', min: 50, max: 2000),
    occurredAtUtc: r.instant('occurred_at_utc', 'Zeitpunkt'),
    localDate: r.date('local_date', 'Datum'),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    note: r.optionalText('note', 'Notiz', max: 500),
    gamificationEligible: r.boolean(
      'gamification_eligible',
      'Gamification-Berechtigung',
    ),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final int amountMl;
  final DateTime occurredAtUtc;
  final LocalDate localDate;
  final String timezoneId;
  final String? note;
  final bool gamificationEligible;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'amount_ml': amountMl,
    'occurred_at_utc': BackupValues.formatInstant(occurredAtUtc),
    'local_date': localDate.toIso(),
    'timezone_id': timezoneId,
    'note': note,
    'gamification_eligible': gamificationEligible,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  WaterEntriesCompanion toCompanion() => WaterEntriesCompanion.insert(
    id: id,
    amountMl: amountMl,
    occurredAtUtc: occurredAtUtc,
    localDate: localDate,
    timezoneId: timezoneId,
    note: Value(note),
    gamificationEligible: gamificationEligible,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// One meal with optional calories (no goals, no XP).
@immutable
final class MealEntryDto {
  const MealEntryDto({
    required this.id,
    required this.name,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.kcal,
    this.note,
  });

  factory MealEntryDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.mealEntries, json, read);

  factory MealEntryDto.fromRow(MealEntryRow row) => MealEntryDto(
    id: row.id,
    name: row.name,
    kcal: row.kcal,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    note: row.note,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static MealEntryDto read(FieldReader r) => MealEntryDto(
    id: r.uuid('id', 'ID'),
    name: r.text('name', 'Name', min: 1, max: 80),
    kcal: r.optionalInteger('kcal', 'Kalorien', min: 0, max: 5000),
    occurredAtUtc: r.instant('occurred_at_utc', 'Zeitpunkt'),
    localDate: r.date('local_date', 'Datum'),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    note: r.optionalText('note', 'Notiz', max: 500),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final String name;
  final int? kcal;
  final DateTime occurredAtUtc;
  final LocalDate localDate;
  final String timezoneId;
  final String? note;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kcal': kcal,
    'occurred_at_utc': BackupValues.formatInstant(occurredAtUtc),
    'local_date': localDate.toIso(),
    'timezone_id': timezoneId,
    'note': note,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  MealEntriesCompanion toCompanion() => MealEntriesCompanion.insert(
    id: id,
    name: name,
    kcal: Value(kcal),
    occurredAtUtc: occurredAtUtc,
    localDate: localDate,
    timezoneId: timezoneId,
    note: Value(note),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}
