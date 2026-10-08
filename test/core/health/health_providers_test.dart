import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/health/application/health_providers.dart';
import 'package:self_improvement/core/health/domain/health_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_connect_steps_source.dart';
import 'package:self_improvement/core/health/platform/health_kit_steps_source.dart';
import 'package:self_improvement/core/health/platform/unsupported_health_steps_source.dart';

/// Which adapter the app uses on which platform (BS-97, D-031; BS-122,
/// D-034).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HealthStepsSource sourceFor(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(healthStepsSourceProvider);
  }

  test('Android uses Health Connect (BS-97)', () {
    expect(sourceFor(TargetPlatform.android), isA<HealthConnectStepsSource>());
  });

  test('iOS uses HealthKit (BS-122)', () {
    expect(sourceFor(TargetPlatform.iOS), isA<HealthKitStepsSource>());
  });

  test('every other platform has no adapter and reports "unsupported" '
      '(BS-97, BS-122)', () async {
    for (final platform in TargetPlatform.values) {
      if (platform == TargetPlatform.android ||
          platform == TargetPlatform.iOS) {
        continue;
      }
      final source = sourceFor(platform);
      expect(source, isA<UnsupportedHealthStepsSource>(), reason: '$platform');
      expect(
        await source.availability(),
        HealthAvailability.unsupported,
        reason: '$platform',
      );
    }
  });

  test('a host test without an override and without a native side reports '
      '"unsupported", so the switch stays hidden (BS-97, BS-122)', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      final source = sourceFor(platform);
      expect(
        await source.availability(),
        HealthAvailability.unsupported,
        reason: '$platform',
      );
    }
  });
}
