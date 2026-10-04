/// The five bundled functional modules. The string keys are a stable
/// technical contract (database, backup, routes) and never change.
enum ModuleId {
  body('body'),
  nutrition('nutrition'),
  focus('focus'),
  tasks('tasks'),
  gamification('gamification');

  const ModuleId(this.key);

  /// Stable persisted identifier.
  final String key;

  /// Returns the module for a persisted [key], or `null` when unknown.
  static ModuleId? tryParse(String key) {
    for (final id in values) {
      if (id.key == key) {
        return id;
      }
    }
    return null;
  }
}
