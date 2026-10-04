import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';

void main() {
  List<BadgeStatus> badges({
    bool eligible = false,
    int streak = 0,
    int focusSeconds = 0,
  }) => computeBadges(
    hasEligibleActivity: eligible,
    longestStreak: streak,
    completedFocusSeconds: focusSeconds,
  );

  Map<BadgeId, bool> earned(List<BadgeStatus> list) => {
    for (final badge in list) badge.id: badge.earned,
  };

  group('catalogue', () {
    test('exactly three badges with stable ids and German titles', () {
      final list = badges();
      expect(list, hasLength(3));
      expect(list.map((badge) => badge.id.key), [
        'first_step',
        'one_week',
        'focus_collected',
      ]);
      expect(list.map((badge) => badge.title), [
        'Erster Schritt',
        'Eine Woche dran',
        'Fokus gesammelt',
      ]);
      for (final badge in list) {
        expect(badge.description, isNotEmpty);
      }
    });

    test('the list is the same for every input and cannot be modified', () {
      expect(
        badges().map((badge) => badge.id),
        badges(
          eligible: true,
          streak: 99,
          focusSeconds: 99999,
        ).map((badge) => badge.id),
      );
      expect(badges().clear, throwsUnsupportedError);
    });

    test('a fresh profile has no badge', () {
      expect(earned(badges()).values, everyElement(isFalse));
    });
  });

  group('Erster Schritt', () {
    test('needs at least one eligible activity', () {
      expect(earned(badges())[BadgeId.firstStep], isFalse);
      expect(earned(badges(eligible: true))[BadgeId.firstStep], isTrue);
    });
  });

  group('Eine Woche dran', () {
    test('needs a longest streak of at least 7 days', () {
      for (final (streak, expected) in [
        (0, false),
        (1, false),
        (6, false),
        (7, true),
        (8, true),
        (365, true),
      ]) {
        expect(
          earned(badges(streak: streak))[BadgeId.oneWeek],
          expected,
          reason: '$streak days',
        );
      }
    });
  });

  group('Fokus gesammelt', () {
    test('needs at least 3600 completed focus seconds in total', () {
      for (final (seconds, expected) in [
        (0, false),
        (300, false),
        (3599, false),
        (3600, true),
        (3601, true),
        (86400, true),
      ]) {
        expect(
          earned(badges(focusSeconds: seconds))[BadgeId.focusCollected],
          expected,
          reason: '$seconds s',
        );
      }
    });
  });

  group('independence and data deletion', () {
    test('each badge depends only on its own input', () {
      expect(earned(badges(eligible: true)), {
        BadgeId.firstStep: true,
        BadgeId.oneWeek: false,
        BadgeId.focusCollected: false,
      });
      expect(earned(badges(streak: 7)), {
        BadgeId.firstStep: false,
        BadgeId.oneWeek: true,
        BadgeId.focusCollected: false,
      });
      expect(earned(badges(focusSeconds: 3600)), {
        BadgeId.firstStep: false,
        BadgeId.oneWeek: false,
        BadgeId.focusCollected: true,
      });
      expect(
        earned(badges(eligible: true, streak: 7, focusSeconds: 3600)).values,
        everyElement(isTrue),
      );
    });

    test('a badge is locked again when the data behind it is gone', () {
      final full = badges(eligible: true, streak: 9, focusSeconds: 4000);
      expect(earned(full).values, everyElement(isTrue));
      final afterDeletion = badges(
        eligible: false,
        streak: 6,
        focusSeconds: 3500,
      );
      expect(earned(afterDeletion).values, everyElement(isFalse));
    });

    test('the same inputs always give the same result', () {
      expect(
        badges(eligible: true, streak: 7, focusSeconds: 3599),
        badges(eligible: true, streak: 7, focusSeconds: 3599),
      );
    });
  });
}
