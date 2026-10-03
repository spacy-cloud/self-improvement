import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';
import 'package:self_improvement/core/database/schema_keys.dart';

/// Derived XP awards (a projection of facts; never the only truth).
@DataClassName('XpAwardRow')
@TableIndex(name: 'xp_awards_date', columns: {#localDate})
class XpAwards extends Table {
  /// e.g. `water:<entryId>`, `weight:<date>`, `habit:<habitId>:<date>`.
  TextColumn get awardKey => text()();

  TextColumn get localDate => text().map(const LocalDateConverter())();

  TextColumn get sourceKind => text().check(
    CustomExpression<bool>(
      'source_kind IN ${SchemaKeys.sqlIn(SchemaKeys.xpSources)}',
    ),
  )();

  TextColumn get sourceId => text().nullable()();

  IntColumn get points =>
      integer().check(const CustomExpression<bool>('points >= 0'))();

  IntColumn get ruleVersion => integer()();

  @override
  Set<Column> get primaryKey => {awardKey};
}

/// Idempotency receipts: one row per committed command.
@DataClassName('CommandReceiptRow')
class CommandReceipts extends Table {
  TextColumn get commandId => text()();

  TextColumn get commandType => text()();

  TextColumn get resultEntityId => text().nullable()();

  IntColumn get committedAtUtc => integer().map(const UtcMillisConverter())();

  @override
  Set<Column> get primaryKey => {commandId};
}

/// User-configured reminder rules (water slots etc.).
@DataClassName('ReminderRuleRow')
class ReminderRules extends Table {
  TextColumn get id => text()();

  TextColumn get moduleId => text().check(
    CustomExpression<bool>(
      'module_id IN ${SchemaKeys.sqlIn(SchemaKeys.modules)}',
    ),
  )();

  TextColumn get kind => text().check(
    CustomExpression<bool>(
      'kind IN ${SchemaKeys.sqlIn(SchemaKeys.reminderKinds)}',
    ),
  )();

  TextColumn get localTime =>
      text().map(const LocalTimeConverter()).nullable()();

  BoolColumn get enabled => boolean()();

  /// Known in-app route opened from the notification.
  TextColumn get route => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Technical projection of planned OS notifications (not exported/imported).
@DataClassName('ScheduledNotificationRow')
class ScheduledNotifications extends Table {
  /// Persistent positive integer id handed to the OS.
  IntColumn get notificationId => integer().autoIncrement()();

  TextColumn get semanticKey => text().unique()();

  IntColumn get fireAtUtc => integer().map(const UtcMillisConverter())();

  TextColumn get route => text()();

  TextColumn get sourceRuleId => text().nullable().references(
    ReminderRules,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get state => text()
      .withDefault(const Constant('scheduled'))
      .check(
        CustomExpression<bool>(
          'state IN ${SchemaKeys.sqlIn(SchemaKeys.notificationStates)}',
        ),
      )();
}
