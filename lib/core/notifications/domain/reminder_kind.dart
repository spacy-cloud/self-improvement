import 'package:self_improvement/core/modules/module_id.dart';

/// The three kinds of reminders of V1 (task due dates are not reminded).
///
/// The [key] values are the persisted `reminder_rules.kind` keys and the
/// prefix of the semantic key of a planned notification.
enum ReminderKind {
  /// Optional water slots (10, 12, 14, 16, 18 o'clock). Owned by `nutrition`.
  water('water', ModuleId.nutrition, 2),

  /// Daily reminder at the individual time of a habit. Owned by `tasks`.
  habit('habit', ModuleId.tasks, 1),

  /// One notification at the end of a running focus session. Owned by
  /// `focus`.
  focusEnd('focus_end', ModuleId.focus, 0);

  const ReminderKind(this.key, this.module, this.sortRank);

  /// Stable persisted key (`water`, `habit`, `focus_end`).
  final String key;

  /// The module whose deactivation removes this kind of reminders.
  final ModuleId module;

  /// Tie breaker for notifications due at the very same instant: lower first.
  /// The focus end always comes first.
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
