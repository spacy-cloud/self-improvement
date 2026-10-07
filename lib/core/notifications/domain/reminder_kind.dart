import 'package:self_improvement/core/modules/module_id.dart';

/// The four kinds of reminders: the three of V1 and, since v0.2.0 (BS-111),
/// the reminder of a single task. A due date alone never reminds; only a
/// reminder time the user set on the task does.
///
/// The [key] values are the prefix of the semantic key of a planned
/// notification. For [water], [habit] and [focusEnd] they are also the
/// persisted `reminder_rules.kind` keys (`SchemaKeys.reminderKinds`); a task
/// reminder is no rule, it is a property of the task
/// (`tasks.reminder_at_utc`), so [task] exists only as a key prefix.
enum ReminderKind {
  /// Optional water slots (10, 12, 14, 16, 18 o'clock). Owned by `nutrition`.
  water('water', ModuleId.nutrition, 3),

  /// Daily reminder at the individual time of a habit. Owned by `tasks`.
  habit('habit', ModuleId.tasks, 2),

  /// One notification at the time the user chose for one task (a single
  /// instant, not recurring). Owned by `tasks`.
  task('task', ModuleId.tasks, 1),

  /// One notification at the end of a running focus session. Owned by
  /// `focus`.
  focusEnd('focus_end', ModuleId.focus, 0);

  const ReminderKind(this.key, this.module, this.sortRank);

  /// Stable key (`water`, `habit`, `task`, `focus_end`).
  final String key;

  /// The module whose deactivation removes this kind of reminders.
  final ModuleId module;

  /// Tie breaker for notifications due at the very same instant: lower first.
  /// The focus end always comes first, then a task (a reminder the user chose
  /// for exactly this moment), then habits, then water.
  final int sortRank;

  /// The kind for a persisted [key], or `null` when unknown.
  static ReminderKind? tryParse(String key) {
    for (final kind in values) {
      if (kind.key == key) {
        return kind;
      }
    }
    return null;
  }
}
