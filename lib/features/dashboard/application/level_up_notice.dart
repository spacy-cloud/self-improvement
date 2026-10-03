import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A level reached today, waiting to be shown on the dashboard.
@immutable
final class LevelUpNotice {
  const LevelUpNotice({required this.levelUp, required this.day});

  /// The level and the total XP after the commit that reached it.
  final LevelUp levelUp;

  /// The day it happened; the notice does not outlive that day.
  final LocalDate day;
}

/// Remembers the last level-up of this app session until the user dismisses it.
///
/// It only reacts to the post-commit level-up events of the engine
/// ([levelUpProvider]): a rolled back or failed command emits nothing, a
/// correction that removes XP never raises one, and because the notice lives
/// in memory only, a restart can never show an old level-up again. The notice
/// is deliberately a quiet card on the dashboard and not a snack bar: a snack
/// bar would replace the "Rückgängig" offer of the save that earned the level.
class LevelUpNoticeController extends Notifier<LevelUpNotice?> {
  @override
  LevelUpNotice? build() {
    ref.listen<AsyncValue<LevelUp>>(levelUpProvider, (previous, next) {
      final levelUp = next.value;
      if (levelUp != null) {
        state = LevelUpNotice(levelUp: levelUp, day: ref.read(todayProvider));
      }
    });
    return null;
  }

  /// Hides the notice ("Hinweis schließen").
  void dismiss() => state = null;
}

/// The level-up notice of this session, or `null`.
final levelUpNoticeProvider =
    NotifierProvider<LevelUpNoticeController, LevelUpNotice?>(
      LevelUpNoticeController.new,
    );
