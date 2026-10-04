/// The fixed XP rules (`ruleVersion` 1). All values are constants of the app,
/// never read from a widget or from user input.
///
/// Per local day an activity earns points only up to its limit, and only when
/// its record qualifies. Meals, opening the app and losing weight earn 0 and
/// therefore have no rule at all.
abstract final class XpRules {
  /// Stored with every award; a rule change would introduce a new version.
  static const int ruleVersion = 1;

  /// Water: points per qualifying entry.
  static const int waterPoints = 5;

  /// Water: smallest amount of an entry that qualifies, in ml.
  static const int waterMinAmountMl = 100;

  /// Water: awarded entries per day (at most 4 x 5 = 20 XP).
  static const int waterMaxAwardsPerDay = 4;

  /// Weight: once per day, when at least one eligible entry exists.
  static const int weightPoints = 10;

  /// Steps: once per day, when the frozen daily threshold was reached.
  static const int stepsPoints = 10;

  /// Task: points per currently completed task of the day.
  static const int taskPoints = 10;

  /// Task: awarded tasks per day (at most 5 x 10 = 50 XP).
  static const int taskMaxAwardsPerDay = 5;

  /// Focus: points per qualifying completed session.
  static const int focusPoints = 10;

  /// Focus: shortest qualifying session, in seconds.
  static const int focusMinSeconds = 300;

  /// Focus: awarded sessions per day (at most 4 x 10 = 40 XP).
  static const int focusMaxAwardsPerDay = 4;

  /// Workout: once per day, when at least one eligible entry exists.
  static const int workoutPoints = 15;

  /// Habit: points per valid habit check.
  static const int habitPoints = 5;

  /// Habit: awarded checks per day (at most 5 x 5 = 25 XP).
  static const int habitMaxAwardsPerDay = 5;
}
