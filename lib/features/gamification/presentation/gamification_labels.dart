import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

// German texts of the streak and progress pages, as plain functions of the
// computed values (no widget, no state), so every wording rule is testable.
// Nothing here invents a number: every figure comes from the arguments.

/// `1 Tag` / `11 Tage`.
String daysText(int days) => days == 1 ? '1 Tag' : '$days Tage';

/// The unit next to the big streak number: `Tag in Folge` / `Tage in Folge`.
String streakUnit(int days) => days == 1 ? 'Tag in Folge' : 'Tage in Folge';

/// Spoken label of the streak entry on the dashboard.
String streakPillLabel(int days) => 'Streak: ${daysText(days)} in Folge';

/// The sentence under the big streak number.
///
/// Follows the streak rules: today without a fulfilled goal does not break a
/// running streak yet, so the text asks for one more goal instead of
/// announcing a loss.
String streakHint(StreakSummary summary) {
  if (summary.current == 0) {
    return summary.longest == 0
        ? 'Erreiche heute ein Tagesziel, um deine erste Serie zu starten.'
        : 'Erreiche heute ein Tagesziel, um eine neue Serie zu starten. '
              'Dein Rekord: ${daysText(summary.longest)}.';
  }
  if (!summary.todayActive) {
    return 'Erreiche heute noch ein Tagesziel, damit deine Serie '
        'weiterläuft.';
  }
  if (summary.current < summary.longest) {
    final missing = summary.longest - summary.current;
    return 'Noch ${daysText(missing)} bis zu deinem Rekord.';
  }
  return 'Das ist deine bisher längste Serie.';
}

/// The line under "Nächster Meilenstein": `14 Tage`, with ` – neuer Rekord`
/// when reaching it would beat the longest streak.
String milestoneSubtitle(StreakSummary summary) {
  final base = daysText(summary.nextMilestone);
  return summary.nextMilestone > summary.longest
      ? '$base – neuer Rekord'
      : base;
}

/// `11 / 14`: the current streak next to the next milestone.
String milestoneProgressText(StreakSummary summary) =>
    '${summary.current} / ${summary.nextMilestone}';

/// Spoken text of the milestone bar.
String milestoneSemanticLabel(StreakSummary summary) =>
    'Nächster Meilenstein: ${daysText(summary.nextMilestone)}, '
    'aktuell ${summary.current} von ${summary.nextMilestone}';

/// The status of one calendar day in words (never only a colour or a symbol).
String streakDayStatusText(StreakDay day) => switch (day.status) {
  StreakDayStatus.active => 'aktiver Tag',
  StreakDayStatus.inactive => 'kein Ziel erreicht',
  StreakDayStatus.todayOpen => 'noch offen',
  StreakDayStatus.beforeStart => 'vor dem Start, zählt nicht',
};

/// The full date of [day]: `Montag, 28. September`, with the year when it is
/// not the year of [today] (the week can reach into the previous year).
String streakDayDate(StreakDay day, LocalDate today) {
  final base = formatDateLong(day.date);
  return day.date.year == today.year ? base : '$base ${day.date.year}';
}

/// Spoken label of one day of the week strip, for example
/// `Heute, Samstag, 3. Oktober: aktiver Tag`.
String streakDayLabel(StreakDay day, LocalDate today) {
  final date = streakDayDate(day, today);
  final prefix = day.date == today ? 'Heute, ' : '';
  return '$prefix$date: ${streakDayStatusText(day)}';
}

/// The date under a day marker: `28.9.`.
String streakDayShortDate(StreakDay day) =>
    '${day.date.day}.${day.date.month}.';

/// `40 / 100 XP`.
String xpInLevelText(LevelProgress level) =>
    '${level.xpInLevel} / ${level.xpForNextLevel} XP';

/// `Noch 60 XP bis Level 5`.
String xpToNextLevelText(LevelProgress level) =>
    'Noch ${level.xpForNextLevel - level.xpInLevel} XP bis '
    'Level ${level.level + 1}';

/// `Gesamt: 1.340 XP`.
String totalXpText(int totalXp) => 'Gesamt: ${formatThousands(totalXp)} XP';

/// Spoken label of the level progress.
String levelSemanticLabel(LevelProgress level, int totalXp) =>
    'Level ${level.level}, ${xpInLevelText(level)}, '
    '${xpToNextLevelText(level)}, ${totalXpText(totalXp)}';

/// The short requirement shown on a badge tile. The numbers come from the
/// badge rules of the domain, so text and rule can never drift apart.
String badgeRequirement(BadgeId id) => switch (id) {
  BadgeId.firstStep => 'Erste Aktivität mit Punkten',
  BadgeId.oneWeek => '$badgeStreakDays Tage Streak',
  BadgeId.focusCollected => '${badgeFocusSeconds ~/ 60} Min. Fokuszeit',
};

/// The state of a badge in words.
String badgeStateText({required bool earned}) =>
    earned ? 'Erreicht' : 'Gesperrt';

/// Spoken label of a badge tile (title, full requirement from the domain,
/// state).
String badgeSemanticLabel(BadgeStatus badge) =>
    '${badge.title}, ${badge.description} ${badgeStateText(earned: badge.earned)}';
