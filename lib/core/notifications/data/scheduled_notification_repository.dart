import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';

/// The projection of what was handed to the operating system
/// (`scheduled_notifications`).
///
/// The table is technical state, not business data: it is neither exported
/// nor imported, and it is only written by the reminder service. Its integer
/// primary key is `AUTOINCREMENT`, so an id is never handed out twice, not
/// even after its row was deleted: the operating system can therefore never
/// confuse two different reminders. Ids are plain database counters; they are
/// never derived from hash codes.
///
/// Rows are deleted when a notification is cancelled. The schema's
/// `cancelled` state is reserved and not used by the engine: a cancelled
/// notification is simply gone from the projection.
class ScheduledNotificationRepository {
  ScheduledNotificationRepository(this._database);

  final AppDatabase _database;

  /// All rows, soonest first (then by id), including rows of unknown kind so
  /// that the service can clean them up.
  Future<List<ScheduledReminder>> all() async {
    final rows = await _ordered().get();
    return rows.map(mapRow).toList();
  }

  /// Streams the rows whenever the projection changes.
  Stream<List<ScheduledReminder>> watchAll() =>
      _ordered().watch().map((rows) => rows.map(mapRow).toList());

  /// Inserts a row for [planned] and returns its new id.
  Future<int> insert(PlannedNotification planned) {
    return _database
        .into(_database.scheduledNotifications)
        .insert(
          ScheduledNotificationsCompanion.insert(
            semanticKey: planned.semanticKey,
            fireAtUtc: planned.fireAtUtc,
            route: planned.route,
            sourceRuleId: Value(planned.sourceRuleId),
          ),
        );
  }

  /// Moves the existing row [notificationId] to the time and route of
  /// [planned]; the id and the semantic key stay.
  Future<void> update(int notificationId, PlannedNotification planned) async {
    await (_database.update(
      _database.scheduledNotifications,
    )..where((r) => r.notificationId.equals(notificationId))).write(
      ScheduledNotificationsCompanion(
        fireAtUtc: Value(planned.fireAtUtc),
        route: Value(planned.route),
        sourceRuleId: Value(planned.sourceRuleId),
      ),
    );
  }

  Future<void> delete(int notificationId) async {
    await (_database.delete(
      _database.scheduledNotifications,
    )..where((r) => r.notificationId.equals(notificationId))).go();
  }

  Future<void> deleteAll() async {
    await _database.delete(_database.scheduledNotifications).go();
  }

  SimpleSelectStatement<$ScheduledNotificationsTable, ScheduledNotificationRow>
  _ordered() => _database.select(_database.scheduledNotifications)
    ..orderBy([
      (r) => OrderingTerm.asc(r.fireAtUtc),
      (r) => OrderingTerm.asc(r.notificationId),
    ]);

  /// Maps a database row to the domain model.
  static ScheduledReminder mapRow(ScheduledNotificationRow row) =>
      ScheduledReminder(
        notificationId: row.notificationId,
        semanticKey: row.semanticKey,
        fireAtUtc: row.fireAtUtc,
        route: row.route,
        sourceRuleId: row.sourceRuleId,
      );
}
