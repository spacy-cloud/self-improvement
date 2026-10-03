import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/tables/table_mixins.dart';

/// Individual drinks in millilitres.
@DataClassName('WaterEntryRow')
@TableIndex(name: 'water_entries_local_date', columns: {#localDate})
class WaterEntries extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  IntColumn get amountMl => integer().check(
    const CustomExpression<bool>('amount_ml BETWEEN 50 AND 2000'),
  )();

  IntColumn get occurredAtUtc => integer().map(const UtcMillisConverter())();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  TextColumn get timezoneId => text()();

  TextColumn get note => text().nullable().check(
    const CustomExpression<bool>('note IS NULL OR length(note) <= 500'),
  )();

  BoolColumn get gamificationEligible => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Meals with optional calories (no XP, no goals).
@DataClassName('MealEntryRow')
@TableIndex(name: 'meal_entries_local_date', columns: {#localDate})
class MealEntries extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get name => text().check(
    const CustomExpression<bool>('length(name) BETWEEN 1 AND 80'),
  )();

  /// Null means "not given"; a deliberate 0 is a valid value.
  IntColumn get kcal => integer().nullable().check(
    const CustomExpression<bool>('kcal IS NULL OR kcal BETWEEN 0 AND 5000'),
  )();

  IntColumn get occurredAtUtc => integer().map(const UtcMillisConverter())();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  TextColumn get timezoneId => text()();

  TextColumn get note => text().nullable().check(
    const CustomExpression<bool>('note IS NULL OR length(note) <= 500'),
  )();

  @override
  Set<Column> get primaryKey => {id};
}
