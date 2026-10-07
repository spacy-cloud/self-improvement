import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';

/// The adapter for a device without a health interface the app supports (every
/// platform except Android in this version). It reports
/// [HealthAvailability.unsupported], so the switch stays hidden and nothing
/// reads or asks.
@immutable
final class UnsupportedHealthStepsSource implements HealthStepsSource {
  const UnsupportedHealthStepsSource();

  @override
  String get displayName => 'Health';

  @override
  Future<HealthAvailability> availability() async =>
      HealthAvailability.unsupported;

  @override
  Future<HealthAccess> access() async => HealthAccess.denied;

  @override
  Future<HealthAccess> requestAccess() async => HealthAccess.denied;

  @override
  Future<int?> totalSteps({
    required DateTime startUtc,
    required DateTime endUtc,
  }) => Future<int?>.error(
    const HealthStepsException(HealthFailureKind.unavailable),
  );

  @override
  Future<bool> openInstallPage() async => false;

  @override
  Future<bool> openAccessSettings() async => false;
}
