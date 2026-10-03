/// The optional intensity of a workout (`workout_entries.intensity`).
///
/// Shown as Leicht, Mittel and Hart. No intensity is saved unless the user
/// chooses one.
enum WorkoutIntensity {
  low('low', 'Leicht'),
  moderate('moderate', 'Mittel'),
  high('high', 'Hart');

  const WorkoutIntensity(this.key, this.label);

  /// Stable persisted identifier.
  final String key;

  /// German display name.
  final String label;

  /// The intensity for a persisted [key], or `null` when unknown.
  static WorkoutIntensity? tryParse(String key) {
    for (final intensity in values) {
      if (intensity.key == key) {
        return intensity;
      }
    }
    return null;
  }
}
