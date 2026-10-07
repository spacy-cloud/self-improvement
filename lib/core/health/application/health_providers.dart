import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/unsupported_health_steps_source.dart';

/// The health interface of the device (BS-97). Overridden in tests with
/// `FakeHealthStepsSource`. The default reports "unsupported": nothing reads
/// and the switch stays hidden until an adapter for the platform exists.
final healthStepsSourceProvider = Provider<HealthStepsSource>(
  (ref) => const UnsupportedHealthStepsSource(),
);
