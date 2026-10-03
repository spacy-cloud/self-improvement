import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/application/reminder_service.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// Result of a change of the reminder settings.
sealed class ReminderChange {
  const ReminderChange();
}

/// The change was stored; [status] is what the engine reports afterwards
/// (permission, planned count, last error). A refusal of the system is not a
/// failure of the change: it shows up in [status].
final class ReminderChanged extends ReminderChange {
  const ReminderChanged(this.status);

  final ReminderStatus status;
}

/// The change could not be stored; nothing changed. Retrying the same action
/// is safe (same command id).
final class ReminderChangeFailed extends ReminderChange {
  const ReminderChangeFailed(this.failure);

  final AppFailure failure;
}

/// The operations of the reminder settings as one small facade over the
/// reminder engine: the master switch, the water slots, the permission and the
/// system settings.
///
/// Storing a wish is a command with the `SubmissionTracker` pattern: retrying
/// the same change reuses the command id, so a retry never stores twice, and a
/// different change gets a new id. Everything the operating system does
/// (permission dialog, planning) reports through the returned status; it never
/// throws.
class ReminderActions {
  ReminderActions({
    required this._service,
    required this._preferences,
    required IdGenerator ids,
  }) : _tracker = SubmissionTracker(ids);

  final ReminderService _service;
  final ReminderPreferencesRepository _preferences;
  final SubmissionTracker _tracker;

  /// Slot changes run one after the other, so two quick taps on two slots
  /// both end up in the stored set.
  Future<void> _slotQueue = Future<void>.value();

  /// The notification permission as the device reports it now. Never shows a
  /// dialog and never throws.
  Future<NotificationPermission> permissionStatus() =>
      _service.permissionStatus();

  /// Switches reminders on: stores the wish, then (with [askSystem]) shows the
  /// system permission dialog if the permission is missing, then plans.
  ///
  /// Without [askSystem] the wish is stored and planned for without asking:
  /// the user chose to grant the permission in the system settings instead.
  Future<ReminderChange> enable({required bool askSystem}) async {
    try {
      final id = _tracker.idFor(('enable', askSystem));
      final ReminderStatus status;
      if (askSystem) {
        status = await _service.enableReminders(commandId: id);
      } else {
        await _preferences.setNotificationsEnabled(
          commandId: id,
          enabled: true,
        );
        status = await _service.reconcile();
      }
      _tracker.completed();
      return ReminderChanged(status);
    } on AppFailure catch (failure) {
      return ReminderChangeFailed(failure);
    }
  }

  /// Switches reminders off: stores the wish and removes every planned
  /// notification.
  Future<ReminderChange> disable() async {
    try {
      final status = await _service.disableReminders(
        commandId: _tracker.idFor(const ('disable', true)),
      );
      _tracker.completed();
      return ReminderChanged(status);
    } on AppFailure catch (failure) {
      return ReminderChangeFailed(failure);
    }
  }

  /// Switches the water slot at [hour] on or off. [current] reads the stored
  /// set at the moment the change runs (not at the moment of the tap).
  Future<ReminderChange> toggleWaterSlot(
    int hour, {
    required Set<int> Function() current,
  }) {
    final run = _slotQueue.then((_) => _toggleWaterSlot(hour, current()));
    _slotQueue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<ReminderChange> _toggleWaterSlot(int hour, Set<int> current) async {
    final hours = <int>{...current};
    if (!hours.remove(hour)) {
      hours.add(hour);
    }
    final sorted = hours.toList()..sort();
    try {
      final status = await _service.setWaterSlots(
        commandId: _tracker.idFor('water:${sorted.join(',')}'),
        hours: hours,
      );
      _tracker.completed();
      return ReminderChanged(status);
    } on AppFailure catch (failure) {
      return ReminderChangeFailed(failure);
    }
  }

  /// Plans again from the current wishes and facts and returns the status.
  /// Used after returning from the system settings and for "Wiederholen".
  /// Never throws.
  Future<ReminderStatus> refresh() => _service.reconcile();

  /// Opens the notification settings of the app. Never throws; `false` when
  /// nothing could be opened.
  Future<bool> openSystemSettings() => _service.openSystemSettings();
}

/// The reminder operations of the settings.
final reminderActionsProvider = Provider<ReminderActions>(
  (ref) => ReminderActions(
    service: ref.watch(reminderServiceProvider),
    preferences: ref.watch(reminderPreferencesRepositoryProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);
