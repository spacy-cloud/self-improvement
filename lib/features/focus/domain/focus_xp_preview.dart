/// What saving a focus session earns (pure): the preview behind the XP hints of
/// the confirmation screen and of the "Beenden" sheet.
library;

import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';

/// What saving does for the experience points.
enum FocusXpOutcome {
  /// Gamification is switched off: XP are not mentioned at all.
  hidden,

  /// Shorter than five minutes: the time is saved, no XP.
  belowMinimum,

  /// Today's four XP sessions are used up: no further XP today.
  limitReached,

  /// The save is expected to earn [XpRules.focusPoints].
  awarded,
}

/// What saving a session of [savedSeconds] earns, given the sessions already
/// completed today. Mirrors the XP rule (the first four eligible sessions of at
/// least five minutes per day), so the hint never promises more than the
/// projection will award.
FocusXpOutcome previewFocusXp({
  required bool gamificationEnabled,
  required int savedSeconds,
  required Iterable<FocusSession> completedToday,
}) {
  if (!gamificationEnabled) {
    return FocusXpOutcome.hidden;
  }
  if (!focusSecondsQualifyForXp(savedSeconds)) {
    return FocusXpOutcome.belowMinimum;
  }
  final awardedAlready = completedToday
      .where(
        (session) =>
            session.gamificationEligible &&
            focusSecondsQualifyForXp(session.accumulatedSeconds),
      )
      .length;
  return awardedAlready >= XpRules.focusMaxAwardsPerDay
      ? FocusXpOutcome.limitReached
      : FocusXpOutcome.awarded;
}
