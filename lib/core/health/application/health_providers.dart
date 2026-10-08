import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_connect_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_kit_steps_source.dart';
import 'package:self_improvement/core/health/platform/unsupported_health_steps_source.dart';

/// The health interface of the device (BS-97). Overridden in tests with
/// `FakeHealthStepsSource`.
///
/// On Android it is Health Connect (`HealthConnectStepsSource`, decision
/// D-031); on iOS it is HealthKit (`HealthKitStepsSource`, decision D-034,
/// BS-122); on every other platform the app has no adapter and reports
/// "unsupported", so nothing reads and the switch stays hidden. A host test
/// without an override runs as Android but has no native side behind the
/// channel, which is reported as "unsupported" too; the same holds for an iOS
/// build without the HealthKit entitlement.
final healthStepsSourceProvider = Provider<HealthStepsSource>(
  (ref) => switch (defaultTargetPlatform) {
    TargetPlatform.android => HealthConnectStepsSource(),
    TargetPlatform.iOS => HealthKitStepsSource(),
    _ => const UnsupportedHealthStepsSource(),
  },
);
