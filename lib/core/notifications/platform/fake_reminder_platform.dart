import 'dart:async';

import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Deterministic in-memory [ReminderPlatform] for tests. Not used in
/// production code.
///
/// It records every call and models the parts of the operating system the
/// engine relies on:
///
/// - **Alarms** ([alarms]): what the system would actually deliver.
/// - **Pending cache** ([pendingIds]): what the plugin reports as pending. A
///   [forceStop] clears the alarms but leaves the cache, exactly like the
///   Android plugin whose cache outlives a forced stop of the app.
/// - **Delivery** ([deliverDue]): fires due alarms; a delivered notification
///   leaves both sets and lands in [delivered].
/// - **Permission** with a configurable answer to a permission dialog.
/// - **Failures** for every call, to test the typed error handling.
final class FakeReminderPlatform implements ReminderPlatform {
  /// With a [clock], scheduling a time that is not in the future throws
  /// [PlatformFailureKind.timeInPast] like the real plugin does.
  FakeReminderPlatform({
    this.permission = NotificationPermission.granted,
    this.clock,
  });

  final ClockService? clock;

  /// The permission the "system" currently reports.
  NotificationPermission permission;

  /// What the permission dialog turns the permission into.
  NotificationPermission permissionAfterRequest =
      NotificationPermission.granted;

  /// Result of [openSystemSettings].
  bool settingsCanOpen = true;

  // ------------------------------------------------------ simulated state

  final Map<int, PlatformScheduleRequest> _alarms = {};
  final Map<int, PlatformScheduleRequest> _cache = {};
  final List<PlatformScheduleRequest> delivered = [];

  /// Alarms the system would deliver, by id.
  Map<int, PlatformScheduleRequest> get alarms => Map.unmodifiable(_alarms);

  // ------------------------------------------------------- recorded calls

  final List<PlatformScheduleRequest> scheduleCalls = [];
  final List<int> cancelCalls = [];
  int cancelAllPendingCalls = 0;
  int requestPermissionCalls = 0;
  int openSettingsCalls = 0;
  int permissionStatusCalls = 0;
  int pendingIdsCalls = 0;
  int initializeCalls = 0;

  /// Forgets the recorded calls (not the simulated state).
  void clearCalls() {
    scheduleCalls.clear();
    cancelCalls.clear();
    cancelAllPendingCalls = 0;
    requestPermissionCalls = 0;
    openSettingsCalls = 0;
    permissionStatusCalls = 0;
    pendingIdsCalls = 0;
    initializeCalls = 0;
  }

  // ----------------------------------------------------- failure injection

  /// Thrown by every [schedule] call while set.
  Object? scheduleFailure;

  /// Ids whose [schedule] call fails while in the set.
  final Set<int> failScheduleForIds = {};

  /// Thrown by every [cancel] and [cancelAllPending] call while set.
  Object? cancelFailure;

  /// Thrown by [permissionStatus] while set.
  Object? permissionFailure;

  /// Thrown by [pendingIds] while set.
  Object? pendingFailure;

  /// Thrown by [requestPermission] while set.
  Object? requestFailure;

  /// Thrown by [initialize] while set.
  Object? initializeFailure;

  /// While set, every [schedule] call waits for this future before it does
  /// anything: holds a reconcile run in the middle of its work, to test how
  /// concurrent calls are handled.
  Future<void>? scheduleGate;

  // -------------------------------------------------------- tap / launch

  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// The payload [launchPayload] returns once.
  String? launchPayloadValue;

  /// Simulates the user tapping a notification while the app runs.
  void emitTap(String payload) => _taps.add(payload);

  // ------------------------------------------------------ simulation hooks

  /// Fires every alarm due at or before [nowUtc]: it leaves the alarms and the
  /// cache and is recorded in [delivered].
  void deliverDue(DateTime nowUtc) {
    final due = _alarms.entries
        .where((e) => !e.value.fireAtUtc.isAfter(nowUtc))
        .toList();
    for (final entry in due) {
      delivered.add(entry.value);
      _alarms.remove(entry.key);
      _cache.remove(entry.key);
    }
  }

  /// Simulates a forced stop of the app: the system drops all alarms, but the
  /// plugin's list of pending notifications survives.
  void forceStop() => _alarms.clear();

  /// Simulates the system dropping everything (alarms and cache), e.g. after
  /// "clear data".
  void wipe() {
    _alarms.clear();
    _cache.clear();
  }

  // ------------------------------------------------------------ interface

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final failure = initializeFailure;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<NotificationPermission> permissionStatus() async {
    permissionStatusCalls++;
    final failure = permissionFailure;
    if (failure != null) {
      throw failure;
    }
    return permission;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    requestPermissionCalls++;
    final failure = requestFailure;
    if (failure != null) {
      throw failure;
    }
    if (permission != NotificationPermission.granted) {
      permission = permissionAfterRequest;
    }
    return permission;
  }

  @override
  Future<bool> openSystemSettings() async {
    openSettingsCalls++;
    return settingsCanOpen;
  }

  @override
  Future<void> schedule(PlatformScheduleRequest request) async {
    scheduleCalls.add(request);
    final gate = scheduleGate;
    if (gate != null) {
      await gate;
    }
    final failure = scheduleFailure;
    if (failure != null) {
      throw failure;
    }
    if (failScheduleForIds.contains(request.id)) {
      throw const ReminderPlatformException(PlatformFailureKind.failed);
    }
    if (request.id <= 0 || request.id > 0x7FFFFFFF) {
      throw const ReminderPlatformException(PlatformFailureKind.failed);
    }
    final now = clock?.nowUtc();
    if (now != null && !request.fireAtUtc.isAfter(now)) {
      throw const ReminderPlatformException(PlatformFailureKind.timeInPast);
    }
    _alarms[request.id] = request;
    _cache[request.id] = request;
  }

  @override
  Future<void> cancel(int notificationId) async {
    cancelCalls.add(notificationId);
    final failure = cancelFailure;
    if (failure != null) {
      throw failure;
    }
    _alarms.remove(notificationId);
    _cache.remove(notificationId);
  }

  @override
  Future<void> cancelAllPending() async {
    cancelAllPendingCalls++;
    final failure = cancelFailure;
    if (failure != null) {
      throw failure;
    }
    _alarms.clear();
    _cache.clear();
  }

  @override
  Future<Set<int>> pendingIds() async {
    pendingIdsCalls++;
    final failure = pendingFailure;
    if (failure != null) {
      throw failure;
    }
    return Set.of(_cache.keys);
  }

  @override
  Future<String?> launchPayload() async {
    final payload = launchPayloadValue;
    launchPayloadValue = null;
    return payload;
  }

  @override
  Stream<String> get tapStream => _taps.stream;

  /// Releases the tap stream.
  Future<void> dispose() => _taps.close();
}
