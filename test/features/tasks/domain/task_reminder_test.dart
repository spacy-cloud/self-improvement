import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/tasks/domain/task_reminder.dart';
import 'package:self_improvement/features/tasks/domain/task_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// The pure rules of the reminder field (BS-111): the quick choices, the text
/// of the chosen moment, and the rule that a moment must lie ahead.
void main() {
  setUpAll(TimeZones.ensureInitialized);

  List<String> labels(List<ReminderChoice> choices) => [
    for (final choice in choices) choice.label,
  ];

  group('quickReminderChoices', () {
    test('in the morning: today 18:00 and tomorrow 09:00, as instants of the '
        'zone (BS-111, AT25)', () {
      // 10:00 in Berlin (summer time).
      final clock = FakeClock.at('2026-10-03T08:00:00Z');
      final choices = quickReminderChoices(
        clock: clock,
        nowUtc: clock.nowUtc(),
      );
      expect(labels(choices), ['Heute 18:00', 'Morgen 09:00']);
      expect(choices[0].atUtc, DateTime.utc(2026, 10, 3, 16));
      expect(choices[1].atUtc, DateTime.utc(2026, 10, 4, 7));
      expect(choices[0].spokenLabel, 'Heute 18:00 Uhr');
      expect(choices[1].spokenLabel, 'Morgen 09:00 Uhr');
    });

    test('today 18:00 is offered only while it lies ahead: at 17:59 yes, at '
        '18:00 and later no (BS-111)', () {
      final clock = FakeClock.at('2026-10-03T15:59:00Z'); // 17:59 Berlin
      expect(
        labels(quickReminderChoices(clock: clock, nowUtc: clock.nowUtc())),
        ['Heute 18:00', 'Morgen 09:00'],
      );
      clock.setNow(DateTime.utc(2026, 10, 3, 16, 0));
      expect(
        labels(quickReminderChoices(clock: clock, nowUtc: clock.nowUtc())),
        ['Morgen 09:00'],
      );
      clock.setNow(DateTime.utc(2026, 10, 3, 21, 59)); // 23:59 Berlin
      expect(
        labels(quickReminderChoices(clock: clock, nowUtc: clock.nowUtc())),
        ['Morgen 09:00'],
      );
    });

    test('just after midnight "today" is the new day (BS-111)', () {
      final clock = FakeClock.at('2026-10-03T22:05:00Z'); // 00:05 on the 4th
      final choices = quickReminderChoices(
        clock: clock,
        nowUtc: clock.nowUtc(),
      );
      expect(choices[0].atUtc, DateTime.utc(2026, 10, 4, 16));
      expect(choices[1].atUtc, DateTime.utc(2026, 10, 5, 7));
    });

    test('the evening before the clocks go forward: tomorrow 09:00 is 09:00 '
        'CEST, one real hour earlier in UTC than today (BS-111, AT25)', () {
      final clock = FakeClock.at('2026-03-28T10:00:00Z'); // 11:00 CET
      final choices = quickReminderChoices(
        clock: clock,
        nowUtc: clock.nowUtc(),
      );
      expect(choices[0].atUtc, DateTime.utc(2026, 3, 28, 17)); // 18:00 CET
      expect(choices[1].atUtc, DateTime.utc(2026, 3, 29, 7)); // 09:00 CEST
    });

    test('on the day the clocks go back both choices are right (BS-111, '
        'AT25)', () {
      final clock = FakeClock.at('2026-10-25T05:00:00Z'); // 06:00 CET
      final choices = quickReminderChoices(
        clock: clock,
        nowUtc: clock.nowUtc(),
      );
      expect(choices[0].atUtc, DateTime.utc(2026, 10, 25, 17)); // 18:00 CET
      expect(choices[1].atUtc, DateTime.utc(2026, 10, 26, 8)); // 09:00 CET
    });

    test('other zones: the instants follow the zone of the clock (BS-111)', () {
      final clock = FakeClock.at(
        '2026-10-03T14:00:00Z',
        timeZoneId: 'America/New_York',
      ); // 10:00 EDT
      final choices = quickReminderChoices(
        clock: clock,
        nowUtc: clock.nowUtc(),
      );
      expect(choices[0].atUtc, DateTime.utc(2026, 10, 3, 22)); // 18:00 EDT
      expect(choices[1].atUtc, DateTime.utc(2026, 10, 4, 13)); // 09:00 EDT
    });

    test('a time the zone does not have is left out, not shifted (BS-111)', () {
      final clock = _GapAt(
        FakeClock.at('2026-10-03T08:00:00Z'),
        const LocalTime(9, 0),
      );
      expect(
        labels(quickReminderChoices(clock: clock, nowUtc: clock.nowUtc())),
        ['Heute 18:00'],
      );
    });
  });

  group('the text of a chosen moment', () {
    final today = LocalDate(2026, 10, 3);

    test('weekday, day, month and time, as the field shows it (Figma '
        '4121:414)', () {
      expect(
        taskReminderText(
          LocalDateTime(LocalDate(2026, 10, 4), const LocalTime(18, 0)),
          today,
        ),
        'Sonntag, 4. Oktober, 18:00',
      );
      expect(
        taskReminderText(LocalDateTime(today, const LocalTime(9, 5)), today),
        'Samstag, 3. Oktober, 09:05',
      );
    });

    test('another year is named (BS-111)', () {
      expect(
        taskReminderText(
          LocalDateTime(LocalDate(2027, 1, 4), const LocalTime(9, 0)),
          today,
        ),
        'Montag, 4. Januar 2027, 09:00',
      );
    });

    test('the spoken form says Uhr (BS-111, AT34)', () {
      expect(
        taskReminderSpokenText(
          LocalDateTime(LocalDate(2026, 10, 4), const LocalTime(18, 0)),
          today,
        ),
        'Sonntag, 4. Oktober, 18:00 Uhr',
      );
    });
  });

  group('taskReminderError', () {
    final now = DateTime.utc(2026, 10, 3, 8);

    test('no reminder is fine (BS-111)', () {
      expect(taskReminderError(null, nowUtc: now), isNull);
    });

    test('a moment after now is fine, now and before are not (BS-111)', () {
      expect(
        taskReminderError(
          now.add(const Duration(milliseconds: 1)),
          nowUtc: now,
        ),
        isNull,
      );
      for (final at in [now, now.subtract(const Duration(seconds: 1))]) {
        expect(
          taskReminderError(at, nowUtc: now),
          'Dieser Zeitpunkt ist schon vorbei. Wähle einen späteren Zeitpunkt '
          'für die Erinnerung.',
          reason: '$at',
        );
      }
    });

    test('the reminder the task already has is never refused, only a '
        'different past one is (BS-111)', () {
      final old = now.subtract(const Duration(days: 2));
      expect(taskReminderError(old, nowUtc: now, unchangedAtUtc: old), isNull);
      expect(
        taskReminderError(
          old.add(const Duration(minutes: 1)),
          nowUtc: now,
          unchangedAtUtc: old,
        ),
        isNotNull,
      );
      // The same moment in another representation counts as unchanged.
      expect(
        taskReminderError(
          DateTime.fromMillisecondsSinceEpoch(
            old.millisecondsSinceEpoch,
            isUtc: true,
          ),
          nowUtc: now,
          unchangedAtUtc: old,
        ),
        isNull,
      );
    });
  });
}

/// A clock whose zone has no [missing] wall clock time on any day.
final class _GapAt implements ClockService {
  _GapAt(this._inner, this.missing);

  final FakeClock _inner;
  final LocalTime missing;

  @override
  DateTime nowUtc() => _inner.nowUtc();

  @override
  String get timeZoneId => _inner.timeZoneId;

  @override
  LocalDate today() => _inner.today();

  @override
  LocalDate localDateOf(DateTime utc, {String? timeZoneId}) =>
      _inner.localDateOf(utc, timeZoneId: timeZoneId);

  @override
  LocalDateTime toLocal(DateTime utc, {String? timeZoneId}) =>
      _inner.toLocal(utc, timeZoneId: timeZoneId);

  @override
  ZonedResolution toUtc(LocalDate date, LocalTime time, {String? timeZoneId}) =>
      time == missing
      ? ZonedNonexistent(LocalTime(time.hour + 1, time.minute))
      : _inner.toUtc(date, time, timeZoneId: timeZoneId);
}
