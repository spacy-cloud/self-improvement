/// The visible workout category (`workout_entries.training_category`).
///
/// It replaces the old visible workout type (upper body, lower body, full
/// body, cardio, other); see the mapping in `workout_entry.dart`. The [key] is
/// the persisted contract (database, backup, import), the German [label] the
/// only definition of the visible names.
enum TrainingCategory {
  strength('strength', 'Kraft'),
  cardio('cardio', 'Cardio'),
  mobility('mobility', 'Mobility'),
  sport('sport', 'Sport');

  const TrainingCategory(this.key, this.label);

  /// Stable persisted identifier.
  final String key;

  /// German display name; it is also the title of an entry without a title.
  final String label;

  /// The category for a persisted [key], or `null` when unknown.
  static TrainingCategory? tryParse(String key) {
    for (final category in values) {
      if (category.key == key) {
        return category;
      }
    }
    return null;
  }

  /// Like [tryParse], but an unknown key is a programming/data error.
  static TrainingCategory fromKey(String key) =>
      tryParse(key) ?? (throw ArgumentError.value(key, 'key', 'unknown'));
}
