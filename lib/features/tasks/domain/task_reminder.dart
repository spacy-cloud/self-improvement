import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// "Heute 18:00": the evening quick choice of the reminder field.
const LocalTime reminderEveningTime = LocalTime(18, 0);

/// "Morgen 09:00": the morning quick choice of the reminder field.
const LocalTime reminderMorningTime = LocalTime(9, 0);

/// One quick choice of the reminder field: a fixed moment next to the free
/// choice of the date and time picker.
@immutable
final class ReminderChoice {
  const ReminderChoice({
    required this.label,
    required this.spokenLabel,
    required this.atUtc,
  });

  /// The chip text, `Heute 18:00`.
  final String label;

  /// What a screen reader says, `Heute 18:00 Uhr`.
  final String spokenLabel;

  /// The moment this choice stands for (UTC).
  final DateTime atUtc;
}

/// The quick choices that can be set right now, in the order of the chips:
/// "Heute 18:00" only while that moment still lies ahead of [nowUtc], and
/// "Morgen 09:00". A moment the zone does not have (a daylight saving gap) is
/// left out. The choices are computed in the zone of [clock] on the local day
/// of [nowUtc], so they are right on a day with a clock change too.
List<ReminderChoice> quickReminderChoices({
  required ClockService clock,
  required DateTime nowUtc,
}) {
  final today = clock.localDateOf(nowUtc);
  final choices = <ReminderChoice>[];

  final evening = _resolve(clock, today, reminderEveningTime);
  if (evening != null && evening.isAfter(nowUtc)) {
    choices.add(
      ReminderChoice(
        label: 'Heute ${reminderEveningTime.toIso()}',
        spokenLabel: 'Heute ${reminderEveningTime.toIso()} Uhr',
        atUtc: evening,
      ),
    );
  }
  final morning = _resolve(clock, today.addDays(1), reminderMorningTime);
  if (morning != null) {
    choices.add(
      ReminderChoice(
        label: 'Morgen ${reminderMorningTime.toIso()}',
        spokenLabel: 'Morgen ${reminderMorningTime.toIso()} Uhr',
        atUtc: morning,
      ),
    );
  }
  return choices;
}

DateTime? _resolve(ClockService clock, LocalDate day, LocalTime time) =>
    switch (clock.toUtc(day, time)) {
      ZonedResolved(:final utc) => utc,
      ZonedNonexistent() => null,
    };

/// The reminder as the field shows it: `Montag, 14. September, 18:00`, with
/// the year when it is not the current one (`Montag, 14. September 2027,
/// 18:00`). The wall clock time is the one of the device zone now.
String taskReminderText(LocalDateTime local, LocalDate today) {
  final date = local.date;
  final day = date.year == today.year
      ? formatDateLong(date)
      : '${formatDateLong(date)} ${date.year}';
  return '$day, ${local.time.toIso()}';
}

/// [taskReminderText] for a screen reader: the time says `Uhr`.
String taskReminderSpokenText(LocalDateTime local, LocalDate today) =>
    '${taskReminderText(local, today)} Uhr';
