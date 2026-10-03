import 'dart:async';

import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';

/// Reconciles the reminders whenever data that influences them changes.
///
/// It listens to the tables the plan depends on and calls
/// [ReminderService.reconcile] after each committed change:
///
/// - `app_settings` (master switch), `reminder_rules` (water slots)
/// - `module_status_history` (modules switched on or off)
/// - `habits` (new, edited time, archived, deleted, restored by undo)
/// - `focus_sessions` (start, pause, resume, finish, discard)
/// - `water_entries`, `goal_versions`, `daily_goal_snapshots` (the
///   "today's water goal is reached" fact)
///
/// A data import or reset writes these tables in a transaction and therefore
/// triggers it as well. Bursts of changes need no debounce timer: the service
/// coalesces calls that arrive while a run is busy into one follow-up run.
///
/// It does not cover app start, resume from background and a time zone
/// change; the app shell calls [ReminderService.reconcile] for those.
///
/// A reconcile reads committed data. The injected "water goal reached today"
/// fact must therefore be answered from the database too and not from a UI
/// cache that updates after this trigger fired.
final class ReminderAutoReconciler {
  ReminderAutoReconciler({required this._database, required this._service});

  final AppDatabase _database;
  final ReminderService _service;
  StreamSubscription<Set<TableUpdate>>? _subscription;

  /// Starts listening. With [reconcileNow] (default) one run starts right
  /// away, which is the "app start" trigger. Idempotent.
  void start({bool reconcileNow = true}) {
    if (_subscription != null) {
      return;
    }
    _subscription = _database
        .tableUpdates(
          TableUpdateQuery.allOf([
            TableUpdateQuery.onTable(_database.appSettings),
            TableUpdateQuery.onTable(_database.reminderRules),
            TableUpdateQuery.onTable(_database.moduleStatusHistory),
            TableUpdateQuery.onTable(_database.habits),
            TableUpdateQuery.onTable(_database.focusSessions),
            TableUpdateQuery.onTable(_database.waterEntries),
            TableUpdateQuery.onTable(_database.goalVersions),
            TableUpdateQuery.onTable(_database.dailyGoalSnapshots),
          ]),
        )
        .listen((_) => unawaited(_service.reconcile()));
    if (reconcileNow) {
      unawaited(_service.reconcile());
    }
  }

  /// Stops listening.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
