import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/notifications/data/reminder_input_reader.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_planner.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Keeps the notifications of the operating system equal to what the user
/// wants: one method, [reconcile], computes the desired set and makes the
/// system match it.
///
/// ## How a run works
///
/// 1. Read the facts once (master switch, permission from the device, module
///    statuses, water rules, habits, open tasks with a reminder, the open
///    focus session, whether today's water goal is reached) and let the pure
///    [ReminderPlanner] compute the desired set: at most 40 notifications,
///    recurring ones within seven calendar days, a task reminder at any
///    distance.
/// 2. Diff it against the projection table `scheduled_notifications`, keyed by
///    the semantic key (`water:2026-10-03:10:00`, `habit:<id>:2026-10-03`,
///    `task:<id>`, `focus_end:<sessionId>`):
///    - same key and same fire time: kept, nothing is called;
///    - same key, other time (habit time edited, task reminder moved, time
///      zone changed): rescheduled under the **same integer id**;
///    - new key: the row is inserted first (its autoincrement id is the id the
///      system gets), then the notification is scheduled;
///    - key no longer wanted (module off, habit archived or deleted, task
///      completed, deleted or its reminder removed, slot switched off, water
///      goal reached, focus paused): cancelled, then the row is deleted.
/// 3. With the master switch off or without the system permission nothing is
///    scheduled and everything pending is cancelled.
///
/// A second run with unchanged facts does nothing (it only reads). The
/// integer ids come from the database counter, never from hash codes, and an
/// id is never reused for another reminder.
///
/// ## Failures never reach the user's data
///
/// [reconcile] never throws. A platform or database failure is reported in the
/// returned [ReminderStatus] (`lastError`, `failedCount`) so the settings
/// screen can show "Planungsfehler" with a retry; the retry is just another
/// [reconcile] and never commits business data again. The projection is kept
/// consistent without half states: a notification that could not be handed to
/// the system is **removed** from the projection (it is not kept for a later
/// retry as a "pending" row), so the next run sees it as missing and tries
/// again, and a notification whose rescheduling failed is cancelled instead of
/// being left at its old time. Apart from the moment between inserting a row
/// and handing it to the system, a row only describes a notification the system
/// accepted; a crash in that moment is repaired by the next run (see below).
/// The schema's `cancelled` state is not used: a cancelled notification has no
/// row.
///
/// The service also heals itself: an id the system reports as pending but the
/// projection does not know (an orphan, e.g. after data was replaced) is
/// cancelled, and a future row the system no longer lists is registered again.
/// The first run of a process registers every wanted notification again,
/// because the system drops all alarms when the user force-stops the app
/// while the plugin's own list still claims they are pending.
///
/// ## When to call [reconcile] (wired by the app shell)
///
/// App start, resume from background, after a data import or reset, after a
/// change of goals, modules, reminder rules or habits, and after the time zone
/// changed. `ReminderAutoReconciler` covers every change that is written to
/// the database; start, resume and the time zone have to be called from the
/// lifecycle. Concurrent calls are coalesced: while a run is busy, further
/// calls share one follow-up run that starts after it.
///
/// ## Honest limits of local notifications
///
/// - **Inexact timing.** On Android the notifications are inexact alarms
///   (`inexactAllowWhileIdle`; no exact-alarm permission, no foreground
///   service). The system may deliver them several minutes late, especially in
///   doze mode. The app is not a clock.
/// - **No background service.** Nothing runs between the planned alarms, so
///   reminders only exist for what was planned while the app ran: at most 40
///   notifications; the recurring ones (water, habits) at most seven days
///   ahead, a task reminder at any distance (it is one moment the user chose).
///   Anyone who does not open the app for a long time stops receiving
///   recurring reminders after the planned window. With very many reminders
///   only the nearest ones are planned ([ReminderStatus.planLimitReached]);
///   the rest follows when the app is opened.
/// - **Forced stop.** After "Force stop" in the system settings the system
///   cancels all alarms of the app. Delivery resumes only after the user opens
///   the app again.
/// - **Reboot.** The plugin re-registers its pending notifications after a
///   reboot or an app update. Reminders whose time passed while the device was
///   off are shown immediately when re-registered (derived from the plugin's
///   source, not measured on a device).
/// - **Vendor battery savers** can suppress alarms of apps; the app cannot
///   change that.
/// - **Permission.** The user may refuse or later revoke the permission. The
///   app then shows the blocked state with a link to the system settings and
///   stays fully usable; no data depends on notifications.
/// - There is no delivery history: the app only knows what it planned.
final class ReminderService {
  ReminderService({
    required this._inputs,
    required this._scheduled,
    required this._preferences,
    required this._platform,
    required ClockService clock,
    ReminderPlanner? planner,
  }) : _clock = clock,
       _planner = planner ?? ReminderPlanner(clock: clock);

  final ReminderInputReader _inputs;
  final ScheduledNotificationRepository _scheduled;
  final ReminderPreferencesRepository _preferences;
  final ReminderPlatform _platform;
  final ClockService _clock;
  final ReminderPlanner _planner;

  final StreamController<ReminderStatus> _updates =
      StreamController<ReminderStatus>.broadcast();

  /// The run in progress and the single follow-up run waiting for it.
  Future<ReminderStatus>? _active;
  Future<ReminderStatus>? _queued;

  /// Whether this process already registered all wanted notifications once.
  bool _alarmsAsserted = false;

  ReminderStatus? _last;
  bool _disposed = false;

  // ----------------------------------------------------------- reconcile

  /// Brings the operating system in line with the wishes of the user and
  /// returns the resulting status. Never throws. See the class documentation.
  Future<ReminderStatus> reconcile() {
    // A follow-up run that is already waiting sees everything changed so far.
    final queued = _queued;
    if (queued != null) {
      return queued;
    }
    final active = _active;
    if (active == null) {
      return _start();
    }
    return _queued = active.then((_) {
      _queued = null;
      return _start();
    });
  }

  Future<ReminderStatus> _start() {
    final run = _reconcileOnce();
    _active = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_active, run)) {
          _active = null;
        }
      }),
    );
    return run;
  }

  /// Completes when no run is active or waiting. For tests and shutdown.
  Future<void> whenIdle() async {
    while (_active != null || _queued != null) {
      await (_queued ?? _active)!;
    }
  }

  Future<ReminderStatus> _reconcileOnce() async {
    final run = _Run(
      nowUtc: _clock.nowUtc(),
      timeZoneId: _clock.timeZoneId,
      refreshAll: !_alarmsAsserted,
    );
    try {
      await _reconcileSteps(run);
    } catch (error) {
      // Nothing above is expected to throw (every call is guarded); this keeps
      // the contract "never throws" even for an unforeseen error such as an
      // unknown time zone id.
      run.fail(ReminderErrorCategory.unknown, error);
    }
    final status = await _finish(run);
    _publish(status);
    return status;
  }

  Future<void> _reconcileSteps(_Run run) async {
    final permission = await _readPermission(run);
    run.permission = permission;

    final ReminderInputs inputs;
    try {
      inputs = await _inputs.read(
        nowUtc: run.nowUtc,
        timeZoneId: run.timeZoneId,
        permission: permission,
      );
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
      return;
    }
    run.wanted = inputs.remindersWanted;

    final plan = _planner.plan(inputs);
    run.limitReached = plan.limitReached;

    final List<ScheduledReminder> rows;
    try {
      rows = await _scheduled.all();
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
      return;
    }
    final pending = await _readPending(run);

    if (plan.skipped != null) {
      await _cancelEverything(run, rows, pending);
      return;
    }

    // Reminders are wanted and allowed: make sure the platform is ready (the
    // app shell normally did it at start; this is idempotent). Without it
    // nothing can be scheduled, so the run ends here and tries again later.
    final notReady = await _platformCall(_platform.initialize);
    if (notReady != null) {
      run.fail(_categoryOf(notReady), notReady);
      return;
    }
    await _apply(run, plan.notifications, rows, pending);
    _alarmsAsserted = true;
  }

  // ---------------------------------------------------------------- diff

  Future<void> _cancelEverything(
    _Run run,
    List<ScheduledReminder> rows,
    Set<int>? pending,
  ) async {
    final nothingToCancel = rows.isEmpty && pending != null && pending.isEmpty;
    if (nothingToCancel) {
      return;
    }
    final failure = await _platformCall(_platform.cancelAllPending);
    if (failure != null) {
      // The rows stay: they still describe what the system holds.
      run.fail(_categoryOf(failure), failure);
      return;
    }
    try {
      await _scheduled.deleteAll();
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
    }
  }

  Future<void> _apply(
    _Run run,
    List<PlannedNotification> desired,
    List<ScheduledReminder> rows,
    Set<int>? pending,
  ) async {
    final desiredKeys = {for (final p in desired) p.semanticKey};
    final rowsByKey = {for (final row in rows) row.semanticKey: row};
    final live = {for (final row in rows) row.notificationId};
    final cancelled = <int>{};

    // 1. Notifications that are no longer wanted.
    for (final row in rows) {
      if (desiredKeys.contains(row.semanticKey)) {
        continue;
      }
      // A cancel also removes a notification that was already delivered from
      // the shade. A row in the past that the system no longer lists was
      // delivered: only its row is removed.
      final stillAhead =
          row.fireAtUtc.isAfter(run.nowUtc) ||
          (pending?.contains(row.notificationId) ?? false);
      if (stillAhead) {
        final failure = await _platformCall(
          () => _platform.cancel(row.notificationId),
        );
        if (failure != null) {
          run.fail(_categoryOf(failure), failure);
          continue; // keep the row: the system still holds it
        }
        cancelled.add(row.notificationId);
      }
      if (await _deleteRow(run, row.notificationId)) {
        live.remove(row.notificationId);
      }
    }

    // 2. Wanted notifications, soonest first.
    for (final planned in desired) {
      final row = rowsByKey[planned.semanticKey];
      if (row == null) {
        await _scheduleNew(run, planned, live, cancelled);
        continue;
      }
      final moved =
          row.fireAtUtc != planned.fireAtUtc ||
          row.route != planned.route ||
          row.sourceRuleId != planned.sourceRuleId;
      final lost = pending != null && !pending.contains(row.notificationId);
      if (moved || lost || run.refreshAll) {
        await _reschedule(run, row, planned, moved, live, cancelled);
      }
    }

    // 3. Orphans: pending in the system but unknown to the projection.
    if (pending != null) {
      for (final id in pending) {
        if (live.contains(id) || cancelled.contains(id)) {
          continue;
        }
        final failure = await _platformCall(() => _platform.cancel(id));
        if (failure != null) {
          run.fail(_categoryOf(failure), failure);
        }
      }
    }
  }

  Future<void> _scheduleNew(
    _Run run,
    PlannedNotification planned,
    Set<int> live,
    Set<int> cancelled,
  ) async {
    final int id;
    try {
      id = await _scheduled.insert(planned);
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
      return;
    }
    live.add(id);
    await _register(run, id, planned, live, cancelled);
  }

  Future<void> _reschedule(
    _Run run,
    ScheduledReminder row,
    PlannedNotification planned,
    bool moved,
    Set<int> live,
    Set<int> cancelled,
  ) async {
    final registered = await _register(
      run,
      row.notificationId,
      planned,
      live,
      cancelled,
    );
    if (!registered || !moved) {
      return;
    }
    try {
      await _scheduled.update(row.notificationId, planned);
    } catch (error) {
      // The system has the new time, the row the old one: the next run sees
      // the difference again and repeats this idempotent step.
      run.fail(ReminderErrorCategory.storage, error);
    }
  }

  /// Hands [planned] to the system under [id]. On failure the notification is
  /// removed from the system (best effort) and from the projection: it is
  /// either registered correctly or not at all.
  Future<bool> _register(
    _Run run,
    int id,
    PlannedNotification planned,
    Set<int> live,
    Set<int> cancelled,
  ) async {
    final failure = await _platformCall(
      () => _platform.schedule(
        PlatformScheduleRequest(
          id: id,
          fireAtUtc: planned.fireAtUtc,
          timeZoneId: run.timeZoneId,
          title: planned.title,
          payload: planned.route,
        ),
      ),
    );
    if (failure == null) {
      return true;
    }
    // A time that slipped into the past while the run was busy is not a fault.
    if (failure.kind != PlatformFailureKind.timeInPast) {
      run.fail(_categoryOf(failure), failure);
    }
    final rollback = await _platformCall(() => _platform.cancel(id));
    if (rollback == null) {
      cancelled.add(id);
    }
    if (await _deleteRow(run, id)) {
      live.remove(id);
    }
    return false;
  }

  Future<bool> _deleteRow(_Run run, int id) async {
    try {
      await _scheduled.delete(id);
      return true;
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
      return false;
    }
  }

  // ------------------------------------------------------------ platform

  Future<NotificationPermission> _readPermission(_Run run) async {
    try {
      return await _platform.permissionStatus();
    } catch (error) {
      run.fail(ReminderErrorCategory.platform, error);
      return NotificationPermission.unavailable;
    }
  }

  Future<Set<int>?> _readPending(_Run run) async {
    try {
      return await _platform.pendingIds();
    } catch (error) {
      run.fail(ReminderErrorCategory.platform, error);
      return null;
    }
  }

  /// Runs [call] and returns its failure, typed; `null` on success.
  Future<ReminderPlatformException?> _platformCall(
    Future<void> Function() call,
  ) async {
    try {
      await call();
      return null;
    } on ReminderPlatformException catch (failure) {
      return failure;
    } catch (error) {
      return ReminderPlatformException(
        PlatformFailureKind.failed,
        causeType: error.runtimeType.toString(),
      );
    }
  }

  static ReminderErrorCategory _categoryOf(ReminderPlatformException failure) =>
      switch (failure.kind) {
        PlatformFailureKind.permissionMissing =>
          ReminderErrorCategory.permission,
        PlatformFailureKind.timeInPast ||
        PlatformFailureKind.failed => ReminderErrorCategory.platform,
      };

  // -------------------------------------------------------------- status

  Future<ReminderStatus> _finish(_Run run) async {
    var count = 0;
    DateTime? next;
    try {
      final rows = await _scheduled.all();
      count = rows.length;
      for (final row in rows) {
        if (row.fireAtUtc.isAfter(run.nowUtc)) {
          next = row.fireAtUtc;
          break;
        }
      }
    } catch (error) {
      run.fail(ReminderErrorCategory.storage, error);
    }
    return ReminderStatus(
      wanted: run.wanted ?? _last?.wanted ?? false,
      permission:
          run.permission ??
          _last?.permission ??
          NotificationPermission.unavailable,
      scheduledCount: count,
      lastError: run.lastError,
      failedCount: run.failedCount,
      planLimitReached: run.limitReached,
      nextFireAtUtc: next,
    );
  }

  void _publish(ReminderStatus status) {
    final unchanged = _last == status;
    _last = status;
    if (!unchanged && !_disposed) {
      _updates.add(status);
    }
  }

  /// The current status without scheduling anything: the wish of the user, the
  /// permission as the device reports it now, the size of the projection and
  /// the outcome of the latest run. Never throws.
  Future<ReminderStatus> readStatus() async {
    try {
      final wanted = await _preferences.notificationsWanted();
      final permission = await permissionStatus();
      final rows = await _scheduled.all();
      final now = _clock.nowUtc();
      final upcoming = rows.where((row) => row.fireAtUtc.isAfter(now));
      return ReminderStatus(
        wanted: wanted,
        permission: permission,
        scheduledCount: rows.length,
        lastError: _last?.lastError,
        failedCount: _last?.failedCount ?? 0,
        planLimitReached: _last?.planLimitReached ?? false,
        nextFireAtUtc: upcoming.isEmpty ? null : upcoming.first.fireAtUtc,
      );
    } catch (error) {
      debugPrint('reminder status: ${error.runtimeType}');
      return ReminderStatus(
        wanted: _last?.wanted ?? false,
        permission: _last?.permission ?? NotificationPermission.unavailable,
        scheduledCount: _last?.scheduledCount ?? 0,
        lastError: ReminderErrorCategory.storage,
        failedCount: _last?.failedCount ?? 0,
      );
    }
  }

  /// Streams the status: first the current one, then every change that a
  /// [reconcile] run reports.
  Stream<ReminderStatus> watchStatus() {
    late final StreamController<ReminderStatus> controller;
    StreamSubscription<ReminderStatus>? subscription;
    controller = StreamController<ReminderStatus>(
      onListen: () {
        var updated = false;
        subscription = _updates.stream.listen((status) {
          updated = true;
          controller.add(status);
        });
        unawaited(
          readStatus().then((status) {
            // A run that finished meanwhile is newer than this read.
            if (!updated && !controller.isClosed) {
              controller.add(status);
            }
          }),
        );
      },
      onCancel: () async {
        await subscription?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  // ---------------------------------------------------------- permission

  /// The notification permission as the device reports it now; never shows a
  /// dialog and never throws (`unavailable` when it cannot be read).
  Future<NotificationPermission> permissionStatus() async {
    try {
      return await _platform.permissionStatus();
    } catch (error) {
      debugPrint('reminder permission: ${error.runtimeType}');
      return NotificationPermission.unavailable;
    }
  }

  /// Shows the system permission dialog (where there is one), then reconciles
  /// so the reminders are planned right away when it was granted. Returns the
  /// resulting permission. Call it only after the user switched reminders on
  /// and after an explanation. Never throws.
  Future<NotificationPermission> requestPermission() async {
    final result = await _requestFromPlatform();
    await reconcile();
    return result;
  }

  Future<NotificationPermission> _requestFromPlatform() async {
    try {
      return await _platform.requestPermission();
    } catch (error) {
      debugPrint('reminder permission request: ${error.runtimeType}');
      return NotificationPermission.unavailable;
    }
  }

  /// Opens the notification settings of the app (the way out of the blocked
  /// state). Never throws; false when nothing could be opened.
  Future<bool> openSystemSettings() async {
    try {
      return await _platform.openSystemSettings();
    } catch (error) {
      debugPrint('reminder settings: ${error.runtimeType}');
      return false;
    }
  }

  // ------------------------------------------------ switch on / switch off

  /// The user switched reminders on (after the explanation was shown): stores
  /// the wish, asks the system for the permission if it is missing, and
  /// reconciles.
  ///
  /// Only storing the wish is a business command: it can throw an
  /// `AppFailure` (storage), and a retry with the same [commandId] never
  /// stores it twice. Everything after it reports through the returned
  /// status; a refusal leaves the wish on and shows the blocked state.
  Future<ReminderStatus> enableReminders({required String commandId}) async {
    await _preferences.setNotificationsEnabled(
      commandId: commandId,
      enabled: true,
    );
    if (await permissionStatus() != NotificationPermission.granted) {
      await _requestFromPlatform();
    }
    return reconcile();
  }

  /// The user switched reminders off: stores the wish and cancels everything.
  /// Throws only the storage failure of the command, like [enableReminders].
  Future<ReminderStatus> disableReminders({required String commandId}) async {
    await _preferences.setNotificationsEnabled(
      commandId: commandId,
      enabled: false,
    );
    return reconcile();
  }

  /// The user chose which water slots (10, 12, 14, 16, 18 o'clock) remind
  /// them: stores the selection and reconciles. Throws only what the command
  /// throws (`ValidationFailure` for an hour that is not offered, or a storage
  /// failure), like [enableReminders]; everything after it reports through the
  /// returned status.
  Future<ReminderStatus> setWaterSlots({
    required String commandId,
    required Set<int> hours,
  }) async {
    await _preferences.setWaterSlots(commandId: commandId, hours: hours);
    return reconcile();
  }

  /// Releases the status stream.
  Future<void> dispose() async {
    _disposed = true;
    await _updates.close();
  }
}

/// Mutable bookkeeping of one reconcile run.
final class _Run {
  _Run({
    required this.nowUtc,
    required this.timeZoneId,
    required this.refreshAll,
  });

  /// The instant the run started; the whole run reasons about this instant.
  final DateTime nowUtc;
  final String timeZoneId;

  /// Register all wanted notifications again (first run of a process).
  final bool refreshAll;

  bool? wanted;
  NotificationPermission? permission;
  bool limitReached = false;
  ReminderErrorCategory? lastError;
  int failedCount = 0;

  void fail(ReminderErrorCategory category, Object error) {
    lastError = category;
    failedCount++;
    // Only the type: messages of platform and storage errors can hold values.
    debugPrint('reminder reconcile: ${category.name} (${error.runtimeType})');
  }
}
