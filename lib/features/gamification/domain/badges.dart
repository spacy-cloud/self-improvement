import 'package:flutter/foundation.dart';

/// Longest global streak (in days) that earns [BadgeId.oneWeek].
const int badgeStreakDays = 7;

/// Completed focus time (in seconds, one hour) that earns
/// [BadgeId.focusCollected].
const int badgeFocusSeconds = 3600;

/// The three badges. The string [key] is a stable identifier for the UI.
enum BadgeId {
  firstStep('first_step'),
  oneWeek('one_week'),
  focusCollected('focus_collected');

  const BadgeId(this.key);

  final String key;
}

/// A badge with its current state. Badges are never stored: they are derived
/// from the current data, so deleting data can lock a badge again.
@immutable
final class BadgeStatus {
  const BadgeStatus({
    required this.id,
    required this.title,
    required this.description,
    required this.earned,
  });

  final BadgeId id;

  /// German display title.
  final String title;

  /// German explanation of the requirement.
  final String description;

  final bool earned;

  @override
  bool operator ==(Object other) =>
      other is BadgeStatus &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      other.earned == earned;

  @override
  int get hashCode => Object.hash(id, title, description, earned);

  @override
  String toString() => 'BadgeStatus(${id.key}, earned: $earned)';
}

/// The three badges in a fixed order, evaluated against the current data.
///
/// Inputs the data layer aggregates:
/// - [hasEligibleActivity]: at least one active activity that was eligible for
///   XP when it was created (for example any award exists, or any record with
///   its eligibility flag set);
/// - [longestStreak]: `StreakSummary.longest` of the global streak;
/// - [completedFocusSeconds]: total of `accumulated_seconds` over all
///   completed focus sessions.
///
/// "Erster Schritt": at least one eligible activity. "Eine Woche dran":
/// longest streak of at least 7 days. "Fokus gesammelt": at least 3600
/// completed focus seconds in total.
List<BadgeStatus> computeBadges({
  required bool hasEligibleActivity,
  required int longestStreak,
  required int completedFocusSeconds,
}) => List.unmodifiable([
  BadgeStatus(
    id: BadgeId.firstStep,
    title: 'Erster Schritt',
    description: 'Erfasse mindestens eine Aktivität, die Punkte bringt.',
    earned: hasEligibleActivity,
  ),
  BadgeStatus(
    id: BadgeId.oneWeek,
    title: 'Eine Woche dran',
    description: 'Erreiche eine Serie von mindestens 7 Tagen.',
    earned: longestStreak >= badgeStreakDays,
  ),
  BadgeStatus(
    id: BadgeId.focusCollected,
    title: 'Fokus gesammelt',
    description: 'Sammle insgesamt mindestens 60 Minuten Fokuszeit.',
    earned: completedFocusSeconds >= badgeFocusSeconds,
  ),
]);
