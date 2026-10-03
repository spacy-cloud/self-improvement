/// German texts of the weight screens that are derived from data (pure Dart:
/// no Flutter import, trivially unit-testable).
library;

import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The condition texts of a measurement in a fixed order. "nüchtern" is only a
/// derived short text (neither eating nor drinking flagged); the toilet
/// condition is named separately. The app makes no claim about quality.
List<String> weightConditionLabels(WeightEntry entry) => [
  if (entry.isFasted) 'nüchtern',
  if (entry.beforeToilet) 'Vor dem Klo',
  if (entry.afterDrinking) 'Nach dem Trinken',
  if (entry.afterEating) 'Nach dem Essen',
];

/// Second line of an entry row, for example `08:32 · nüchtern · Vor dem Klo`.
/// [isStart] marks the first measurement when it equals the explicit start
/// weight of the profile.
String weightMetaLine(String time, WeightEntry entry, {bool isStart = false}) =>
    [
      time,
      ...weightConditionLabels(entry),
      if (isStart) 'Startgewicht',
    ].join(' · ');

/// Direction arrow of a change: `↓`, `↑` or `→` for no change.
String weightDeltaArrow(int deltaGrams) => deltaGrams < 0
    ? '↓'
    : deltaGrams > 0
    ? '↑'
    : '→';

/// A change as neutral text with arrow and sign, for example `↓  −0,3 kg`.
/// The sign uses the true minus; the colour never carries the meaning.
String weightDeltaText(int deltaGrams) =>
    '${weightDeltaArrow(deltaGrams)}  ${formatSignedKilograms(deltaGrams)} kg';

/// A change for screen readers, for example `minus 0,3 Kilogramm`.
String weightDeltaSpoken(int deltaGrams) {
  if (deltaGrams == 0) {
    return 'unverändert';
  }
  final amount = formatKilograms(deltaGrams.abs());
  return deltaGrams < 0 ? 'minus $amount Kilogramm' : 'plus $amount Kilogramm';
}

/// The remaining distance to the goal, or "Ziel erreicht" (never a negative
/// remainder).
String weightGoalRemainingText(WeightGoalState goal) => goal.reached
    ? 'Ziel erreicht'
    : 'Noch ${formatKilograms(goal.remainingGrams)} kg';

/// Title of the chart period buttons: 7 and 30 days, "3 M" for 90 days.
String weightPeriodLabel(int days) => switch (days) {
  7 => '7 T',
  30 => '30 T',
  90 => '3 M',
  _ => '$days T',
};

/// Spoken name of a chart period ("3 M" is explicitly 90 days).
String weightPeriodSpoken(int days) => switch (days) {
  7 => '7 Tage',
  30 => '30 Tage',
  90 => '3 Monate, 90 Tage',
  _ => '$days Tage',
};

/// One sentence that tells what the chart shows (the text alternative of the
/// line chart): the number of measured days and the first and last value.
String weightChartSummary(
  List<WeightDayPoint> points,
  int periodDays,
  LocalDate today,
) {
  if (points.isEmpty) {
    return 'In den letzten $periodDays Tagen gibt es keine Messung.';
  }
  final last = points.last;
  if (points.length == 1) {
    return 'Eine Messung am '
        '${formatDateShort(last.date, contextYear: today.year)}: '
        '${formatKilograms(last.grams)} kg.';
  }
  final first = points.first;
  return '${points.length} Messtage in $periodDays Tagen. '
      'Zuerst ${formatKilograms(first.grams)} kg, '
      'zuletzt ${formatKilograms(last.grams)} kg '
      '(${formatSignedKilograms(last.grams - first.grams)} kg).';
}

/// Wall clock time of a measurement in the zone it was taken in (`08:32`);
/// the frozen zone keeps old entries stable after a trip.
String weightEntryTime(ClockService clock, WeightEntry entry) => clock
    .toLocal(entry.occurredAtUtc, timeZoneId: entry.timezoneId)
    .time
    .toIso();
