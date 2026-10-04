/// Rules shared by water and meal entries: event time, note and plain number
/// parsing. Pure functions, no database, no Flutter widgets.
///
/// The limits equal the ones of the weight form (technical input limits, not
/// medical or nutritional norms). They are kept local so the nutrition module
/// does not depend on another feature; a test asserts they stay in sync.
library;

import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Earliest accepted business date of a water or meal entry (2000-01-01 in the
/// device zone).
final LocalDate earliestNutritionDate = LocalDate(2000, 1, 1);

/// Longest note, counted in characters (Unicode code points, the same unit
/// SQLite's `length()` uses for the database check).
const int maxNutritionNoteLength = 500;

/// German hint: the time lies after "now".
const String eventInFutureMessage =
    'Der Zeitpunkt darf nicht in der Zukunft liegen.';

/// German hint: the date lies before 2000-01-01.
const String eventTooEarlyMessage =
    'Das Datum darf nicht vor dem 01.01.2000 liegen.';

/// German hint: the note is longer than [maxNutritionNoteLength].
const String noteTooLongMessage =
    'Die Notiz darf höchstens $maxNutritionNoteLength Zeichen lang sein.';

/// Number of characters of [text] as the database counts them (code points).
int characterCount(String text) => text.runes.length;

/// German hint for a wall clock time that does not exist because clocks jump
/// forward; [nextValid] is the first valid time after the gap.
String dstGapMessage(LocalTime nextValid) =>
    'Diese Uhrzeit gibt es wegen der Zeitumstellung nicht. '
    'Bitte wähle ${nextValid.toIso()} Uhr oder später.';

/// Checks the time of an entry: not after [nowUtc] and not before 2000-01-01
/// (calendar day in the current device zone). Returns the German hint or null.
String? eventTimeError({
  required DateTime occurredAtUtc,
  required DateTime nowUtc,
  required ClockService clock,
}) {
  if (occurredAtUtc.isAfter(nowUtc)) {
    return eventInFutureMessage;
  }
  if (clock.localDateOf(occurredAtUtc) < earliestNutritionDate) {
    return eventTooEarlyMessage;
  }
  return null;
}

/// Normalises an optional note: trimmed, blank means no note. [error] is set
/// when the trimmed note is longer than [maxNutritionNoteLength].
({String? note, String? error}) normalizeNote(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return (note: null, error: null);
  }
  if (characterCount(trimmed) > maxNutritionNoteLength) {
    return (note: null, error: noteTooLongMessage);
  }
  return (note: trimmed, error: null);
}

/// Value returned by [parseDigits] for absurdly long digit strings: larger than
/// any accepted number, so range checks reject it without integer overflow.
const int wholeNumberCeiling = 999999999;

final RegExp _onlyDigits = RegExp(r'^\d+$');
final RegExp _leadingZeros = RegExp(r'^0+');

/// Parses a non-empty string of ASCII digits (already trimmed).
///
/// Returns null when [text] contains anything else: signs, decimal or
/// thousands separators, letters, exponents, other scripts' digits. Leading
/// zeros are allowed. Inputs with more than nine significant digits saturate
/// at [wholeNumberCeiling].
int? parseDigits(String text) {
  if (!_onlyDigits.hasMatch(text)) {
    return null;
  }
  final significant = text.replaceFirst(_leadingZeros, '');
  if (significant.length > 9) {
    return wholeNumberCeiling;
  }
  return significant.isEmpty ? 0 : int.parse(significant);
}
