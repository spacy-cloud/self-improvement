import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';

/// An instant together with the frozen business date and zone of the event.
///
/// Records store all three; a later zone change never moves them.
@immutable
final class FrozenInstant {
  const FrozenInstant({
    required this.utc,
    required this.localDate,
    required this.timezoneId,
  });

  final DateTime utc;
  final LocalDate localDate;
  final String timezoneId;
}

/// Everything a command body may use. Time is captured ONCE at command start
/// so all effects of one command share the same instant.
final class CommandContext {
  CommandContext({
    required this.clock,
    required this.ids,
    required this.nowUtc,
    required this._gamificationEnabled,
  }) : timeZoneId = clock.timeZoneId,
       today = clock.localDateOf(nowUtc);

  final ClockService clock;
  final IdGenerator ids;

  /// The instant this command started (UTC).
  final DateTime nowUtc;

  /// IANA zone in effect at [nowUtc].
  final String timeZoneId;

  /// Local calendar date at [nowUtc].
  final LocalDate today;

  final Future<bool> Function() _gamificationEnabled;

  /// Whether the gamification module is active right now (evaluated inside the
  /// command transaction). Facts created while it is off are never eligible.
  Future<bool> isGamificationEnabled() => _gamificationEnabled();

  /// Freezes [utc] with the current zone.
  FrozenInstant freeze(DateTime utc) => FrozenInstant(
    utc: utc,
    localDate: clock.localDateOf(utc, timeZoneId: timeZoneId),
    timezoneId: timeZoneId,
  );

  /// [freeze] of [nowUtc].
  FrozenInstant get frozenNow => freeze(nowUtc);
}
