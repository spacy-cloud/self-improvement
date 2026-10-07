import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// How many days before today Home can go back (BS-93, D-029): today and the
/// seven days before it, so the oldest day it can show is "vor 7 Tagen".
const int dayBrowserBackDays = 7;

/// The day Home shows, in relation to today and to the days that can be
/// reached.
///
/// Home pages through the days from the oldest reachable one up to today. The
/// oldest reachable day is [dayBrowserBackDays] days before today, but never
/// before the day the profile started: nothing was recorded before it and no
/// goal existed, so there is nothing honest to show (the day is simply not
/// offered). Everything here is calendar arithmetic on [LocalDate], so a day
/// with a daylight saving change has exactly one place in the row, like any
/// other.
@immutable
final class BrowsedDay {
  const BrowsedDay._({
    required this.date,
    required this.today,
    required this.oldest,
  });

  /// The day to show: [choice] when it can be reached, otherwise today (no
  /// choice, a day in the future, or a day older than the oldest reachable
  /// one). [profileStart] is the first day of the profile; without it only the
  /// seven days limit the way back.
  factory BrowsedDay.resolve({
    required LocalDate today,
    LocalDate? choice,
    LocalDate? profileStart,
  }) {
    var oldest = today.addDays(-dayBrowserBackDays);
    if (profileStart != null && profileStart.isAfter(oldest)) {
      oldest = profileStart;
    }
    if (oldest.isAfter(today)) {
      oldest = today;
    }
    final reachable =
        choice != null && !choice.isBefore(oldest) && !choice.isAfter(today);
    return BrowsedDay._(
      date: reachable ? choice : today,
      today: today,
      oldest: oldest,
    );
  }

  /// The day shown.
  final LocalDate date;

  /// Today, as the clock says.
  final LocalDate today;

  /// The oldest day that can be reached from here.
  final LocalDate oldest;

  /// Whether the day shown is today.
  bool get isToday => date == today;

  /// How many days before today the day shown lies (0 for today).
  int get daysAgo => date.daysUntil(today);

  /// Whether there is more than one day to page through. On the first day of
  /// the profile there is not, and Home shows no arrows then.
  bool get isBrowsable => oldest.isBefore(today);

  /// Whether an older day can be reached.
  bool get canGoBack => date.isAfter(oldest);

  /// Whether a newer day can be reached (only a day that is not today has one).
  bool get canGoForward => date.isBefore(today);

  /// The day before the one shown, or `null` at the oldest reachable day.
  LocalDate? get previous => canGoBack ? date.addDays(-1) : null;

  /// The day after the one shown, or `null` at today.
  LocalDate? get next => canGoForward ? date.addDays(1) : null;

  /// The reachable days from the oldest to today.
  List<LocalDate> get days =>
      List<LocalDate>.unmodifiable(oldest.rangeTo(today));

  /// The day as Home writes it: "Samstag, 12. September".
  String get dateText => formatDateLong(date);

  /// How far the day is from today in words: "heute", "gestern", "vor 3 Tagen".
  String get relativeText => switch (daysAgo) {
    <= 0 => 'heute',
    1 => 'gestern',
    final back => 'vor $back Tagen',
  };

  /// What a screen reader says for the day: the date and how long ago it was,
  /// "Montag, 5. Oktober, vor 2 Tagen".
  String get spoken => '$dateText, $relativeText';

  @override
  bool operator ==(Object other) =>
      other is BrowsedDay &&
      other.date == date &&
      other.today == today &&
      other.oldest == oldest;

  @override
  int get hashCode => Object.hash(date, today, oldest);

  @override
  String toString() => 'BrowsedDay($date, today $today, oldest $oldest)';
}
