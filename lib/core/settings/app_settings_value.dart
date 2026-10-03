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
  });

  /// `system`, `light`, `dark` or `oled`.
  final String themeModeKey;

  /// App switch in addition to the system setting.
  final bool reduceMotion;

  final bool haptics;

  /// Desired state only; the real OS permission is queried from the device.
  final bool notificationsEnabled;

  final String? lastKnownTimezone;
  final int rowVersion;
}
