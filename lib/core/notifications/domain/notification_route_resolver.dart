import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';

/// Kinds of records a notification can point to.
enum NotificationEntityKind {
  /// A habit (route `/habits/<uuid>`).
  habit,

  /// A task (route `/tasks/<uuid>`, the form "Aufgabe bearbeiten").
  task,
}

/// A record a payload refers to, to be checked for existence by the caller.
@immutable
final class NotificationEntity {
  const NotificationEntity(this.kind, this.id);

  final NotificationEntityKind kind;

  /// The local UUID.
  final String id;

  @override
  bool operator ==(Object other) =>
      other is NotificationEntity && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'NotificationEntity(${kind.name}:$id)';
}

/// A payload that passed the whitelist.
@immutable
final class NotificationTarget {
  const NotificationTarget({required this.route, this.module, this.entity});

  /// The canonical in-app route.
  final String route;

  /// The module that owns the route; `null` for the dashboard.
  final ModuleId? module;

  /// The record the route points to, if any.
  final NotificationEntity? entity;
}

/// Turns a notification payload into a safe in-app route.
///
/// The payload is untrusted input (it comes back from the operating system
/// and could be damaged by an older app version): everything that is not
/// exactly a known route is rejected, and nothing is ever interpreted as a
/// URL, query or scheme.
///
/// ## Cold start contract (for the app shell)
///
/// 1. The shell initializes the reminder platform before the first frame so
///    taps while the app runs are delivered (`tapStream`).
/// 2. After the bootstrap succeeded **and** onboarding is completed, the shell
///    reads `launchPayload()` exactly once. During bootstrap or onboarding the
///    payload is ignored: the user sees the start flow, not a module screen.
/// 3. The shell passes the payload (launch or tap) to
///    `NotificationEntryResolver.resolve`, which reads the module status and
///    the record from the database and calls [resolve], and navigates to the
///    returned route. Taps while the app runs follow the same path.
abstract final class NotificationRouteResolver {
  /// Payloads longer than this are rejected without parsing (the longest valid
  /// payload is `/habits/` plus a 36 character UUID).
  static const int maxPayloadLength = 64;

  static const String _uuid =
      r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$';

  static final RegExp _habitDetail = RegExp(
    '^${RegExp.escape(NotificationRoutes.habitDetailPrefix)}$_uuid',
  );

  static final RegExp _taskEdit = RegExp(
    '^${RegExp.escape(NotificationRoutes.taskEditPrefix)}$_uuid',
  );

  /// Checks [payload] against the whitelist; `null` for anything else (empty,
  /// no leading slash, unknown route, URL schemes, query strings, overlong).
  static NotificationTarget? parse(String? payload) {
    if (payload == null ||
        payload.isEmpty ||
        payload.length > maxPayloadLength) {
      return null;
    }
    switch (payload) {
      case NotificationRoutes.home:
        return const NotificationTarget(route: NotificationRoutes.home);
      case NotificationRoutes.water:
        return const NotificationTarget(
          route: NotificationRoutes.water,
          module: ModuleId.nutrition,
        );
      case NotificationRoutes.habits:
        return const NotificationTarget(
          route: NotificationRoutes.habits,
          module: ModuleId.tasks,
        );
      case NotificationRoutes.tasks:
        return const NotificationTarget(
          route: NotificationRoutes.tasks,
          module: ModuleId.tasks,
        );
      case NotificationRoutes.focusSession:
        return const NotificationTarget(
          route: NotificationRoutes.focusSession,
          module: ModuleId.focus,
        );
    }
    final habit = _habitDetail.firstMatch(payload);
    if (habit != null) {
      return NotificationTarget(
        route: payload,
        module: ModuleId.tasks,
        entity: NotificationEntity(
          NotificationEntityKind.habit,
          habit.group(1)!,
        ),
      );
    }
    final task = _taskEdit.firstMatch(payload);
    if (task != null) {
      return NotificationTarget(
        route: payload,
        module: ModuleId.tasks,
        entity: NotificationEntity(NotificationEntityKind.task, task.group(1)!),
      );
    }
    return null;
  }

  /// The safe route to open for [payload]:
  ///
  /// - unknown or malformed payload: the dashboard `/`
  /// - the owning module is switched off: the dashboard `/`
  /// - the habit does not exist (any more) or is archived: `/habits`
  /// - the task does not exist (any more): the task list `/habits?tab=tasks`
  /// - otherwise the route of the payload.
  ///
  /// [isModuleEnabled] and [entityExists] are plain synchronous lookups; the
  /// caller loads the facts first (see `NotificationEntryResolver`).
  static String resolve(
    String? payload, {
    required bool Function(ModuleId module) isModuleEnabled,
    required bool Function(NotificationEntity entity) entityExists,
  }) {
    final target = parse(payload);
    if (target == null) {
      return NotificationRoutes.home;
    }
    final module = target.module;
    if (module != null && !isModuleEnabled(module)) {
      return NotificationRoutes.home;
    }
    final entity = target.entity;
    if (entity != null && !entityExists(entity)) {
      return switch (entity.kind) {
        NotificationEntityKind.habit => NotificationRoutes.habits,
        NotificationEntityKind.task => NotificationRoutes.tasks,
      };
    }
    return target.route;
  }
}
