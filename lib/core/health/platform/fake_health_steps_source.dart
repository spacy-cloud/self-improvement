import 'dart:async';

import 'package:self_improvement/core/health/domain/health_steps_source.dart';

/// Deterministic in-memory [HealthStepsSource] for tests. Not used in
/// production code.
///
/// It models what the steps comparison relies on:
///
/// - **Availability and access** that tests set, and an answer to the system
///   dialog ([accessAfterRequest]).
/// - **Step records** ([addSteps]) that [totalSteps] aggregates. A record
///   counts in the range that contains its time; the real interface splits a
///   record that spans a boundary in proportion, which this fake does not
///   (records are points). Records of different origins are simply added up
///   here: merging duplicate sources is the job of the real interface and can
///   only be checked on a device.
/// - **Recorded calls**, so tests see which ranges were asked, and how often
///   the dialog and the setting pages were opened.
/// - **Failures** for every call and for single ranges, and a gate that holds
///   a read in the middle of its work.
final class FakeHealthStepsSource implements HealthStepsSource {
  FakeHealthStepsSource({
    this.availabilityValue = HealthAvailability.available,
    this.accessValue = HealthAccess.granted,
    this.displayName = 'Health Connect',
  });

  @override
  final String displayName;

  /// What [availability] reports.
  HealthAvailability availabilityValue;

  /// What [access] reports.
  HealthAccess accessValue;

  /// What the system dialog turns the access into.
  HealthAccess accessAfterRequest = HealthAccess.granted;

  /// Result of [openInstallPage].
  bool installPageCanOpen = true;

  /// Result of [openAccessSettings].
  bool accessSettingsCanOpen = true;

  // ------------------------------------------------------ simulated data

  final List<({DateTime atUtc, int steps, String origin})> _records = [];

  /// Adds a step record at [atUtc] (a point in time) with [steps] steps.
  void addSteps(DateTime atUtc, int steps, {String origin = 'phone'}) {
    assert(atUtc.isUtc, 'instants are UTC');
    _records.add((atUtc: atUtc, steps: steps, origin: origin));
  }

  /// Removes every record (the days have no data any more).
  void clearSteps() => _records.clear();

  // ------------------------------------------------------ recorded calls

  int availabilityCalls = 0;
  int accessCalls = 0;
  int requestAccessCalls = 0;
  int installPageCalls = 0;
  int accessSettingsCalls = 0;

  /// Every range [totalSteps] was asked for, in call order.
  final List<({DateTime startUtc, DateTime endUtc})> totalCalls = [];

  /// Forgets the recorded calls (not the simulated data).
  void clearCalls() {
    availabilityCalls = 0;
    accessCalls = 0;
    requestAccessCalls = 0;
    installPageCalls = 0;
    accessSettingsCalls = 0;
    totalCalls.clear();
  }

  // ----------------------------------------------------- failure injection

  /// Thrown by [availability] while set.
  Object? availabilityFailure;

  /// Thrown by [access] while set.
  Object? accessFailure;

  /// Thrown by [requestAccess] while set.
  Object? requestFailure;

  /// Thrown by every [totalSteps] call while set.
  Object? totalFailure;

  /// Ranges (by their start) for which [totalSteps] throws
  /// [totalFailureForStarts]; the other ranges answer normally.
  final Set<DateTime> failTotalAtStarts = {};

  /// What a range in [failTotalAtStarts] throws.
  Object totalFailureForStarts = const HealthStepsException(
    HealthFailureKind.failed,
  );

  /// While set, every [totalSteps] call waits for this future before it
  /// answers: holds a comparison in the middle of its work, to test how
  /// concurrent calls are handled.
  Future<void>? totalGate;

  /// While set, [requestAccess] waits for this future before it answers (the
  /// system dialog is open).
  Future<void>? requestGate;

  // --------------------------------------------------- HealthStepsSource

  @override
  Future<HealthAvailability> availability() async {
    availabilityCalls++;
    final failure = availabilityFailure;
    if (failure != null) {
      throw failure;
    }
    return availabilityValue;
  }

  @override
  Future<HealthAccess> access() async {
    accessCalls++;
    final failure = accessFailure;
    if (failure != null) {
      throw failure;
    }
    return accessValue;
  }

  @override
  Future<HealthAccess> requestAccess() async {
    requestAccessCalls++;
    final gate = requestGate;
    if (gate != null) {
      await gate;
    }
    final failure = requestFailure;
    if (failure != null) {
      throw failure;
    }
    accessValue = accessAfterRequest;
    return accessValue;
  }

  @override
  Future<int?> totalSteps({
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    assert(startUtc.isUtc && endUtc.isUtc, 'instants are UTC');
    totalCalls.add((startUtc: startUtc, endUtc: endUtc));
    final gate = totalGate;
    if (gate != null) {
      await gate;
    }
    final failure = totalFailure;
    if (failure != null) {
      throw failure;
    }
    if (failTotalAtStarts.contains(startUtc)) {
      throw totalFailureForStarts;
    }
    if (accessValue != HealthAccess.granted) {
      throw const HealthStepsException(HealthFailureKind.accessDenied);
    }
    var found = false;
    var total = 0;
    for (final record in _records) {
      if (!record.atUtc.isBefore(startUtc) && record.atUtc.isBefore(endUtc)) {
        found = true;
        total += record.steps;
      }
    }
    return found ? total : null;
  }

  @override
  Future<bool> openInstallPage() async {
    installPageCalls++;
    return installPageCanOpen;
  }

  @override
  Future<bool> openAccessSettings() async {
    accessSettingsCalls++;
    return accessSettingsCanOpen;
  }
}
