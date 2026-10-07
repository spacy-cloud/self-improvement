import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_connect_steps_source.dart';
import 'package:self_improvement/core/health/platform/unsupported_health_steps_source.dart';

/// The health interface of the device (BS-97). Overridden in tests with
/// `FakeHealthStepsSource`.
///
/// On Android it is Health Connect (`HealthConnectStepsSource`, decision
/// D-031); on every other platform the app has no adapter yet and reports
/// "unsupported", so nothing reads and the switch stays hidden. A host test
/// without an override runs as Android but has no native side behind the
/// channel, which is reported as "unsupported" too.
final healthStepsSourceProvider = Provider<HealthStepsSource>(
  (ref) => defaultTargetPlatform == TargetPlatform.android
      ? HealthConnectStepsSource()
      : const UnsupportedHealthStepsSource(),
);
