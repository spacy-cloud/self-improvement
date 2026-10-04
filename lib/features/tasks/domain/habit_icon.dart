/// The symbols a habit can show. The key is stored as `habits.icon_key`
/// (`SchemaKeys.habitIcons`) and exported in backups; the accent colour is NOT
/// stored, the UI derives it from the design tokens.
enum HabitIcon {
  book('book', 'Buch'),
  moon('moon', 'Mond'),
  drop('drop', 'Tropfen'),
  check('check', 'Haken'),
  flame('flame', 'Flamme'),
  heart('heart', 'Herz');

  const HabitIcon(this.key, this.label);

  /// Stable storage key.
  final String key;

  /// German name for the symbol picker and its semantics ("Symbol: Flamme").
  final String label;

  /// The icon stored under [key], or null for an unknown key (rejected by the
  /// validation, never silently replaced).
  static HabitIcon? tryParse(String key) {
    for (final icon in values) {
      if (icon.key == key) {
        return icon;
      }
    }
    return null;
  }
}

/// The icon of a habit that was not given one.
const HabitIcon defaultHabitIcon = HabitIcon.book;
