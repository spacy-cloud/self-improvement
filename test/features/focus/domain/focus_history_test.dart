import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/focus_fixtures.dart';

void main() {
  setUpAll(TimeZones.ensureInitialized);

  final clock = FakeClock(t0);

  /// A completed session saved on [date] at [endedAt].
  FocusSession completed({
    String id = 'c',
    int planned = 1500,
    int saved = 1500,
    DateTime? endedAt,
    LocalDate? date,
    FocusCategory category = FocusCategory.reading,
    String zone = 'Europe/Berlin',
  }) => focusSession(
    id: id,
    category: category,
    planned: planned,
    accumulated: saved,
    status: FocusStatus.completed,
    endedAt: endedAt ?? t0,
    completedDate: date ?? LocalDate(2026, 10, 3),
    timezoneId: zone,
  );

  group('FocusHistoryEntry', () {
    test('shows category, saved duration, end time and status', () {
      final entry = FocusHistoryEntry.fromSession(
        completed(saved: 1200, endedAt: DateTime.utc(2026, 10, 3, 12, 30)),
        clock,
      );
      expect(entry.categoryLabel, 'Lesen');
      expect(entry.actualSeconds, 1200);
      expect(entry.actualDurationText, '20 Min.');
      expect(entry.endedLocalTime, const LocalTime(14, 30));
      expect(entry.date, LocalDate(2026, 10, 3));
      expect(entry.status, FocusHistoryStatus.finishedEarly);
      expect(entry.subtitle, '14:30 · früher beendet');
    });

    test('the plan reached is "abgeschlossen", one second short is not', () {
      final full = FocusHistoryEntry.fromSession(
        completed(planned: 600, saved: 600),
        clock,
      );
      expect(full.status, FocusHistoryStatus.completed);
      expect(full.subtitle, endsWith('abgeschlossen'));
      final early = FocusHistoryEntry.fromSession(
        completed(planned: 600, saved: 599),
        clock,
      );
      expect(early.status, FocusHistoryStatus.finishedEarly);
    });

    test(
      'the end time is shown in the frozen zone, not in the current one',
      () {
        // 22:30Z is 18:30 in New York (EDT) but 00:30 in Berlin.
        final session = completed(
          endedAt: DateTime.utc(2026, 10, 3, 22, 30),
          zone: 'America/New_York',
          date: LocalDate(2026, 10, 3),
        );
        final entry = FocusHistoryEntry.fromSession(session, clock);
        expect(entry.endedLocalTime, const LocalTime(18, 30));
        expect(entry.date, LocalDate(2026, 10, 3));
      },
    );

    test('an unknown stored zone falls back to the current zone', () {
      final entry = FocusHistoryEntry.fromSession(
        completed(
          endedAt: DateTime.utc(2026, 10, 3, 12, 30),
          zone: 'Mars/Olympus_Mons',
        ),
        clock,
      );
      expect(entry.endedLocalTime, const LocalTime(14, 30));
    });

    test('the XP minimum is 300 seconds', () {
      expect(
        FocusHistoryEntry.fromSession(
          completed(saved: 299),
          clock,
        ).meetsXpMinimum,
        isFalse,
      );
      expect(
        FocusHistoryEntry.fromSession(
          completed(saved: 300),
          clock,
        ).meetsXpMinimum,
        isTrue,
      );
      expect(focusSecondsQualifyForXp(299), isFalse);
      expect(focusSecondsQualifyForXp(300), isTrue);
    });
  });

  group('groupFocusHistoryByDay', () {
    FocusHistoryEntry entry(String id, LocalDate date, int saved) =>
        FocusHistoryEntry(
          session: completed(id: id, date: date, saved: saved),
          date: date,
          endedLocalTime: const LocalTime(12, 0),
        );

    test('groups by completion day, newest day first, keeps the order', () {
      final today = LocalDate(2026, 10, 3);
      final yesterday = LocalDate(2026, 10, 2);
      final days = groupFocusHistoryByDay([
        entry('a', today, 1200),
        entry('b', today, 1500),
        entry('c', yesterday, 3000),
        entry('d', yesterday, 900),
      ]);
      expect(days.map((d) => d.date), [today, yesterday]);
      expect(days[0].entries.map((e) => e.id), ['a', 'b']);
      expect(days[0].totalSeconds, 2700);
      expect(days[1].entries.map((e) => e.id), ['c', 'd']);
      expect(days[1].totalSeconds, 3900);
    });

    test('an empty history has no days', () {
      expect(groupFocusHistoryByDay(const []), isEmpty);
    });

    test('a day after a time zone change still sorts by date', () {
      final days = groupFocusHistoryByDay([
        entry('late', LocalDate(2026, 10, 2), 600),
        entry('later', LocalDate(2026, 10, 3), 600),
      ]);
      expect(days.map((d) => d.date), [
        LocalDate(2026, 10, 3),
        LocalDate(2026, 10, 2),
      ]);
    });
  });

  group('buildFocusTodaySummary', () {
    final today = LocalDate(2026, 10, 3);

    test('sums only the saved durations of sessions completed today', () {
      final summary = buildFocusTodaySummary([
        completed(id: 'a', saved: 1200),
        completed(id: 'b', saved: 1500),
        completed(id: 'old', saved: 3000, date: LocalDate(2026, 10, 2)),
      ], today: today);
      expect(summary.completedSeconds, 2700);
      expect(summary.completedMinutes, 45);
      expect(summary.sessionCount, 2);
      expect(summary.isEmpty, isFalse);
      expect(summary.goalMinutes, isNull);
      expect(summary.goalFraction, isNull);
      expect(summary.remainingGoalMinutes, isNull);
      expect(summary.goalReached, isFalse);
    });

    test('running, paused, awaiting and discarded sessions add nothing', () {
      final summary = buildFocusTodaySummary([
        focusSession(id: 'r'),
        focusSession(id: 'p', status: FocusStatus.paused, accumulated: 600),
        focusSession(
          id: 'w',
          status: FocusStatus.awaitingConfirmation,
          accumulated: 1500,
        ),
        focusSession(id: 'd', status: FocusStatus.discarded, accumulated: 900),
      ], today: today);
      expect(summary.completedSeconds, 0);
      expect(summary.sessionCount, 0);
      expect(summary.isEmpty, isTrue);
    });

    test('whole minutes round down: 44:59 shows 44', () {
      final summary = buildFocusTodaySummary([
        completed(saved: 2699),
      ], today: today);
      expect(summary.completedMinutes, 44);
    });

    test('goal progress: fraction capped at 1, the real time stays', () {
      final reached = buildFocusTodaySummary(
        [completed(saved: 4500)],
        today: today,
        goalMinutes: 60,
      );
      expect(reached.completedMinutes, 75);
      expect(reached.goalFraction, 1.0);
      expect(reached.goalReached, isTrue);
      expect(reached.remainingGoalMinutes, 0);

      final partial = buildFocusTodaySummary(
        [completed(saved: 2700)],
        today: today,
        goalMinutes: 60,
      );
      expect(partial.goalFraction, closeTo(0.75, 1e-9));
      expect(partial.goalReached, isFalse);
      expect(partial.remainingGoalMinutes, 15);
    });

    test('the remaining goal minutes round up', () {
      final summary = buildFocusTodaySummary(
        [completed(saved: 3541)],
        today: today,
        goalMinutes: 60,
      );
      expect(summary.remainingGoalMinutes, 1, reason: '59 s are missing');
      expect(summary.goalReached, isFalse);
      final exactly = buildFocusTodaySummary(
        [completed(saved: 3600)],
        today: today,
        goalMinutes: 60,
      );
      expect(exactly.goalReached, isTrue);
      expect(exactly.remainingGoalMinutes, 0);
    });

    test('without any session the goal is fully open', () {
      final summary = buildFocusTodaySummary(
        const [],
        today: today,
        goalMinutes: 25,
      );
      expect(summary.goalFraction, 0.0);
      expect(summary.remainingGoalMinutes, 25);
      expect(summary.completedMinutes, 0);
    });
  });
}
