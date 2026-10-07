/// Prefix of snapshot goal keys that stem from a daily habit.
const String _habitKeyPrefix = 'habit:';

/// Snapshot goal key of a habit: `habit:<habitId>`.
///
/// Snapshot rows of the daily goal types use `GoalType.key` instead (`water`,
/// `steps`, `weight_entry`, `focus_minutes`, `task_completion`,
/// `workout_daily`).
String habitGoalKey(String habitId) => '$_habitKeyPrefix$habitId';

/// Whether [goalKey] is a habit key with a non-empty habit id.
bool isHabitGoalKey(String goalKey) =>
    goalKey.startsWith(_habitKeyPrefix) &&
    goalKey.length > _habitKeyPrefix.length;

/// The habit id inside a habit key, or `null` for any other key.
String? habitIdFromKey(String goalKey) =>
    isHabitGoalKey(goalKey) ? goalKey.substring(_habitKeyPrefix.length) : null;
