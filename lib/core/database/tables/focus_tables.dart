import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/database/tables/table_mixins.dart';

/// Focus countdown sessions, restored from persisted time segments.
@DataClassName('FocusSessionRow')
@TableIndex(
  name: 'focus_sessions_completed_date',
  columns: {#completedLocalDate},
)
@TableIndex.sql('''
  CREATE UNIQUE INDEX focus_sessions_single_open
    ON focus_sessions ((1))
    WHERE status IN ('running','paused','awaiting_confirmation')
      AND deleted_at_utc IS NULL;
''')
class FocusSessions extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get category => text().check(
    CustomExpression<bool>(
      'category IN ${SchemaKeys.sqlIn(SchemaKeys.focusCategories)}',
    ),
  )();

  /// Planned countdown, 5-180 minutes.
  IntColumn get plannedSeconds => integer().check(
    const CustomExpression<bool>('planned_seconds BETWEEN 300 AND 10800'),
  )();

  /// Seconds already accumulated in finished segments (never above plan).
  IntColumn get accumulatedSeconds => integer()
      .withDefault(const Constant(0))
      .check(
        const CustomExpression<bool>(
          'accumulated_seconds >= 0 AND accumulated_seconds <= planned_seconds',
        ),
      )();

  /// Start of the currently running segment; only set while `running`.
  IntColumn get segmentStartedAtUtc =>
      integer().map(const UtcMillisConverter()).nullable()();

  IntColumn get startedAtUtc => integer().map(const UtcMillisConverter())();

  IntColumn get endedAtUtc =>
      integer().map(const UtcMillisConverter()).nullable()();

  /// Business date of the confirmed completion (whole duration counts here).
  TextColumn get completedLocalDate =>
      text().map(const LocalDateConverter()).nullable()();

  TextColumn get timezoneId => text()();

  TextColumn get status => text().check(
    CustomExpression<bool>(
      'status IN ${SchemaKeys.sqlIn(SchemaKeys.focusStatuses)}',
    ),
  )();

  TextColumn get note => text().nullable().check(
    const CustomExpression<bool>('note IS NULL OR length(note) <= 500'),
  )();

  /// Frozen when the session is saved as completed; false before.
  BoolColumn get gamificationEligible =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK ((status = 'running') = (segment_started_at_utc IS NOT NULL))",
    "CHECK ((status = 'completed') = (completed_local_date IS NOT NULL))",
  ];
}

/// Manually logged workouts (no sets/reps, no calorie formula).
@DataClassName('WorkoutEntryRow')
@TableIndex(name: 'workout_entries_local_date', columns: {#localDate})
class WorkoutEntries extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  TextColumn get trainingCategory => text().check(
    CustomExpression<bool>(
      'training_category IN ${SchemaKeys.sqlIn(SchemaKeys.trainingCategories)}',
    ),
  )();

  /// Optional custom title (<= 80); empty means the category name is shown.
  TextColumn get title => text().nullable().check(
    const CustomExpression<bool>(
      'title IS NULL OR length(title) BETWEEN 1 AND 80',
    ),
  )();

  IntColumn get durationMinutes => integer().check(
    const CustomExpression<bool>('duration_minutes BETWEEN 1 AND 600'),
  )();

  /// Deduplicated list of known muscle group keys (JSON array).
  TextColumn get muscleGroups => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))
      .check(const CustomExpression<bool>('json_valid(muscle_groups)'))();

  TextColumn get intensity => text().nullable().check(
    CustomExpression<bool>(
      'intensity IS NULL OR '
      'intensity IN ${SchemaKeys.sqlIn(SchemaKeys.workoutIntensities)}',
    ),
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

/// A day marked as a rest day or as a skipped workout (schema 2, BS-99): the
/// daily workout goal counts such a day as done (without XP) next to a logged
/// workout. At most one active row per local date; changing the kind of a day
/// updates its row, undo works through the audit columns and the soft delete
/// like for every other fact.
@DataClassName('WorkoutDayMarkRow')
@TableIndex.sql('''
  CREATE UNIQUE INDEX workout_day_marks_active_date
    ON workout_day_marks (local_date)
    WHERE deleted_at_utc IS NULL;
''')
class WorkoutDayMarks extends Table with AuditColumns, SoftDeleteColumn {
  TextColumn get id => text()();

  /// The local business day the mark applies to.
  TextColumn get localDate => text().map(const LocalDateConverter())();

  /// One of [SchemaKeys.workoutDayMarkKinds]: `rest` or `skipped`.
  TextColumn get kind => text().check(
    CustomExpression<bool>(
      'kind IN ${SchemaKeys.sqlIn(SchemaKeys.workoutDayMarkKinds)}',
    ),
  )();

  /// IANA zone in effect when the mark was set.
  TextColumn get timezoneId => text()();

  @override
  Set<Column> get primaryKey => {id};
}
