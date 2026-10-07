import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/database/tables/table_mixins.dart';

/// Body weight measurements (integer grams, one decimal of a kilogram).
@DataClassName('WeightEntryRow')
@TableIndex(name: 'weight_entries_local_date', columns: {#localDate})
@TableIndex.sql('''
  CREATE UNIQUE INDEX weight_entries_active_time
    ON weight_entries (occurred_at_utc)
    WHERE deleted_at_utc IS NULL;
''')
class WeightEntries extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  IntColumn get weightGrams => integer().check(
    const CustomExpression<bool>(
      'weight_grams BETWEEN 20000 AND 350000 AND weight_grams % 100 = 0',
    ),
  )();

  IntColumn get occurredAtUtc => integer().map(const UtcMillisConverter())();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  TextColumn get timezoneId => text()();

  BoolColumn get beforeToilet => boolean().withDefault(const Constant(false))();

  BoolColumn get afterDrinking =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get afterEating => boolean().withDefault(const Constant(false))();

  TextColumn get note => text().nullable().check(
    const CustomExpression<bool>('note IS NULL OR length(note) <= 500'),
  )();

  /// Frozen at creation: whether gamification was enabled then.
  BoolColumn get gamificationEligible => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Daily step totals, typed in by hand or taken from the health app (one
/// active row per local date).
@DataClassName('StepDayRow')
@TableIndex.sql('''
  CREATE UNIQUE INDEX step_days_active_date
    ON step_days (local_date)
    WHERE deleted_at_utc IS NULL;
''')
class StepDays extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  IntColumn get steps => integer().check(
    const CustomExpression<bool>('steps BETWEEN 0 AND 100000'),
  )();

  TextColumn get timezoneId => text()();

  /// Null until the day's applicable goal was reached for the first time;
  /// then frozen with the gamification state of that moment.
  BoolColumn get reachedGoalEligible => boolean().nullable()();

  /// The threshold that was reached (frozen), null until reached.
  IntColumn get xpGoalTargetSteps => integer().nullable()();

  /// Where the total comes from, one of [SchemaKeys.stepSources] (schema 2,
  /// BS-97). Rows written before schema 2 are `manual`; a value the user
  /// types in always makes the row `manual`.
  TextColumn get source => text()
      .withDefault(const Constant('manual'))
      .check(
        CustomExpression<bool>(
          'source IN ${SchemaKeys.sqlIn(SchemaKeys.stepSources)}',
        ),
      )();

  @override
  Set<Column> get primaryKey => {id};
}
