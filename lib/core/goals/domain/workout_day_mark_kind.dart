/// What a day without a workout can be marked as (BS-99).
///
/// Persisted as `workout_day_marks.kind` (stable keys, also in the backup). A
/// mark fulfils the optional daily goal "Workout heute" like a workout does, but
/// it earns no XP: it keeps the streak, nothing more.
enum WorkoutDayMarkKind {
  /// A deliberate rest day.
  rest('rest'),

  /// A workout that was planned and skipped.
  skipped('skipped');

  const WorkoutDayMarkKind(this.key);

  /// Stable persisted identifier (`SchemaKeys.workoutDayMarkKinds`).
  final String key;

  /// The kind for a persisted [key], or `null` when unknown.
  static WorkoutDayMarkKind? tryParse(String key) {
    for (final kind in values) {
      if (kind.key == key) {
        return kind;
      }
    }
    return null;
  }
}
