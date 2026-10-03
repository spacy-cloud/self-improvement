/// Persisted enum-like keys of schema version 1.
///
/// These strings are a stable contract: they are stored in SQLite (CHECK
/// constraints), exported in backups and validated on import. Domain enums
/// map to and from these keys; tests assert both sides stay in sync.
abstract final class SchemaKeys {
  static const List<String> modules = [
    'body',
    'nutrition',
    'focus',
    'tasks',
    'gamification',
  ];

  /// Dashboard card ids (stable). An unknown id is invalid.
  static const List<String> dashboardCards = [
    'steps',
    'water',
    'weight',
    'workout',
    'focus',
    'tasks',
    'nutrition',
    'xp',
  ];

  /// Which module owns which dashboard card.
  static const Map<String, String> dashboardCardModule = {
    'steps': 'body',
    'weight': 'body',
    'water': 'nutrition',
    'nutrition': 'nutrition',
    'workout': 'focus',
    'focus': 'focus',
    'tasks': 'tasks',
    'xp': 'gamification',
  };

  static const List<String> goalTypes = [
    'water',
    'steps',
    'weight_entry',
    'focus_minutes',
    'task_completion',
    'workout_weekly',
  ];

  static const List<String> themeModes = ['system', 'light', 'dark', 'oled'];

  static const List<String> focusCategories = [
    'reading',
    'learning',
    'programming',
    'meditation',
    'other',
  ];

  static const List<String> focusStatuses = [
    'running',
    'paused',
    'awaiting_confirmation',
    'completed',
    'discarded',
  ];

  /// Statuses of a session that is still open (at most one at a time).
  static const List<String> focusOpenStatuses = [
    'running',
    'paused',
    'awaiting_confirmation',
  ];

  static const List<String> taskPriorities = ['low', 'normal', 'high'];

  static const List<String> trainingCategories = [
    'strength',
    'cardio',
    'mobility',
    'sport',
  ];

  static const List<String> workoutIntensities = ['low', 'moderate', 'high'];

  static const List<String> muscleGroups = [
    'chest',
    'shoulders',
    'back',
    'biceps',
    'triceps',
    'legs',
    'core',
    'full_body',
  ];

  static const List<String> habitIcons = [
    'book',
    'moon',
    'drop',
    'check',
    'flame',
    'heart',
  ];

  static const List<String> xpSources = [
    'water',
    'weight',
    'steps',
    'task',
    'focus',
    'workout',
    'habit',
  ];

  static const List<String> reminderKinds = ['water', 'habit', 'focus_end'];

  static const List<String> notificationStates = ['scheduled', 'cancelled'];

  /// Voluntary onboarding preferences (stored as `motivation_goals`).
  static const List<String> motivationGoals = [
    'lose_weight',
    'get_fitter',
    'move_more',
    'live_healthier',
    'build_habits',
  ];

  /// Renders a SQL list literal such as `('a','b')` for CHECK constraints.
  static String sqlIn(Iterable<String> keys) =>
      '(${keys.map((k) => "'$k'").join(',')})';
}
