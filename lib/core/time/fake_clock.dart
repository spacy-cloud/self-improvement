import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/time/clock_service.dart';

/// Deterministic clock for tests and previews. Not used in production code.
@visibleForTesting
final class FakeClock with ZonedClockMixin implements ClockService {
  FakeClock(this._nowUtc, {this._timeZoneId = 'Europe/Berlin'})
    : assert(_nowUtc.isUtc, 'FakeClock needs a UTC instant');

  /// Convenience: `FakeClock.at('2026-10-03T08:00:00Z')`.
  factory FakeClock.at(String isoUtc, {String timeZoneId = 'Europe/Berlin'}) =>
      FakeClock(DateTime.parse(isoUtc).toUtc(), timeZoneId: timeZoneId);

  DateTime _nowUtc;
  String _timeZoneId;

  @override
  DateTime nowUtc() => _nowUtc;

  @override
  String get timeZoneId => _timeZoneId;

  /// Moves time forward (or backward for clock-change tests).
  void advance(Duration duration) => _nowUtc = _nowUtc.add(duration);

  /// Sets the current instant.
  void setNow(DateTime nowUtc) {
    assert(nowUtc.isUtc, 'FakeClock needs a UTC instant');
    _nowUtc = nowUtc;
  }

  /// Simulates travelling to another time zone.
  void setTimeZone(String timeZoneId) => _timeZoneId = timeZoneId;
}
