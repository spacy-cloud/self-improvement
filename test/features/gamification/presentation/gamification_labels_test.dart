import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';
import 'package:self_improvement/features/gamification/domain/level.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

StreakSummary _streak({
  required int current,
  required int longest,
  bool todayActive = true,
  int? next,
}) => StreakSummary(
  current: current,
  longest: longest,
  activeDays: longest,
  nextMilestone: next ?? nextStreakMilestone(current),
  todayActive: todayActive,
  lastSevenDays: const [],
);

void main() {
  group('days and units', () {
    test('singular only for exactly one day', () {
      expect(daysText(0), '0 Tage');
      expect(daysText(1), '1 Tag');
      expect(daysText(2), '2 Tage');
      expect(streakUnit(1), 'Tag in Folge');
      expect(streakUnit(0), 'Tage in Folge');
      expect(streakUnit(11), 'Tage in Folge');
      expect(streakPillLabel(1), 'Streak: 1 Tag in Folge');
      expect(streakPillLabel(11), 'Streak: 11 Tage in Folge');
    });
  });

  group('streakHint (G02, AT22)', () {
    test('no streak yet asks for the first goal, never blames', () {
      expect(
        streakHint(_streak(current: 0, longest: 0, todayActive: false)),
        'Erreiche heute ein Tagesziel, um deine erste Serie zu starten.',
      );
    });

    test('a broken streak names the record', () {
      expect(
        streakHint(_streak(current: 0, longest: 5, todayActive: false)),
        'Erreiche heute ein Tagesziel, um eine neue Serie zu starten. '
        'Dein Rekord: 5 Tage.',
      );
    });

    test('an open today keeps the streak alive and says what to do', () {
      expect(
        streakHint(_streak(current: 3, longest: 3, todayActive: false)),
        'Erreiche heute noch ein Tagesziel, damit deine Serie weiterläuft.',
      );
    });

    test('below the record it counts the days to it', () {
      expect(
        streakHint(_streak(current: 4, longest: 5)),
        'Noch 1 Tag bis zu deinem Rekord.',
      );
      expect(
        streakHint(_streak(current: 4, longest: 14)),
        'Noch 10 Tage bis zu deinem Rekord.',
      );
    });

    test('at the record it says so', () {
      expect(
        streakHint(_streak(current: 4, longest: 4)),
        'Das ist deine bisher längste Serie.',
      );
    });
  });

  group('milestone', () {
    test('adds "neuer Rekord" only when it would beat the longest streak', () {
      expect(
        milestoneSubtitle(_streak(current: 4, longest: 5)),
        '7 Tage – neuer Rekord',
      );
      expect(milestoneSubtitle(_streak(current: 11, longest: 14)), '14 Tage');
      expect(
        milestoneSubtitle(_streak(current: 0, longest: 0)),
        '3 Tage – neuer Rekord',
      );
    });

    test('works beyond 100 days (every hundred)', () {
      final summary = _streak(current: 150, longest: 150);
      expect(summary.nextMilestone, 200);
      expect(milestoneSubtitle(summary), '200 Tage – neuer Rekord');
      expect(milestoneProgressText(summary), '150 / 200');
    });

    test('progress text and spoken label carry the same numbers', () {
      final summary = _streak(current: 4, longest: 5);
      expect(milestoneProgressText(summary), '4 / 7');
      expect(
        milestoneSemanticLabel(summary),
        'Nächster Meilenstein: 7 Tage, aktuell 4 von 7',
      );
    });
  });

  group('days of the week strip (accessible status)', () {
    final today = LocalDate(2026, 10, 3);
    StreakDay day(LocalDate date, StreakDayStatus status) =>
        StreakDay(date: date, status: status);

    test('every status has its own words', () {
      expect(
        streakDayStatusText(day(today, StreakDayStatus.active)),
        'aktiver Tag',
      );
      expect(
        streakDayStatusText(day(today, StreakDayStatus.inactive)),
        'kein Ziel erreicht',
      );
      expect(
        streakDayStatusText(day(today, StreakDayStatus.todayOpen)),
        'noch offen',
      );
      expect(
        streakDayStatusText(day(today, StreakDayStatus.beforeStart)),
        'vor dem Start, zählt nicht',
      );
    });

    test('the spoken label has the concrete date and marks today', () {
      expect(
        streakDayLabel(day(today, StreakDayStatus.active), today),
        'Heute, Samstag, 3. Oktober: aktiver Tag',
      );
      expect(
        streakDayLabel(
          day(LocalDate(2026, 9, 28), StreakDayStatus.inactive),
          today,
        ),
        'Montag, 28. September: kein Ziel erreicht',
      );
      expect(
        streakDayLabel(day(today, StreakDayStatus.todayOpen), today),
        'Heute, Samstag, 3. Oktober: noch offen',
      );
    });

    test('a week reaching into the previous year names the year', () {
      final newYear = LocalDate(2027, 1, 2);
      expect(
        streakDayDate(
          day(LocalDate(2026, 12, 31), StreakDayStatus.active),
          newYear,
        ),
        'Donnerstag, 31. Dezember 2026',
      );
      expect(
        streakDayDate(
          day(LocalDate(2027, 1, 1), StreakDayStatus.active),
          newYear,
        ),
        'Freitag, 1. Januar',
      );
    });

    test('the short date under the marker is day and month', () {
      expect(
        streakDayShortDate(day(LocalDate(2026, 9, 28), StreakDayStatus.active)),
        '28.9.',
      );
      expect(
        streakDayShortDate(day(LocalDate(2026, 10, 3), StreakDayStatus.active)),
        '3.10.',
      );
    });
  });

  group('level and XP texts (G02)', () {
    test('99, 100 and 250 XP', () {
      final l99 = levelFor(99);
      expect(xpInLevelText(l99), '99 / 100 XP');
      expect(xpToNextLevelText(l99), 'Noch 1 XP bis Level 2');
      final l100 = levelFor(100);
      expect(xpInLevelText(l100), '0 / 100 XP');
      expect(xpToNextLevelText(l100), 'Noch 100 XP bis Level 3');
      final l250 = levelFor(250);
      expect(xpInLevelText(l250), '50 / 100 XP');
      expect(xpToNextLevelText(l250), 'Noch 50 XP bis Level 4');
    });

    test('the total uses the German thousands separator', () {
      expect(totalXpText(0), 'Gesamt: 0 XP');
      expect(totalXpText(1340), 'Gesamt: 1.340 XP');
    });

    test('the spoken label has level, progress and total', () {
      expect(
        levelSemanticLabel(levelFor(250), 250),
        'Level 3, 50 / 100 XP, Noch 50 XP bis Level 4, Gesamt: 250 XP',
      );
    });
  });

  group('badges', () {
    test('the requirement texts come from the badge rules', () {
      expect(
        badgeRequirement(BadgeId.firstStep),
        'Erste Aktivität mit Punkten',
      );
      expect(badgeRequirement(BadgeId.oneWeek), '$badgeStreakDays Tage Streak');
      expect(
        badgeRequirement(BadgeId.focusCollected),
        '${badgeFocusSeconds ~/ 60} Min. Fokuszeit',
      );
      expect(badgeRequirement(BadgeId.oneWeek), '7 Tage Streak');
      expect(badgeRequirement(BadgeId.focusCollected), '60 Min. Fokuszeit');
    });

    test('the state is a word and the spoken label has the full requirement', () {
      expect(badgeStateText(earned: true), 'Erreicht');
      expect(badgeStateText(earned: false), 'Gesperrt');
      final locked = computeBadges(
        hasEligibleActivity: false,
        longestStreak: 3,
        completedFocusSeconds: 0,
      );
      expect(
        badgeSemanticLabel(locked[1]),
        'Eine Woche dran, Erreiche eine Serie von mindestens 7 Tagen. Gesperrt',
      );
    });
  });
}
