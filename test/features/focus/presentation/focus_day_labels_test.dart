import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The words of the focus card for a day that is not today (BS-93): what the
/// saved sessions of that day reached, in the past tense, and a day without a
/// session says so instead of "0 Min.".
void main() {
  final day = LocalDate(2026, 10, 1);

  FocusTodaySummary summary({
    int seconds = 0,
    int sessions = 0,
    int? goal = 25,
  }) => FocusTodaySummary(
    date: day,
    completedSeconds: seconds,
    sessionCount: sessions,
    goalMinutes: goal,
  );

  group('the caption (BS-93)', () {
    test('(BS-93) a day without a session says so, with or without a goal', () {
      expect(focusDayCaption(summary()), 'Keine Sitzung an diesem Tag');
      expect(
        focusDayCaption(summary(goal: null)),
        'Keine Sitzung an diesem Tag',
      );
    });

    test('(BS-93) below the goal: what was missing, in the past tense', () {
      expect(
        focusDayCaption(summary(seconds: 1200, sessions: 1)),
        'Es fehlten 5 Min. bis zum Tagesziel',
      );
      expect(
        focusDayCaption(summary(seconds: 61, sessions: 1)),
        'Es fehlten 24 Min. bis zum Tagesziel',
        reason: 'the minutes still missing are rounded up',
      );
    });

    test('(BS-93) the goal reached', () {
      expect(
        focusDayCaption(summary(seconds: 1500, sessions: 1)),
        'Tagesziel erreicht',
      );
      expect(
        focusDayCaption(summary(seconds: 1800, sessions: 2)),
        'Tagesziel erreicht',
      );
    });

    test('(BS-93) without a goal the sessions are counted', () {
      expect(
        focusDayCaption(summary(seconds: 600, sessions: 1, goal: null)),
        '1 Sitzung',
      );
      expect(
        focusDayCaption(summary(seconds: 1800, sessions: 3, goal: null)),
        '3 Sitzungen',
      );
    });

    test('(BS-93) never "heute"', () {
      for (final s in <FocusTodaySummary>[
        summary(),
        summary(seconds: 1200, sessions: 1),
        summary(seconds: 1500, sessions: 1),
        summary(seconds: 600, sessions: 2, goal: null),
      ]) {
        expect(focusDayCaption(s), isNot(contains('heute')));
        expect(focusDaySpoken(s), isNot(contains('heute')));
      }
    });
  });

  group('the spoken text (BS-93, AT34)', () {
    test('(BS-93, AT34) with a goal, without a goal, without a session', () {
      expect(
        focusDaySpoken(summary(seconds: 1200, sessions: 1)),
        'Fokuszeit an diesem Tag: 20 von 25 Minuten',
      );
      expect(
        focusDaySpoken(summary(seconds: 1200, sessions: 1, goal: null)),
        'Fokuszeit an diesem Tag: 20 Minuten',
      );
      expect(
        focusDaySpoken(summary()),
        'Fokuszeit an diesem Tag: keine Sitzung, Tagesziel 25 Minuten',
      );
      expect(
        focusDaySpoken(summary(goal: null)),
        'Fokuszeit an diesem Tag: keine Sitzung',
      );
    });
  });
}
