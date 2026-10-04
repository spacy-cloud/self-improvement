/// The predefined focus categories (no custom categories in V1).
///
/// The [key] is the persisted contract (`focus_sessions.category`, backup,
/// import); the German [label] is the only place where the visible names are
/// defined.
enum FocusCategory {
  reading('reading', 'Lesen'),
  learning('learning', 'Lernen'),
  programming('programming', 'Programmieren'),
  meditation('meditation', 'Meditation'),
  other('other', 'Sonstiges');

  const FocusCategory(this.key, this.label);

  /// Stable persisted identifier.
  final String key;

  /// German display name.
  final String label;

  /// The category for a persisted [key], or `null` when unknown.
  static FocusCategory? tryParse(String key) {
    for (final category in values) {
      if (category.key == key) {
        return category;
      }
    }
    return null;
  }

  /// Like [tryParse], but an unknown key is a programming/data error.
  static FocusCategory fromKey(String key) =>
      tryParse(key) ?? (throw ArgumentError.value(key, 'key', 'unknown'));
}
