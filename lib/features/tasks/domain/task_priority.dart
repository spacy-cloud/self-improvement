/// Priority of a task. The keys are stored in the database
/// (`SchemaKeys.taskPriorities`) and exported in backups.
enum TaskPriority {
  low('low', 'Niedrig'),
  normal('normal', 'Normal'),
  high('high', 'Hoch');

  const TaskPriority(this.key, this.label);

  /// Stable storage key.
  final String key;

  /// German label for chips, menus and semantics ("Priorität: Hoch").
  final String label;

  /// Sort rank: the higher, the more important (low 0, normal 1, high 2).
  int get rank => index;

  /// The priority stored under [key], or null for an unknown key.
  static TaskPriority? tryParse(String key) {
    for (final priority in values) {
      if (priority.key == key) {
        return priority;
      }
    }
    return null;
  }
}

/// The priority of a task that was not given one.
const TaskPriority defaultTaskPriority = TaskPriority.normal;
