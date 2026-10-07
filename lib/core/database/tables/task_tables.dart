import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/database/tables/table_mixins.dart';

/// To-do tasks. Open means `completed_at_utc` is null.
@DataClassName('TaskRow')
@TableIndex(name: 'tasks_completed_date', columns: {#completedLocalDate})
class Tasks extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get title => text().check(
    const CustomExpression<bool>('length(title) BETWEEN 1 AND 120'),
  )();

  TextColumn get description => text().nullable().check(
    const CustomExpression<bool>(
      'description IS NULL OR length(description) <= 1000',
    ),
  )();

  TextColumn get priority => text()
      .withDefault(const Constant('normal'))
      .check(
        CustomExpression<bool>(
          'priority IN ${SchemaKeys.sqlIn(SchemaKeys.taskPriorities)}',
        ),
      )();

  TextColumn get dueLocalDate =>
      text().map(const LocalDateConverter()).nullable()();

  /// Up to five trimmed, case-insensitively deduplicated tags (JSON array).
  TextColumn get tagsJson => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))
      .check(const CustomExpression<bool>('json_valid(tags_json)'))();

  IntColumn get completedAtUtc =>
      integer().map(const UtcMillisConverter()).nullable()();

  TextColumn get completedLocalDate =>
      text().map(const LocalDateConverter()).nullable()();

  TextColumn get timezoneId => text().nullable()();

  /// Frozen per completion; null while open.
  BoolColumn get completionEligibility => boolean().nullable()();

  /// The optional reminder of the task (schema 2, BS-111): the instant the
  /// notification is due (UTC). The three `reminder_*` columns are all set or
  /// all null; they follow the time model of the facts (UTC instant plus the
  /// local date and zone frozen when the reminder was set) and are independent
  /// of the completion fields. The reminder engine (BS-111) is meant to plan
  /// the notification under the semantic key `task:<id>`; a reminder is not a
  /// row of `reminder_rules`.
  IntColumn get reminderAtUtc =>
      integer().map(const UtcMillisConverter()).nullable()();

  /// Local business date of [reminderAtUtc] in [reminderTimezoneId], frozen
  /// when the reminder was set.
  TextColumn get reminderLocalDate => text()
      .map(const LocalDateConverter())
      .nullable()
      .check(
        const CustomExpression<bool>(
          '(reminder_at_utc IS NULL) = (reminder_local_date IS NULL)',
        ),
      )();

  /// IANA zone in effect when the reminder was set.
  TextColumn get reminderTimezoneId => text().nullable().check(
    const CustomExpression<bool>(
      '(reminder_at_utc IS NULL) = (reminder_timezone_id IS NULL)',
    ),
  )();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK ((completed_at_utc IS NULL) = (completed_local_date IS NULL))',
    'CHECK ((completed_at_utc IS NULL) = (completion_eligibility IS NULL))',
  ];
}

/// Daily yes/no habits (V1: daily frequency only).
@DataClassName('HabitRow')
class Habits extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get title => text().check(
    const CustomExpression<bool>('length(title) BETWEEN 1 AND 80'),
  )();

  TextColumn get startedLocalDate => text().map(const LocalDateConverter())();

  /// First day on which the habit no longer applies (archiving is from
  /// tomorrow on); null while active.
  TextColumn get archivedFromDate =>
      text().map(const LocalDateConverter()).nullable()();

  TextColumn get reminderLocalTime =>
      text().map(const LocalTimeConverter()).nullable()();

  /// Presentation icon; the accent colour is derived from the design tokens.
  TextColumn get iconKey => text()
      .withDefault(const Constant('book'))
      .check(
        CustomExpression<bool>(
          'icon_key IN ${SchemaKeys.sqlIn(SchemaKeys.habitIcons)}',
        ),
      )();

  @override
  Set<Column> get primaryKey => {id};
}

/// One check per habit and day; undo reactivates the same row.
@DataClassName('HabitCheckRow')
@TableIndex(name: 'habit_checks_date', columns: {#localDate})
class HabitChecks extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get habitId => text().references(Habits, #id)();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  IntColumn get checkedAtUtc => integer().map(const UtcMillisConverter())();

  TextColumn get timezoneId => text()();

  /// Frozen when this check was made.
  BoolColumn get eligibility => boolean()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {habitId, localDate},
  ];
}
