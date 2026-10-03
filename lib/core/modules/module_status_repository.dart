import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Reads the activation state of the five modules from the append-only
/// history. A module without any history row counts as enabled (all five are
/// on by default).
class ModuleStatusRepository {
  ModuleStatusRepository(this._database);

  final AppDatabase _database;

  /// Current state of every module, re-emitted on each change.
  Stream<Map<ModuleId, bool>> watchStatuses() => _database
      .select(_database.moduleStatusHistory)
      .watch()
      .map((rows) => statusesFromHistory(rows, null));

  /// Current state of every module.
  Future<Map<ModuleId, bool>> statuses() async {
    final rows = await _database.select(_database.moduleStatusHistory).get();
    return statusesFromHistory(rows, null);
  }

  /// Whether [module] is enabled right now (also valid inside a transaction).
  Future<bool> isEnabled(ModuleId module) async =>
      (await statuses())[module] ?? true;

  /// Whether [module] was enabled on [day] (last change on or before [day]).
  Future<bool> isEnabledOn(ModuleId module, LocalDate day) async {
    final rows = await (_database.select(
      _database.moduleStatusHistory,
    )..where((r) => r.moduleId.equals(module.key))).get();
    return statusesFromHistory(rows, day)[module] ?? true;
  }

  /// Pure: the state per module from history [rows], optionally as of [day].
  ///
  /// The latest change by time (then id) with a date up to [day] wins.
  static Map<ModuleId, bool> statusesFromHistory(
    Iterable<ModuleStatusRow> rows,
    LocalDate? day,
  ) {
    final latest = <ModuleId, ModuleStatusRow>{};
    for (final row in rows) {
      final module = ModuleId.tryParse(row.moduleId);
      if (module == null || (day != null && row.localDate.isAfter(day))) {
        continue;
      }
      final current = latest[module];
      if (current == null || _isNewer(row, current)) {
        latest[module] = row;
      }
    }
    return {
      for (final module in ModuleId.values)
        module: latest[module]?.enabled ?? true,
    };
  }

  static bool _isNewer(ModuleStatusRow a, ModuleStatusRow b) {
    final byTime = a.effectiveAtUtc.compareTo(b.effectiveAtUtc);
    return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
  }
}
