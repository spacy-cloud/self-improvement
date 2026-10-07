import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// How many days every comparison with the health data looks at: today and the
/// six days before. The same window is the "reload" when the comparison is
/// switched on, and it also catches up days the app was not opened and data
/// that reached the health interface late (a watch that synced afterwards).
const int healthSyncDays = 7;

/// Whether a comparison reads [day]: it is one of the [days] local days ending
/// [today] (default [healthSyncDays], the window of [healthSyncWindow]). An
/// older day is never read again, and neither is a day after [today].
///
/// What reaches a day outside of it (a total that Health Connect holds for it)
/// stays out of the app, so nothing refills it after it was deleted.
bool isInHealthSyncWindow(
  LocalDate day,
  LocalDate today, {
  int days = healthSyncDays,
}) => !day.isAfter(today) && day.daysUntil(today) < days;

/// The instants of one local calendar day: from its first moment up to (not
/// including) the first moment of the next day.
///
/// The length is not always 24 hours: on the day the clocks change it is 23 or
/// 25 hours. That is why the range is always built from the calendar and the
/// zone, never with a fixed number of hours.
@immutable
final class HealthDayRange {
  const HealthDayRange({
    required this.day,
    required this.startUtc,
    required this.endUtc,
  });

  /// The local calendar date.
  final LocalDate day;

  /// First moment of [day] in the zone (UTC, inclusive).
  final DateTime startUtc;

  /// First moment of the next day in the zone (UTC, exclusive).
  final DateTime endUtc;

  /// The real length of the day in the zone.
  Duration get length => endUtc.difference(startUtc);

  @override
  bool operator ==(Object other) =>
      other is HealthDayRange &&
      other.day == day &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc;

  @override
  int get hashCode => Object.hash(day, startUtc, endUtc);

  @override
  String toString() => 'HealthDayRange($day, $startUtc to $endUtc)';
}

/// The range of the local calendar [day] in [timeZoneId] (default: the zone of
/// [clock] right now).
///
/// A zone that skips local midnight (the clocks jump over it) starts the day
/// at the first minute that exists, like the day change of the app itself; an
/// ambiguous midnight (the clocks turn back over it) starts at the earlier
/// instant.
HealthDayRange healthDayRange(
  ClockService clock,
  LocalDate day, {
  String? timeZoneId,
}) {
  final zone = timeZoneId ?? clock.timeZoneId;
  return HealthDayRange(
    day: day,
    startUtc: _startOfDay(clock, day, zone),
    endUtc: _startOfDay(clock, day.addDays(1), zone),
  );
}

/// The ranges of the last [days] local days ending today (default
/// [healthSyncDays]), oldest first. "Today" and the zone come from [clock], so
/// tests move both.
List<HealthDayRange> healthSyncWindow(
  ClockService clock, {
  int days = healthSyncDays,
}) {
  assert(days > 0, 'a window needs at least one day');
  final zone = clock.timeZoneId;
  final today = clock.today();
  return [
    for (var back = days - 1; back >= 0; back--)
      healthDayRange(clock, today.addDays(-back), timeZoneId: zone),
  ];
}

DateTime _startOfDay(ClockService clock, LocalDate day, String zone) {
  const midnight = LocalTime(0, 0);
  var resolved = clock.toUtc(day, midnight, timeZoneId: zone);
  if (resolved is ZonedNonexistent) {
    resolved = clock.toUtc(day, resolved.nextValid, timeZoneId: zone);
  }
  return resolved is ZonedResolved ? resolved.utc : day.toUtcMidnight();
}
