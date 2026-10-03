/// The optional muscle groups of a workout (`workout_entries.muscle_groups`).
///
/// This enum is the single mapping table from the persisted key to the German
/// label (names as in the approved design: Brust, Schultern, Rücken, Bizeps,
/// Trizeps, Beine, Core, Ganzkörper). The declaration order is the canonical
/// order used for display and storage.
enum MuscleGroup {
  chest('chest', 'Brust'),
  shoulders('shoulders', 'Schultern'),
  back('back', 'Rücken'),
  biceps('biceps', 'Bizeps'),
  triceps('triceps', 'Trizeps'),
  legs('legs', 'Beine'),
  core('core', 'Core'),
  fullBody('full_body', 'Ganzkörper');

  const MuscleGroup(this.key, this.label);

  /// Stable persisted identifier.
  final String key;

  /// German display name.
  final String label;

  /// The group for a persisted [key], or `null` when unknown.
  static MuscleGroup? tryParse(String key) {
    for (final group in values) {
      if (group.key == key) {
        return group;
      }
    }
    return null;
  }

  /// The groups of persisted [keys] in canonical order; duplicates and unknown
  /// keys are dropped.
  static List<MuscleGroup> fromKeys(Iterable<String> keys) =>
      normalize([for (final key in keys) ?tryParse(key)]);

  /// [groups] without duplicates, in canonical order. Pure, so the same
  /// selection always has the same representation (storage, comparison).
  static List<MuscleGroup> normalize(Iterable<MuscleGroup> groups) {
    final selected = groups.toSet();
    return List.unmodifiable([
      for (final group in values)
        if (selected.contains(group)) group,
    ]);
  }
}
