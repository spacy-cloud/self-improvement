import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_xp_preview.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/focus_fixtures.dart';

FocusTodaySummary summary({
  int seconds = 0,
  int count = 0,
  int? goalMinutes = 60,
}) => FocusTodaySummary(
  date: LocalDate(2026, 10, 3),
  completedSeconds: seconds,
  sessionCount: count,
  goalMinutes: goalMinutes,
);

void main() {
  group('status text', () {
    test('names state and category, the confirmation has its own words', () {
      expect(
        focusStatusText(FocusStatus.running, FocusCategory.learning),
        'Läuft · Lernen',
      );
      expect(
        focusStatusText(FocusStatus.paused, FocusCategory.programming),
        'Pausiert · Programmieren',
      );
      expect(
        focusStatusText(
          FocusStatus.awaitingConfirmation,
          FocusCategory.meditation,
        ),
        'Geschafft!',
      );
    });
  });

  group('spoken duration', () {
    test('uses singular and plural and joins with "und"', () {
      expect(spokenDuration(0), '0 Sekunden');
      expect(spokenDuration(1), '1 Sekunde');
      expect(spokenDuration(45), '45 Sekunden');
      expect(spokenDuration(60), '1 Minute');
      expect(spokenDuration(612), '10 Minuten und 12 Sekunden');
      expect(spokenDuration(1500), '25 Minuten');
      expect(spokenDuration(3600), '1 Stunde');
      expect(spokenDuration(3725), '1 Stunde, 2 Minuten und 5 Sekunden');
      expect(spokenDuration(10800), '3 Stunden');
      expect(spokenDuration(-5), '0 Sekunden', reason: 'never negative');
    });

    test('the ring is read with the remaining time, not as a live count', () {
      final spoken = focusRingSpoken(
        status: FocusStatus.running,
        category: FocusCategory.learning,
        remainingSeconds: 612,
        plannedSeconds: 1500,
      );
      expect(
        spoken,
        'Fokus läuft, Lernen. Noch 10 Minuten und 12 Sekunden von '
        '25 Minuten.',
      );
      expect(
        focusRingSpoken(
          status: FocusStatus.paused,
          category: FocusCategory.reading,
          remainingSeconds: 600,
          plannedSeconds: 1500,
          pausedText: 'pausiert seit 2 Min.',
        ),
        contains('pausiert seit 2 Min.'),
      );
      expect(
        focusRingSpoken(
          status: FocusStatus.awaitingConfirmation,
          category: FocusCategory.learning,
          remainingSeconds: 0,
          plannedSeconds: 1500,
        ),
        contains('wartet auf deine Bestätigung'),
      );
    });
  });

  group('minute texts', () {
    test('the remaining time is rounded UP to whole minutes', () {
      expect(remainingMinutesText(1500), 'Noch 25 Min.');
      expect(remainingMinutesText(1441), 'Noch 25 Min.');
      expect(remainingMinutesText(1440), 'Noch 24 Min.');
      expect(remainingMinutesText(61), 'Noch 2 Min.');
      expect(remainingMinutesText(1), 'Noch 1 Min.');
      expect(remainingMinutesText(0), 'Zeit abgelaufen');
      expect(remainingMinutesText(-3), 'Zeit abgelaufen');
    });

    test('the pause is described in minutes and hours', () {
      expect(pausedSinceText(Duration.zero), 'gerade pausiert');
      expect(pausedSinceText(const Duration(seconds: 59)), 'gerade pausiert');
      expect(
        pausedSinceText(const Duration(seconds: 60)),
        'pausiert seit 1 Min.',
      );
      expect(
        pausedSinceText(const Duration(minutes: 2, seconds: 30)),
        'pausiert seit 2 Min.',
      );
      expect(
        pausedSinceText(const Duration(minutes: 60)),
        'pausiert seit 1 Std.',
      );
      expect(
        pausedSinceText(const Duration(minutes: 65)),
        'pausiert seit 1 Std. 5 Min.',
      );
      expect(pausedSinceText(const Duration(minutes: -3)), 'gerade pausiert');
    });

    test('planned minutes for screen readers', () {
      expect(plannedMinutesSpoken(1), '1 Minute');
      expect(plannedMinutesSpoken(25), '25 Minuten');
    });
  });

  group('today texts', () {
    test('the goal progress is told in words', () {
      expect(
        focusTodayCaption(summary(seconds: 2700, count: 2)),
        'Noch 15 Min. bis zu deinem Tagesziel',
      );
      expect(
        focusTodayCaption(summary(seconds: 3600, count: 2)),
        'Tagesziel erreicht',
      );
      expect(
        focusTodayCaption(summary(seconds: 5400, count: 3)),
        'Tagesziel erreicht',
        reason: 'more than the goal is still just reached',
      );
    });

    test('without a goal only the sessions are counted', () {
      expect(
        focusTodayCaption(summary(goalMinutes: null)),
        'Noch keine Sitzung heute',
      );
      expect(
        focusTodayCaption(summary(goalMinutes: null, seconds: 600, count: 1)),
        '1 Sitzung heute',
      );
      expect(
        focusTodayCaption(summary(goalMinutes: null, seconds: 900, count: 3)),
        '3 Sitzungen heute',
      );
    });

    test('the spoken summary names minutes and goal', () {
      expect(
        focusTodaySpoken(summary(seconds: 2700)),
        'Fokuszeit heute: 45 von 60 Minuten',
      );
      expect(
        focusTodaySpoken(summary(seconds: 2700, goalMinutes: null)),
        'Fokuszeit heute: 45 Minuten',
      );
    });

    test('the save effect shows before and after against the goal', () {
      expect(
        focusSaveEffectText(
          savedSeconds: 1500,
          today: summary(seconds: 2700, count: 2),
        ),
        'Speichern zählt 25 Min. zu deinem Tagesziel (45 → 70 von 60 Min.).',
      );
      expect(
        focusSaveEffectText(
          savedSeconds: 1500,
          today: summary(seconds: 0, goalMinutes: null),
        ),
        'Speichern zählt 25 Min. zu deiner Fokuszeit heute (0 → 25 Min.).',
      );
      expect(
        focusSaveEffectText(
          savedSeconds: 45,
          today: summary(seconds: 590, count: 1),
        ),
        'Speichern zählt 45 Sek. zu deinem Tagesziel (9 → 10 von 60 Min.).',
      );
    });
  });

  group('XP preview (G01)', () {
    final qualifying = focusSession(
      accumulated: 1500,
      eligible: true,
      status: FocusStatus.completed,
    );

    test('is hidden while gamification is off', () {
      expect(
        previewFocusXp(
          gamificationEnabled: false,
          savedSeconds: 1500,
          completedToday: const [],
        ),
        FocusXpOutcome.hidden,
      );
      expect(focusXpText(FocusXpOutcome.hidden), isNull);
    });

    test('299 seconds earn nothing, 300 earn the points', () {
      FocusXpOutcome outcomeFor(int seconds) => previewFocusXp(
        gamificationEnabled: true,
        savedSeconds: seconds,
        completedToday: const [],
      );
      expect(outcomeFor(299), FocusXpOutcome.belowMinimum);
      expect(outcomeFor(300), FocusXpOutcome.awarded);
      expect(
        focusXpText(FocusXpOutcome.belowMinimum),
        'Unter 5 Minuten: Die Zeit wird gespeichert, es gibt keine XP.',
      );
      expect(focusXpText(FocusXpOutcome.awarded), '+10 XP beim Speichern');
    });

    test('only the first four qualifying sessions of a day are rewarded', () {
      FocusXpOutcome withSessions(int count) => previewFocusXp(
        gamificationEnabled: true,
        savedSeconds: 1500,
        completedToday: List.filled(count, qualifying),
      );
      expect(withSessions(3), FocusXpOutcome.awarded);
      expect(withSessions(4), FocusXpOutcome.limitReached);
      expect(
        focusXpText(FocusXpOutcome.limitReached),
        'Für heute gibt es keine weiteren Fokus-XP.',
      );
    });

    test('sessions that did not qualify do not use up the slots', () {
      final tooShort = focusSession(
        accumulated: 299,
        eligible: true,
        status: FocusStatus.completed,
      );
      final notEligible = focusSession(
        accumulated: 1500,
        eligible: false,
        status: FocusStatus.completed,
      );
      expect(
        previewFocusXp(
          gamificationEnabled: true,
          savedSeconds: 1500,
          completedToday: [
            tooShort,
            tooShort,
            notEligible,
            notEligible,
            qualifying,
          ],
        ),
        FocusXpOutcome.awarded,
      );
    });
  });

  group('dashboard card texts', () {
    test('an open session is told by state, category and time', () {
      expect(focusOpenCardValue(FocusStatus.running), 'Läuft');
      expect(focusOpenCardValue(FocusStatus.paused), 'Pausiert');
      expect(
        focusOpenCardValue(FocusStatus.awaitingConfirmation),
        'Geschafft!',
      );
      expect(
        focusOpenCardSubtitle(
          status: FocusStatus.running,
          category: FocusCategory.learning,
          remainingSeconds: 612,
        ),
        'Lernen · Noch 11 Min.',
      );
      expect(
        focusOpenCardSubtitle(
          status: FocusStatus.paused,
          category: FocusCategory.reading,
          remainingSeconds: 612,
        ),
        'Lesen · 10:12 übrig',
      );
      expect(
        focusOpenCardSubtitle(
          status: FocusStatus.awaitingConfirmation,
          category: FocusCategory.other,
          remainingSeconds: 0,
        ),
        'Sonstiges · Bestätigung offen',
      );
    });

    test('the resume action asks for confirmation once the time is over', () {
      expect(focusResumeLabel(FocusStatus.running), 'Fokus fortsetzen');
      expect(focusResumeLabel(FocusStatus.paused), 'Fokus fortsetzen');
      expect(
        focusResumeLabel(FocusStatus.awaitingConfirmation),
        'Sitzung bestätigen',
      );
    });
  });
}
