import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_xp_preview.dart';

/// The remaining time of the RUNNING session rounded up to whole minutes, or
/// null when no session runs. The countdown emits every second, but this value
/// only changes once a minute, so the widgets that watch it (dashboard card,
/// start screen) rebuild once a minute instead of every second.
final focusRemainingMinutesProvider = Provider.autoDispose<int?>((ref) {
  final countdown = ref.watch(focusCountdownProvider).value;
  if (countdown == null || !countdown.isRunning) {
    return null;
  }
  return (countdown.remainingSeconds + 59) ~/ 60;
});

/// Whether the gamification module is switched on right now (decides whether
/// the XP hints are shown at all).
final focusGamificationEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(moduleStatusesProvider).value?[ModuleId.gamification] ?? false,
);

/// What saving a session of the given length earns, for the XP hint of the
/// confirmation and of the "Beenden" sheet. Family key: saved seconds.
final focusXpOutcomeProvider = Provider.autoDispose.family<FocusXpOutcome, int>(
  (ref, savedSeconds) {
    final today = ref.watch(focusSessionsTodayProvider).value ?? const [];
    return previewFocusXp(
      gamificationEnabled: ref.watch(focusGamificationEnabledProvider),
      savedSeconds: savedSeconds,
      completedToday: [for (final entry in today) entry.session],
    );
  },
);
