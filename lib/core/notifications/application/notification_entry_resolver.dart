import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_status_repository.dart';
import 'package:self_improvement/core/notifications/domain/notification_route_resolver.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Resolves a notification payload (cold start or tap while running) to the
/// in-app route to open, using the real module statuses and records.
///
/// It loads the facts and delegates the decision to the pure
/// [NotificationRouteResolver.resolve]; see there for the cold start contract
/// the app shell follows. It never throws for a bad payload: anything unknown
/// opens the dashboard.
class NotificationEntryResolver {
  NotificationEntryResolver({
    required this._database,
    required this._modules,
    required this._clock,
  });

  final AppDatabase _database;
  final ModuleStatusRepository _modules;
  final ClockService _clock;

  /// The safe route for [payload]:
  ///
  /// - unknown or malformed payload, or the module is switched off: `/`
  /// - the habit does not exist, was deleted or is archived: `/habits`
  /// - the task does not exist or was deleted: the task list
  ///   `/habits?tab=tasks` (a completed task still exists: its form opens)
  /// - otherwise the route of the payload.
  Future<String> resolve(String? payload) async {
    final target = NotificationRouteResolver.parse(payload);
    final statuses = await _modules.statuses();
    final entity = target?.entity;
    final exists = entity == null || await _entityExists(entity);
    return NotificationRouteResolver.resolve(
      payload,
      isModuleEnabled: (module) => statuses[module] ?? true,
      entityExists: (_) => exists,
    );
  }

  Future<bool> _entityExists(NotificationEntity entity) async {
    switch (entity.kind) {
      case NotificationEntityKind.habit:
        final row =
            await (_database.select(_database.habits)..where(
                  (h) => h.id.equals(entity.id) & h.deletedAtUtc.isNull(),
                ))
                .getSingleOrNull();
        if (row == null) {
          return false;
        }
        // Archiving works from tomorrow: on the archive day itself and
        // before, the habit still exists for the user.
        final archivedFrom = row.archivedFromDate;
        return archivedFrom == null || _clock.today() < archivedFrom;
      case NotificationEntityKind.task:
        final row =
            await (_database.select(_database.tasks)..where(
                  (t) => t.id.equals(entity.id) & t.deletedAtUtc.isNull(),
                ))
                .getSingleOrNull();
        return row != null;
    }
  }
}
