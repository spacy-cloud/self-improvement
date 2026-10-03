import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/app_theme.dart';
import 'package:self_improvement/core/providers/core_providers.dart';

/// The chosen theme. The app shell feeds it into `MaterialApp`
/// (`AppThemeMode.themeMode`, `AppTheme.light/dark/oled`), so a change in the
/// settings reaches the whole app as soon as it is committed. While the
/// settings load (or hold an unknown key) the app follows the system.
final appThemeModeProvider = Provider<AppThemeMode>((ref) {
  final key = ref.watch(appSettingsProvider).value?.themeModeKey;
  return AppThemeMode.tryParse(key) ?? AppThemeMode.system;
});

/// The app switch "Reduzierte Bewegung" (in addition to the system setting).
/// The app shell passes it to `ReducedMotionScope`.
final reduceMotionProvider = Provider<bool>(
  (ref) => ref.watch(appSettingsProvider).value?.reduceMotion ?? false,
);

/// The switch "Haptisches Feedback" (on by default).
final hapticsEnabledProvider = Provider<bool>(
  (ref) => ref.watch(appSettingsProvider).value?.haptics ?? true,
);

/// Haptic feedback that respects the setting. Screens call [confirm] after an
/// action was committed (check-off, quick add, switch) and never decide on
/// their own whether to vibrate.
class AppHaptics {
  AppHaptics(this._isEnabled);

  final bool Function() _isEnabled;

  /// A light tap that confirms a committed action; does nothing when haptic
  /// feedback is switched off. With [force] the setting is not asked (right
  /// after the user switched haptic feedback on, so the tap shows what it
  /// does). Devices without a vibrator and tests never fail because of it.
  Future<void> confirm({bool force = false}) async {
    if (!force && !_isEnabled()) {
      return;
    }
    try {
      await HapticFeedback.lightImpact();
    } on PlatformException {
      // No haptic hardware: nothing to confirm.
    } on MissingPluginException {
      // No platform implementation (host tests).
    }
  }
}

/// The haptics helper; reads the current setting at every call.
final appHapticsProvider = Provider<AppHaptics>(
  (ref) => AppHaptics(() => ref.read(hapticsEnabledProvider)),
);
