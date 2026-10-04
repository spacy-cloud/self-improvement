import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/database/tables/table_mixins.dart';

/// Singleton local profile (id is always `local`).
@DataClassName('ProfileRow')
class Profile extends Table with AuditColumns {
  TextColumn get id => text()
      .withDefault(const Constant('local'))
      .check(const CustomExpression<bool>("id = 'local'"))();

  /// Optional display name, 1-40 characters after trimming.
  TextColumn get displayName => text().nullable().check(
    const CustomExpression<bool>(
      'display_name IS NULL OR length(display_name) BETWEEN 1 AND 40',
    ),
  )();

  /// First local business day of this installation (no data counts before).
  TextColumn get startedLocalDate => text().map(const LocalDateConverter())();

  IntColumn get heightCm => integer().nullable().check(
    const CustomExpression<bool>(
      'height_cm IS NULL OR height_cm BETWEEN 100 AND 250',
    ),
  )();

  IntColumn get ageYears => integer().nullable().check(
    const CustomExpression<bool>(
      'age_years IS NULL OR age_years BETWEEN 18 AND 120',
    ),
  )();

  IntColumn get startWeightGrams => integer().nullable().check(
    const CustomExpression<bool>(
      'start_weight_grams IS NULL OR '
      '(start_weight_grams BETWEEN 20000 AND 350000 '
      'AND start_weight_grams % 100 = 0)',
    ),
  )();

  IntColumn get targetWeightGrams => integer().nullable().check(
    const CustomExpression<bool>(
      'target_weight_grams IS NULL OR '
      '(target_weight_grams BETWEEN 20000 AND 350000 '
      'AND target_weight_grams % 100 = 0)',
    ),
  )();

  /// Deduplicated list of known onboarding preference ids (JSON array).
  TextColumn get motivationGoals => text()
      .map(const StringListConverter())
      .withDefault(const Constant('[]'))
      .check(const CustomExpression<bool>('json_valid(motivation_goals)'))();

  BoolColumn get onboardingCompleted =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Singleton application settings (id is always `app`).
@DataClassName('AppSettingsRow')
class AppSettings extends Table with AuditColumns {
  TextColumn get id => text()
      .withDefault(const Constant('app'))
      .check(const CustomExpression<bool>("id = 'app'"))();

  TextColumn get themeMode => text()
      .withDefault(const Constant('system'))
      .check(
        CustomExpression<bool>(
          'theme_mode IN ${SchemaKeys.sqlIn(SchemaKeys.themeModes)}',
        ),
      )();

  BoolColumn get reduceMotion => boolean().withDefault(const Constant(false))();

  BoolColumn get haptics => boolean().withDefault(const Constant(true))();

  /// Desired state. The real OS permission is never read from here.
  BoolColumn get notificationsEnabled =>
      boolean().withDefault(const Constant(false))();

  TextColumn get lastKnownTimezone => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only history of module activation changes.
@DataClassName('ModuleStatusRow')
@TableIndex(
  name: 'module_status_lookup',
  columns: {#moduleId, #localDate, #effectiveAtUtc},
)
class ModuleStatusHistory extends Table {
  TextColumn get id => text()();

  TextColumn get moduleId => text().check(
    CustomExpression<bool>(
      'module_id IN ${SchemaKeys.sqlIn(SchemaKeys.modules)}',
    ),
  )();

  IntColumn get effectiveAtUtc => integer().map(const UtcMillisConverter())();

  /// Local business day of the change.
  TextColumn get localDate => text().map(const LocalDateConverter())();

  BoolColumn get enabled => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Visibility and order of dashboard cards.
@DataClassName('DashboardCardRow')
class DashboardCards extends Table {
  TextColumn get cardId => text().check(
    CustomExpression<bool>(
      'card_id IN ${SchemaKeys.sqlIn(SchemaKeys.dashboardCards)}',
    ),
  )();

  TextColumn get moduleId => text().check(
    CustomExpression<bool>(
      'module_id IN ${SchemaKeys.sqlIn(SchemaKeys.modules)}',
    ),
  )();

  BoolColumn get visible => boolean().withDefault(const Constant(true))();

  IntColumn get sortIndex =>
      integer().check(const CustomExpression<bool>('sort_index >= 0'))();

  @override
  Set<Column> get primaryKey => {cardId};
}

/// Versioned goal values. Changes take effect from a given local date.
@DataClassName('GoalVersionRow')
@TableIndex(
  name: 'goal_versions_type_date',
  columns: {#goalType, #effectiveFromDate},
)
class GoalVersions extends Table {
  TextColumn get id => text()();

  TextColumn get goalType => text().check(
    CustomExpression<bool>(
      'goal_type IN ${SchemaKeys.sqlIn(SchemaKeys.goalTypes)}',
    ),
  )();

  IntColumn get targetInteger => integer().nullable().check(
    const CustomExpression<bool>(
      'target_integer IS NULL OR target_integer > 0',
    ),
  )();

  BoolColumn get enabled => boolean()();

  TextColumn get effectiveFromDate => text().map(const LocalDateConverter())();

  IntColumn get createdAtUtc => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {goalType, effectiveFromDate},
  ];
}

/// Per-day snapshot of which goals applied and their thresholds.
///
/// Whether a goal was fulfilled is never stored: it is derived from facts.
@DataClassName('DailyGoalSnapshotRow')
@TableIndex(name: 'daily_goal_snapshots_date', columns: {#localDate})
class DailyGoalSnapshots extends Table {
  TextColumn get id => text()();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  /// `water`, `steps`, ... or `habit:<habitId>`.
  TextColumn get goalKey => text()();

  TextColumn get moduleId => text().check(
    CustomExpression<bool>(
      'module_id IN ${SchemaKeys.sqlIn(SchemaKeys.modules)}',
    ),
  )();

  IntColumn get targetInteger => integer().nullable()();

  BoolColumn get applicable => boolean()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {localDate, goalKey},
  ];
}
