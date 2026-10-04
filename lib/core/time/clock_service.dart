import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// A calendar date plus wall clock time, without zone information.
@immutable
final class LocalDateTime {
  const LocalDateTime(this.date, this.time);

  final LocalDate date;
  final LocalTime time;

  @override
  bool operator ==(Object other) =>
      other is LocalDateTime && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  @override
  String toString() => '$date $time';
}

/// Result of converting a wall clock date and time of a zone to an instant.
sealed class ZonedResolution {
  const ZonedResolution();
}

/// The wall clock time exists; [utc] is the instant (always `isUtc`). For an
/// ambiguous time (clocks turned back) the earlier offset is used.
final class ZonedResolved extends ZonedResolution {
  const ZonedResolved(this.utc, {required this.wasAmbiguous});

  final DateTime utc;
  final bool wasAmbiguous;
}

/// The wall clock time does not exist (daylight saving gap).
final class ZonedNonexistent extends ZonedResolution {
  const ZonedNonexistent(this.nextValid);

  /// The first valid wall clock time after the gap.
  final LocalTime nextValid;
}

/// Source of truth for "now", the device time zone and calendar day
/// conversions. Injectable and replaceable in tests ([FakeClock]).
///
/// Business records store a UTC instant plus the *frozen* local date and the
/// IANA zone id at the time of the event; later zone changes never move them.
abstract interface class ClockService {
  /// The current instant; `isUtc` is always true.
  DateTime nowUtc();

  /// IANA id of the device zone at this moment, e.g. `Europe/Berlin`.
  String get timeZoneId;

  /// The local calendar date now (in [timeZoneId]).
  LocalDate today();

  /// The calendar date of [utc] in [timeZoneId] (default: current zone).
  LocalDate localDateOf(DateTime utc, {String? timeZoneId});

  /// Wall clock date and time of [utc] in [timeZoneId] (default: current).
  LocalDateTime toLocal(DateTime utc, {String? timeZoneId});

  /// Converts a wall clock [date] and [time] to an instant. Never uses fixed
  /// 24 hour arithmetic; reports DST gaps instead of shifting silently.
  ZonedResolution toUtc(LocalDate date, LocalTime time, {String? timeZoneId});
}

/// Loads the IANA time zone database once.
abstract final class TimeZones {
  static bool _initialized = false;

  /// Idempotent. Must run before any [ClockService] conversion.
  static void ensureInitialized() {
    if (_initialized) {
      return;
    }
    tz_data.initializeTimeZones();
    _initialized = true;
  }

  static const Set<String> _utcAliases = {'UTC', 'Etc/UTC', 'GMT', 'Etc/GMT'};

  /// The location for an IANA zone [id]; UTC aliases map to UTC.
  static tz.Location location(String id) {
    ensureInitialized();
    if (_utcAliases.contains(id)) {
      return tz.UTC;
    }
    return tz.getLocation(id);
  }

  /// Whether [id] is a known IANA zone id.
  static bool isKnown(String id) {
    try {
      location(id);
      return true;
    } on tz.LocationNotFoundException {
      return false;
    }
  }
}

/// Shared zone arithmetic used by all [ClockService] implementations.
mixin ZonedClockMixin implements ClockService {
  tz.Location _location(String? zoneId) =>
      TimeZones.location(zoneId ?? timeZoneId);

  @override
  LocalDate today() => localDateOf(nowUtc());

  @override
  LocalDate localDateOf(DateTime utc, {String? timeZoneId}) =>
      toLocal(utc, timeZoneId: timeZoneId).date;

  @override
  LocalDateTime toLocal(DateTime utc, {String? timeZoneId}) {
    assert(utc.isUtc, 'Instants must be UTC');
    final local = tz.TZDateTime.from(utc, _location(timeZoneId));
    return LocalDateTime(
      LocalDate(local.year, local.month, local.day),
      LocalTime(local.hour, local.minute),
    );
  }

  @override
  ZonedResolution toUtc(LocalDate date, LocalTime time, {String? timeZoneId}) {
    final location = _location(timeZoneId);
    final resolved = _resolve(location, date, time);
    if (resolved != null) {
      return resolved;
    }
    // DST gap: find the first wall clock minute that exists again.
    var probe = time.minutesOfDay;
    var probeDate = date;
    for (var step = 0; step < 24 * 60; step++) {
      probe += 1;
      if (probe >= 24 * 60) {
        probe -= 24 * 60;
        probeDate = probeDate.addDays(1);
      }
      final candidate = LocalTime(probe ~/ 60, probe % 60);
      if (_resolve(location, probeDate, candidate) != null) {
        return ZonedNonexistent(candidate);
      }
    }
    return ZonedNonexistent(time);
  }

  ZonedResolved? _resolve(
    tz.Location location,
    LocalDate date,
    LocalTime time,
  ) {
    final wallAsUtc = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).millisecondsSinceEpoch;
    const day = 24 * 60 * 60 * 1000;
    final candidates = <int>{};
    for (final shift in [-day, 0, day]) {
      final offset = location.timeZone(wallAsUtc + shift).offset;
      candidates.add(wallAsUtc - offset.inMilliseconds);
    }
    final valid = <int>[];
    for (final utcMillis in candidates) {
      final local = tz.TZDateTime.fromMillisecondsSinceEpoch(
        location,
        utcMillis,
      );
      if (local.year == date.year &&
          local.month == date.month &&
          local.day == date.day &&
          local.hour == time.hour &&
          local.minute == time.minute) {
        valid.add(utcMillis);
      }
    }
    if (valid.isEmpty) {
      return null;
    }
    valid.sort();
    return ZonedResolved(
      DateTime.fromMillisecondsSinceEpoch(valid.first, isUtc: true),
      wasAmbiguous: valid.length > 1,
    );
  }
}

/// Production clock: system time and the device zone reported by the platform.
final class SystemClock with ZonedClockMixin implements ClockService {
  SystemClock({required this._timeZoneIdProvider});

  final String Function() _timeZoneIdProvider;

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  String get timeZoneId => _timeZoneIdProvider();
}
