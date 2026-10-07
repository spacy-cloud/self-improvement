import 'package:self_improvement/shared/local_date.dart';

/// How far the goals of a day are reached. It selects the list of titles of the
/// day card (this file); the colour of the day ring follows the same stand in
/// `ProgressRing.goals`.
enum GoalsStanding {
  /// No applicable goal is reached yet. This also covers a day without any
  /// applicable goal: nothing is reached, but the dashboard shows "Noch keine
  /// Tagesziele" then and never asks for a title.
  none,

  /// At least one, but not every applicable goal is reached.
  partial,

  /// Every applicable goal is reached and at least one applies (1 of 1 counts).
  all;

  /// The stand of [fulfilled] of [applicable] goals. Like the ring it clamps:
  /// negative counts reach nothing, more reached than applicable is all.
  static GoalsStanding of({required int fulfilled, required int applicable}) {
    if (applicable <= 0 || fulfilled <= 0) {
      return none;
    }
    return fulfilled >= applicable ? all : partial;
  }
}

// The neutral titles of the day card, three per stand. No AI, no network, no
// health claims and no pressure: calm, short sentences. The order is the
// rotation order of `motivationTextFor`.
const List<String> _noneReached = <String>[
  'Heute ist ein guter Tag, um anzufangen.',
  'Jeder Tag ist ein neuer Anfang.',
  'Ein Eintrag nach dem anderen.',
];
const List<String> _someReached = <String>[
  'Stark unterwegs!',
  'Kleine Schritte zählen.',
  'Bleib in deinem Tempo.',
];
const List<String> _allReached = <String>[
  'Geschafft!',
  'Das war ein runder Tag.',
  'Heute hat alles geklappt.',
];

/// The three titles of [standing] in rotation order.
List<String> motivationTextsOf(GoalsStanding standing) => switch (standing) {
  GoalsStanding.none => _noneReached,
  GoalsStanding.partial => _someReached,
  GoalsStanding.all => _allReached,
};

/// The title of the day card for [date] and the stand of the goals
/// ([fulfilled] of [applicable]).
///
/// The list is chosen by the stand, the text inside it by `dayOfYear % 3`: the
/// title changes daily, is stable within a day and identical on every device,
/// and never comes from the list of another stand.
///
/// The texts speak of "today": ask only for today. A past day (BS-93) shows
/// the factual sentence only and no title, so it does not call this function.
String motivationTextFor(
  LocalDate date, {
  required int fulfilled,
  required int applicable,
}) {
  final texts = motivationTextsOf(
    GoalsStanding.of(fulfilled: fulfilled, applicable: applicable),
  );
  return texts[date.dayOfYear % texts.length];
}
