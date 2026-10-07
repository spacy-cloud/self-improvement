/// The in-app routes a notification may open, and the only strings that ever
/// appear as notification payload.
///
/// A payload is exactly one of these routes. It is a known route plus, for the
/// habit detail and the task form, one local UUID. It never carries health
/// values or any text the user typed (habit and task titles are user text and
/// therefore never leave the database through a notification).
abstract final class NotificationRoutes {
  /// Dashboard. Also the safe fallback for anything unknown.
  static const String home = '/';

  /// Water overview and entry (module `nutrition`).
  static const String water = '/water';

  /// Habit list (module `tasks`). Fallback for a missing habit.
  static const String habits = '/habits';

  /// The task list, the "Aufgaben" view of the habits tab (module `tasks`).
  /// Fallback for a missing task; a task reminder opens the task itself.
  static const String tasks = '/habits?tab=tasks';

  /// The active focus session (module `focus`).
  static const String focusSession = '/focus/session';

  /// Prefix of the habit detail route, followed by the habit UUID.
  static const String habitDetailPrefix = '/habits/';

  /// Prefix of the route of the task form "Aufgabe bearbeiten", followed by
  /// the task UUID. The form is the only detail view a task has.
  static const String taskEditPrefix = '/tasks/';

  static final RegExp _localId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// Whether [value] has the canonical lowercase UUID shape of a local id.
  static bool isLocalId(String value) => _localId.hasMatch(value);

  /// The detail route of habit [habitId]. An id that is not a canonical UUID
  /// (only possible for damaged data) is never put into a payload; the habit
  /// list is used instead.
  static String habitDetail(String habitId) =>
      isLocalId(habitId) ? '$habitDetailPrefix$habitId' : habits;

  /// The route of the task form of task [taskId]. An id that is not a
  /// canonical UUID (only possible for damaged data) is never put into a
  /// payload; the task list is used instead.
  static String taskEdit(String taskId) =>
      isLocalId(taskId) ? '$taskEditPrefix$taskId' : tasks;
}
