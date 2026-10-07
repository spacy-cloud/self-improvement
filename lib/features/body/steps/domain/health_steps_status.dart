import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';

/// The state of "Schritte aus Health übernehmen" as the screens show it.
///
/// Every state has one honest text and at most one way out; nothing here
/// claims more than the app knows.
enum HealthStepsCondition {
  /// Nothing to show: the device has no health interface the app supports, or
  /// the module "Gewicht & Körper" is off.
  hidden,

  /// The state of the interface has not been read yet.
  unknown,

  /// The switch is off (the interface can be used).
  off,

  /// The switch is on and the app may read the steps.
  ready,

  /// The switch is on, but the app of the interface is not installed.
  interfaceMissing,

  /// The switch is on, but the app of the interface is too old.
  interfaceOutdated,

  /// The switch is on, but the app may not read the steps: never asked,
  /// refused, taken away in the system, or the switch came from an imported
  /// backup (the access never comes from a file).
  accessMissing,

  /// The switch is on and the last comparison failed for a technical reason.
  failed,
}

/// Everything the screens need to know about the comparison with the health
/// interface: the wish of the user (settings), what the device says about the
/// interface and the access, and whether a comparison runs.
@immutable
final class HealthStepsStatus {
  const HealthStepsStatus({
    required this.enabled,
    required this.bodyEnabled,
    required this.sourceName,
    this.availability,
    this.access,
    this.syncing = false,
    this.failed = false,
    this.lastSyncAtUtc,
  });

  /// The wish: "Schritte aus Health übernehmen" is on.
  final bool enabled;

  /// Whether the module "Gewicht & Körper" is on (the steps are shown).
  final bool bodyEnabled;

  /// How the interface is called in texts, for example `Health Connect`.
  final String sourceName;

  /// What the device says about the interface; null until it was asked.
  final HealthAvailability? availability;

  /// Whether the app may read the steps; null until it was asked.
  final HealthAccess? access;

  /// A comparison is running right now.
  final bool syncing;

  /// The last comparison failed for a technical reason.
  final bool failed;

  /// When the last comparison finished (to the minute), null if none ran.
  final DateTime? lastSyncAtUtc;

  /// The state the screens show.
  HealthStepsCondition get condition {
    if (!bodyEnabled) {
      return HealthStepsCondition.hidden;
    }
    final state = availability;
    if (state == HealthAvailability.unsupported) {
      return HealthStepsCondition.hidden;
    }
    if (state == null) {
      // A switch that is off needs no state; an enabled one is shown
      // neutrally so it can still be switched off.
      return enabled
          ? HealthStepsCondition.unknown
          : HealthStepsCondition.hidden;
    }
    if (!enabled) {
      return HealthStepsCondition.off;
    }
    return switch (state) {
      HealthAvailability.missing => HealthStepsCondition.interfaceMissing,
      HealthAvailability.updateRequired =>
        HealthStepsCondition.interfaceOutdated,
      HealthAvailability.unsupported => HealthStepsCondition.hidden,
      HealthAvailability.available => switch (access) {
        HealthAccess.denied => HealthStepsCondition.accessMissing,
        HealthAccess.granted =>
          failed ? HealthStepsCondition.failed : HealthStepsCondition.ready,
        null => HealthStepsCondition.unknown,
      },
    };
  }

  /// Whether the switch and the state are shown at all.
  bool get visible => condition != HealthStepsCondition.hidden;

  /// Whether the values of Health reach the steps right now: the switch is
  /// on and the access is there.
  bool get reading =>
      condition == HealthStepsCondition.ready ||
      condition == HealthStepsCondition.failed;

  @override
  bool operator ==(Object other) =>
      other is HealthStepsStatus &&
      other.enabled == enabled &&
      other.bodyEnabled == bodyEnabled &&
      other.sourceName == sourceName &&
      other.availability == availability &&
      other.access == access &&
      other.syncing == syncing &&
      other.failed == failed &&
      other.lastSyncAtUtc == lastSyncAtUtc;

  @override
  int get hashCode => Object.hash(
    enabled,
    bodyEnabled,
    sourceName,
    availability,
    access,
    syncing,
    failed,
    lastSyncAtUtc,
  );

  @override
  String toString() =>
      'HealthStepsStatus(${condition.name}, enabled: $enabled, '
      'syncing: $syncing, last: $lastSyncAtUtc)';
}
