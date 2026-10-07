import 'package:flutter/foundation.dart';

/// Persisted application settings (singleton).
@immutable
final class AppSettingsValue {
  const AppSettingsValue({
    required this.themeModeKey,
    required this.reduceMotion,
    required this.haptics,
    required this.notificationsEnabled,
    required this.rowVersion,
    this.lastKnownTimezone,
    this.healthStepsSyncEnabled = false,
    this.healthStepsLastSyncAtUtc,
  });

  /// `system`, `light`, `dark` or `oled`.
  final String themeModeKey;

  /// App switch in addition to the system setting.
  final bool reduceMotion;

  final bool haptics;

  /// Desired state only; the real OS permission is queried from the device.
  final bool notificationsEnabled;

  final String? lastKnownTimezone;

  /// Desired state of "Schritte aus Health übernehmen" (off by default). Like
  /// [notificationsEnabled] it is a wish only: whether the app may read is
  /// always asked from the device, so after an import the switch can be on
  /// without an access.
  final bool healthStepsSyncEnabled;

  /// When the last comparison with the health interface finished (UTC, on the
  /// minute); null until one ran. Informational only.
  final DateTime? healthStepsLastSyncAtUtc;

  final int rowVersion;
}
