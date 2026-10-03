import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/focus_fixtures.dart';

Matcher invalidState() => throwsA(
  isA<ConflictFailure>().having(
    (f) => f.kind,
    'kind',
    ConflictKind.invalidState,
  ),
);

void main() {
  group('computeFocusElapsed (running)', () {
    test('starts at zero and counts whole seconds (floor)', () {
      final session = focusSession();
      expect(computeFocusElapsed(session, t0).elapsedSeconds, 0);
      expect(
        computeFocusElapsed(session, after(0, millis: 999)).elapsedSeconds,
        0,
      );
      expect(computeFocusElapsed(session, after(1)).elapsedSeconds, 1);
      final later = computeFocusElapsed(session, after(600));
      expect(later.elapsedSeconds, 600);
      expect(later.remainingSeconds, 900);
      expect(later.clockAnomaly, isFalse);
    });

    test('adds the segment to the accumulated seconds', () {
      final session = focusSession(accumulated: 300);
      final elapsed = computeFocusElapsed(session, after(120));
      expect(elapsed.elapsedSeconds, 420);
      expect(elapsed.remainingSeconds, 1080);
    });

    test('never exceeds the planned time (clamp)', () {
      final session = focusSession(planned: 300, accumulated: 100);
      final exactly = computeFocusElapsed(session, after(200));
      expect(exactly.elapsedSeconds, 300);
      expect(exactly.remainingSeconds, 0);
      expect(exactly.reachedPlan, isTrue);
      final beyond = computeFocusElapsed(session, after(86400));
      expect(beyond.elapsedSeconds, 300);
      expect(beyond.remainingSeconds, 0);
      expect(
        computeFocusElapsed(session, after(199)).reachedPlan,
        isFalse,
        reason: 'one second before the end',
      );
    });

    test('a negative difference counts as 0 and sets the anomaly flag', () {
      final session = focusSession(accumulated: 200);
      final back = computeFocusElapsed(
        session,
        t0.subtract(const Duration(hours: 1)),
      );
      expect(back.elapsedSeconds, 200, reason: 'no negative segment time');
      expect(back.remainingSeconds, 1300);
      expect(back.clockAnomaly, isTrue);
      expect(
        computeFocusElapsed(
          session,
          t0.subtract(const Duration(milliseconds: 1)),
        ).clockAnomaly,
        isTrue,
        reason: 'any negative difference',
      );
      expect(
        computeFocusElapsed(session, t0).clockAnomaly,
        isFalse,
        reason: 'equal instants are not an anomaly',
      );
    });

    test('elapsed is never negative even for a corrupt accumulated value', () {
      final session = focusSession(accumulated: -50);
      expect(computeFocusElapsed(session, t0).elapsedSeconds, 0);
    });

    test('a corrupt accumulated value above the plan is clamped', () {
      final session = focusSession(planned: 300, accumulated: 999);
      final elapsed = computeFocusElapsed(session, t0);
      expect(elapsed.elapsedSeconds, 300);
      expect(elapsed.remainingSeconds, 0);
    });
  });

  group('computeFocusElapsed (other states)', () {
    test('paused: the accumulated value, independent of the time', () {
      final session = focusSession(
        status: FocusStatus.paused,
        accumulated: 612,
      );
      expect(computeFocusElapsed(session, t0).elapsedSeconds, 612);
      expect(computeFocusElapsed(session, after(99999)).elapsedSeconds, 612);
      expect(computeFocusElapsed(session, after(99999)).remainingSeconds, 888);
    });

    test('awaiting confirmation: the planned time', () {
      final session = focusSession(
        status: FocusStatus.awaitingConfirmation,
        accumulated: 0,
      );
      final elapsed = computeFocusElapsed(session, t0);
      expect(elapsed.elapsedSeconds, 1500);
      expect(elapsed.remainingSeconds, 0);
    });

    test('completed and discarded keep their stored value', () {
      expect(
        computeFocusElapsed(
          focusSession(status: FocusStatus.completed, accumulated: 420),
          t0,
        ).elapsedSeconds,
        420,
      );
      expect(
        computeFocusElapsed(
          focusSession(status: FocusStatus.discarded, accumulated: 90),
          t0,
        ).elapsedSeconds,
        90,
      );
    });
  });

  group('pauseFocus', () {
    test('stores the elapsed seconds and stops the segment', () {
      final result = pauseFocus(focusSession(), after(600));
      expect(result.changed, isTrue);
      expect(result.session.status, FocusStatus.paused);
      expect(result.session.accumulatedSeconds, 600);
      expect(result.session.segmentStartedAtUtc, isNull);
    });

    test('accumulates over several segments', () {
      final first = pauseFocus(focusSession(), after(600)).session;
      final resumed = resumeFocus(first, after(900)).session;
      expect(resumed.segmentStartedAtUtc, after(900));
      final second = pauseFocus(resumed, after(1000)).session;
      expect(second.accumulatedSeconds, 700, reason: '600 + 100');
    });

    test(
      'a pause with the plan already over ends in awaiting confirmation',
      () {
        final result = pauseFocus(focusSession(planned: 300), after(300));
        expect(result.session.status, FocusStatus.awaitingConfirmation);
        expect(result.session.accumulatedSeconds, 300);
        expect(result.session.segmentStartedAtUtc, isNull);
        final beyond = pauseFocus(focusSession(planned: 300), after(5000));
        expect(beyond.session.status, FocusStatus.awaitingConfirmation);
        expect(
          beyond.session.accumulatedSeconds,
          300,
          reason: 'never above the plan',
        );
        expect(
          pauseFocus(focusSession(planned: 300), after(299)).session.status,
          FocusStatus.paused,
          reason: 'one second before the end it is a normal pause',
        );
      },
    );

    test('with the clock set back nothing is added', () {
      final result = pauseFocus(
        focusSession(accumulated: 200),
        t0.subtract(const Duration(minutes: 5)),
      );
      expect(result.session.accumulatedSeconds, 200);
      expect(result.session.status, FocusStatus.paused);
    });

    test('pausing a paused session is a no-op', () {
      final paused = focusSession(status: FocusStatus.paused, accumulated: 50);
      final result = pauseFocus(paused, after(100));
      expect(result.changed, isFalse);
      expect(result.session, paused);
    });

    test('is refused for awaiting, completed and discarded sessions', () {
      for (final status in [
        FocusStatus.awaitingConfirmation,
        FocusStatus.completed,
        FocusStatus.discarded,
      ]) {
        expect(
          () => pauseFocus(focusSession(status: status), t0),
          invalidState(),
          reason: status.key,
        );
      }
    });
  });

  group('resumeFocus', () {
    test('keeps the accumulated value and starts a new UTC segment', () {
      final paused = focusSession(status: FocusStatus.paused, accumulated: 420);
      final result = resumeFocus(paused, after(5000));
      expect(result.changed, isTrue);
      expect(result.session.status, FocusStatus.running);
      expect(result.session.accumulatedSeconds, 420);
      expect(result.session.segmentStartedAtUtc, after(5000));
      expect(
        computeFocusElapsed(result.session, after(5060)).elapsedSeconds,
        480,
      );
    });

    test('resuming a running session is a no-op', () {
      final running = focusSession();
      final result = resumeFocus(running, after(10));
      expect(result.changed, isFalse);
      expect(result.session, running);
    });

    test('a paused session with a used up plan goes to awaiting', () {
      final paused = focusSession(
        status: FocusStatus.paused,
        planned: 300,
        accumulated: 300,
      );
      final result = resumeFocus(paused, after(10));
      expect(result.session.status, FocusStatus.awaitingConfirmation);
      expect(result.session.segmentStartedAtUtc, isNull);
    });

    test('is refused for awaiting, completed and discarded sessions', () {
      for (final status in [
        FocusStatus.awaitingConfirmation,
        FocusStatus.completed,
        FocusStatus.discarded,
      ]) {
        expect(
          () => resumeFocus(focusSession(status: status), t0),
          invalidState(),
          reason: status.key,
        );
      }
    });
  });

  group('awaitFocusConfirmation', () {
    test('sets accumulated to the plan and clears the segment', () {
      final result = awaitFocusConfirmation(
        focusSession(accumulated: 100, planned: 600),
      );
      expect(result.changed, isTrue);
      expect(result.session.status, FocusStatus.awaitingConfirmation);
      expect(result.session.accumulatedSeconds, 600);
      expect(result.session.segmentStartedAtUtc, isNull);
      expect(result.session.endedAtUtc, isNull, reason: 'nothing completed');
      expect(result.session.completedLocalDate, isNull);
    });

    test('is idempotent', () {
      final awaiting = focusSession(
        status: FocusStatus.awaitingConfirmation,
        accumulated: 1500,
      );
      final result = awaitFocusConfirmation(awaiting);
      expect(result.changed, isFalse);
      expect(result.session, awaiting);
    });

    test('a paused session only moves on if its plan is used up', () {
      expect(
        () => awaitFocusConfirmation(
          focusSession(status: FocusStatus.paused, accumulated: 1499),
        ),
        invalidState(),
      );
      final result = awaitFocusConfirmation(
        focusSession(status: FocusStatus.paused, accumulated: 1500),
      );
      expect(result.session.status, FocusStatus.awaitingConfirmation);
    });

    test('is refused for completed and discarded sessions', () {
      for (final status in [FocusStatus.completed, FocusStatus.discarded]) {
        expect(
          () => awaitFocusConfirmation(focusSession(status: status)),
          invalidState(),
          reason: status.key,
        );
      }
    });
  });

  group('completeFocus', () {
    final date = LocalDate(2026, 10, 3);

    FocusSession complete(FocusSession session, DateTime now) => completeFocus(
      session,
      nowUtc: now,
      completedDate: date,
      timezoneId: 'Europe/Berlin',
      eligible: true,
    ).session;

    test(
      'running: the elapsed time is saved, end and date are the confirmation',
      () {
        final saved = complete(focusSession(accumulated: 100), after(500));
        expect(saved.status, FocusStatus.completed);
        expect(saved.accumulatedSeconds, 600);
        expect(saved.endedAtUtc, after(500));
        expect(saved.completedLocalDate, date);
        expect(saved.timezoneId, 'Europe/Berlin');
        expect(saved.gamificationEligible, isTrue);
        expect(saved.segmentStartedAtUtc, isNull);
      },
    );

    test('paused: the accumulated time is saved', () {
      final saved = complete(
        focusSession(status: FocusStatus.paused, accumulated: 333),
        after(99999),
      );
      expect(saved.accumulatedSeconds, 333);
    });

    test('awaiting confirmation: the planned time is saved', () {
      final saved = complete(
        focusSession(
          status: FocusStatus.awaitingConfirmation,
          accumulated: 1500,
        ),
        after(99999),
      );
      expect(saved.accumulatedSeconds, 1500);
    });

    test('a running session past the plan saves exactly the plan', () {
      final saved = complete(focusSession(planned: 300), after(86400));
      expect(saved.accumulatedSeconds, 300);
    });

    test('the minimum is one second (0 s refused, 1 s saved)', () {
      expect(
        () => complete(focusSession(), t0),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors.keys,
            'fields',
            contains(FocusFields.duration),
          ),
        ),
      );
      expect(
        () => complete(focusSession(), after(0, millis: 999)),
        throwsA(isA<ValidationFailure>()),
        reason: 'still 0 whole seconds',
      );
      expect(complete(focusSession(), after(1)).accumulatedSeconds, 1);
      expect(
        () => complete(
          focusSession(status: FocusStatus.paused, accumulated: 0),
          t0,
        ),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('with the clock set back and nothing accumulated it is refused', () {
      expect(
        () => complete(focusSession(), t0.subtract(const Duration(hours: 2))),
        throwsA(isA<ValidationFailure>()),
      );
      final kept = complete(
        focusSession(accumulated: 60),
        t0.subtract(const Duration(hours: 2)),
      );
      expect(kept.accumulatedSeconds, 60);
    });

    test('the eligibility and the zone passed in are frozen', () {
      final saved = completeFocus(
        focusSession(),
        nowUtc: after(400),
        completedDate: LocalDate(2026, 10, 4),
        timezoneId: 'America/New_York',
        eligible: false,
      ).session;
      expect(saved.gamificationEligible, isFalse);
      expect(saved.timezoneId, 'America/New_York');
      expect(saved.completedLocalDate, LocalDate(2026, 10, 4));
    });

    test('saving a completed session again changes nothing', () {
      final done = complete(focusSession(), after(400));
      final again = completeFocus(
        done,
        nowUtc: after(9999),
        completedDate: LocalDate(2030, 1, 1),
        timezoneId: 'Asia/Tokyo',
        eligible: false,
      );
      expect(again.changed, isFalse);
      expect(again.session, done);
    });

    test('a discarded session cannot be saved', () {
      expect(
        () => complete(focusSession(status: FocusStatus.discarded), t0),
        invalidState(),
      );
    });
  });

  group('discardFocus', () {
    test('open sessions become discarded without a completion', () {
      for (final status in [
        FocusStatus.running,
        FocusStatus.paused,
        FocusStatus.awaitingConfirmation,
      ]) {
        final result = discardFocus(
          focusSession(status: status, accumulated: 100),
          after(50),
        );
        expect(result.changed, isTrue, reason: status.key);
        expect(result.session.status, FocusStatus.discarded);
        expect(result.session.completedLocalDate, isNull);
        expect(result.session.endedAtUtc, isNull);
        expect(result.session.segmentStartedAtUtc, isNull);
        expect(result.session.gamificationEligible, isFalse);
      }
    });

    test('the time spent so far stays recorded', () {
      final result = discardFocus(focusSession(accumulated: 100), after(50));
      expect(result.session.accumulatedSeconds, 150);
    });

    test('discarding twice is a no-op, a completed session is refused', () {
      final discarded = focusSession(status: FocusStatus.discarded);
      expect(discardFocus(discarded, t0).changed, isFalse);
      expect(
        () => discardFocus(focusSession(status: FocusStatus.completed), t0),
        invalidState(),
      );
    });
  });

  group('restoreSession (app closed, AT16/AT17)', () {
    test(
      'time left: the session keeps running with a recomputed remainder',
      () {
        final session = focusSession(accumulated: 300);
        final restored = restoreSession(session, after(600));
        expect(restored.movedToAwaitingConfirmation, isFalse);
        expect(restored.session, session);
        expect(restored.elapsed.elapsedSeconds, 900);
        expect(restored.elapsed.remainingSeconds, 600);
      },
    );

    test('the plan passed while closed: awaiting confirmation', () {
      final restored = restoreSession(focusSession(planned: 600), after(7200));
      expect(restored.movedToAwaitingConfirmation, isTrue);
      expect(restored.session.status, FocusStatus.awaitingConfirmation);
      expect(restored.session.accumulatedSeconds, 600);
      expect(restored.session.segmentStartedAtUtc, isNull);
      expect(restored.elapsed.remainingSeconds, 0);
      expect(
        restored.session.completedLocalDate,
        isNull,
        reason: 'no completed record without the user',
      );
      expect(restored.session.endedAtUtc, isNull);
    });

    test(
      'exactly at the end the session is awaiting, one second before not',
      () {
        expect(
          restoreSession(
            focusSession(planned: 600),
            after(600),
          ).movedToAwaitingConfirmation,
          isTrue,
        );
        expect(
          restoreSession(
            focusSession(planned: 600),
            after(599),
          ).movedToAwaitingConfirmation,
          isFalse,
        );
      },
    );

    test('paused, awaiting and final sessions are left untouched', () {
      for (final status in [
        FocusStatus.paused,
        FocusStatus.awaitingConfirmation,
        FocusStatus.completed,
        FocusStatus.discarded,
      ]) {
        final session = focusSession(status: status, accumulated: 100);
        final restored = restoreSession(session, after(999999));
        expect(restored.session, session, reason: status.key);
        expect(restored.movedToAwaitingConfirmation, isFalse);
      }
    });

    test('a clock set back while closed is reported and counts as 0', () {
      final restored = restoreSession(
        focusSession(accumulated: 100),
        t0.subtract(const Duration(hours: 3)),
      );
      expect(restored.elapsed.clockAnomaly, isTrue);
      expect(restored.elapsed.elapsedSeconds, 100);
      expect(restored.movedToAwaitingConfirmation, isFalse);
    });
  });

  group('validation', () {
    test('the planned time is 5 to 180 minutes, both ends inclusive', () {
      validateFocusPlan(300);
      validateFocusPlan(10800);
      validateFocusPlan(1500);
      for (final bad in [299, 0, -1, 10801, 86400]) {
        expect(
          () => validateFocusPlan(bad),
          throwsA(
            isA<ValidationFailure>().having(
              (f) => f.fieldErrors[FocusFields.planned],
              'message',
              'Bitte wähle eine Dauer zwischen 5 und 180 Minuten.',
            ),
          ),
          reason: '$bad s',
        );
      }
    });

    test('a note is trimmed; blank means none; 500 characters at most', () {
      expect(normalizeFocusNote('  Kapitel 3  '), 'Kapitel 3');
      expect(normalizeFocusNote('   '), isNull);
      expect(normalizeFocusNote(null), isNull);
      expect(normalizeFocusNote('x' * 500), 'x' * 500);
      expect(
        () => normalizeFocusNote('x' * 501),
        throwsA(
          isA<ValidationFailure>().having(
            (f) => f.fieldErrors[FocusFields.note],
            'message',
            'Die Notiz darf höchstens 500 Zeichen lang sein.',
          ),
        ),
      );
      expect(
        normalizeFocusNote(' ${'x' * 500} '),
        'x' * 500,
        reason: 'the limit applies after trimming',
      );
    });

    test('the limit counts characters, not UTF-16 units', () {
      expect(normalizeFocusNote('😀' * 500), '😀' * 500);
      expect(
        () => normalizeFocusNote('😀' * 501),
        throwsA(isA<ValidationFailure>()),
      );
    });

    test('the defaults and limits match the specification', () {
      expect(minFocusPlannedSeconds, 5 * 60);
      expect(maxFocusPlannedSeconds, 180 * 60);
      expect(defaultFocusPlannedSeconds, 25 * 60);
      expect(focusPlanStepSeconds, 5 * 60);
      expect(minFocusSavedSeconds, 1);
      expect(maxFocusNoteLength, 500);
    });
  });

  group('FocusSession', () {
    test('the expected end exists only while running', () {
      final running = focusSession(accumulated: 300, planned: 1500);
      expect(running.expectedEndUtc, after(1200), reason: '1500 - 300 left');
      expect(focusSession(status: FocusStatus.paused).expectedEndUtc, isNull);
      expect(
        focusSession(status: FocusStatus.awaitingConfirmation).expectedEndUtc,
        isNull,
      );
    });

    test('the pause time is the last change of a paused session', () {
      final paused = FocusSession(
        id: 'p',
        category: focusSession().category,
        plannedSeconds: 1500,
        accumulatedSeconds: 10,
        status: FocusStatus.paused,
        startedAtUtc: t0,
        timezoneId: 'Europe/Berlin',
        rowVersion: 2,
        updatedAtUtc: after(10),
      );
      expect(paused.pausedAtUtc, after(10));
      expect(focusSession().pausedAtUtc, isNull);
    });

    test('copyWith can clear nullable fields and keeps the rest', () {
      final session = focusSession(note: 'a');
      final cleared = session.copyWith(note: () => null, rowVersion: 5);
      expect(cleared.note, isNull);
      expect(cleared.rowVersion, 5);
      expect(cleared.id, session.id);
      expect(cleared.segmentStartedAtUtc, session.segmentStartedAtUtc);
      expect(session.copyWith(), session);
      expect(session.copyWith().hashCode, session.hashCode);
    });

    test('isOpen follows the status', () {
      expect(focusSession().isOpen, isTrue);
      expect(focusSession(status: FocusStatus.paused).isOpen, isTrue);
      expect(
        focusSession(status: FocusStatus.awaitingConfirmation).isOpen,
        isTrue,
      );
      expect(focusSession(status: FocusStatus.completed).isOpen, isFalse);
      expect(focusSession(status: FocusStatus.discarded).isOpen, isFalse);
    });
  });
}
