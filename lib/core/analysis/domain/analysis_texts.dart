/// Ready-made German texts of the analysis: numbers with units, signed
/// changes and the spoken (screen reader) variants.
///
/// Conventions:
/// - Numbers use the shared German formatting (decimal comma, thousands dot,
///   true minus `−` for negative values, explicit `+` for increases).
/// - A unit SYMBOL (`l`, `kg`, `min`, `h`, `kcal`, `%`) is separated from its
///   number by a no-break space ([analysisNbsp], U+00A0) so a line break never
///   separates them. Count nouns (Schritte, Workouts, Tage) are not part of the
///   number text; the label of the figure carries them.
/// - The "spoken" variants spell units out (`Liter`, `Kilogramm`, `Minuten`,
///   `Prozent`) and use the words `plus` and `minus`.
/// - Deltas are neutral: no text implies good or bad.
library;

import 'package:self_improvement/core/analysis/domain/analysis_dates.dart';
import 'package:self_improvement/core/analysis/domain/period_comparison.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// No-break space between a number and a unit symbol.
const String analysisNbsp = ' ';

const String _minus = '−';

/// Visible text when a comparison is impossible.
const String analysisNoComparisonText = 'Noch kein Vergleich';

/// Visible text of an empty card or series.
const String analysisNoDataText = 'Noch keine Daten';

/// Marker of a day without a record for steps, water and weight: a 0 bar is
/// never a measurement.
const String analysisNotRecordedText = 'Nicht erfasst';

/// Placeholder for "no value" (days where a metric does not apply, missing
/// values in a table).
const String analysisDashText = '–';

/// Completeness hint of calories.
const String analysisCaloriesIncompleteText = 'Kalorien unvollständig';

/// Text of an exactly unchanged value.
const String analysisUnchangedText = 'unverändert';

String _withUnit(String number, String unit) => '$number$analysisNbsp$unit';

/// The singular for exactly 1, otherwise the plural: `pluralize(1, 'Tag',
/// 'Tagen')` is `Tag`. Used for words after "von N".
String pluralize(int count, String singular, String plural) =>
    count == 1 ? singular : plural;

/// `1 Workout` / `2 Workouts` (the count is formatted with thousands dots).
String _count(int count, String singular, String plural) =>
    '${formatThousands(count)} ${pluralize(count, singular, plural)}';

/// Litres of [milliliters], rounded to the nearest 10 ml (half up) first so the
/// two decimals are rounded and not truncated: `1687.5` -> `1,69`.
String _liters(double milliliters) =>
    formatLiters((milliliters / 10).round() * 10);

/// A duration in minutes: `45 min`, `1 h`, `1 h 5 min` (units separated from
/// their numbers by a no-break space).
String formatDuration(int minutes) {
  if (minutes < 60) {
    return _withUnit('$minutes', 'min');
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final hoursText = _withUnit(formatThousands(hours), 'h');
  return rest == 0 ? hoursText : '$hoursText ${_withUnit('$rest', 'min')}';
}

/// Completed focus time in whole minutes (the same flooring as the focus
/// goal): `45 min`, `1 h 5 min`; a positive time below one minute is
/// `< 1 min`, none is `0 min`.
String formatFocusDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (seconds > 0 && minutes == 0) {
    return '<${analysisNbsp}1${analysisNbsp}min';
  }
  return formatDuration(minutes);
}

/// Spoken duration in minutes: `45 Minuten`, `1 Stunde 5 Minuten`.
String spokenDuration(int minutes) {
  if (minutes < 60) {
    return _count(minutes, 'Minute', 'Minuten');
  }
  final hours = _count(minutes ~/ 60, 'Stunde', 'Stunden');
  final rest = minutes % 60;
  return rest == 0 ? hours : '$hours ${_count(rest, 'Minute', 'Minuten')}';
}

/// Spoken focus time in whole minutes; below one minute `weniger als eine
/// Minute`.
String spokenFocusDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (seconds > 0 && minutes == 0) {
    return 'weniger als eine Minute';
  }
  return spokenDuration(minutes);
}

/// The value of a figure as shown in a card or table cell.
///
/// Examples: steps `7.450`, water `2,15 l`, weight `71,5 kg`, weight change
/// `−0,3 kg`, workout minutes `1 h 15 min`, kcal `1.850 kcal`, percent
/// `57 %`, counts `3`.
String formatFigureValue(FigureUnit unit, double value) => switch (unit) {
  FigureUnit.steps => formatThousands(value.round()),
  FigureUnit.milliliters => _withUnit(_liters(value), 'l'),
  FigureUnit.grams => _withUnit(formatKilograms(value.round()), 'kg'),
  FigureUnit.gramsChange => _withUnit(
    formatSignedKilograms(value.round()),
    'kg',
  ),
  FigureUnit.workouts ||
  FigureUnit.focusSessions ||
  FigureUnit.tasks ||
  FigureUnit.meals => formatThousands(value.round()),
  FigureUnit.workoutMinutes => formatDuration(value.round()),
  FigureUnit.focusSeconds => formatFocusDuration(value.round()),
  FigureUnit.kcal => _withUnit(formatThousands(value.round()), 'kcal'),
  FigureUnit.percent => _withUnit('${value.round()}', '%'),
};

/// The spoken form of a value (units spelled out): `2,15 Liter`,
/// `71,5 Kilogramm`, `3 Workouts`, `57 Prozent`.
String spokenFigureValue(FigureUnit unit, double value) {
  final whole = value.round();
  return switch (unit) {
    FigureUnit.steps => _count(whole, 'Schritt', 'Schritte'),
    FigureUnit.milliliters => '${_liters(value)} Liter',
    FigureUnit.grams => '${formatKilograms(whole)} Kilogramm',
    FigureUnit.gramsChange => _spokenSigned(
      whole,
      '${formatKilograms(whole.abs())} Kilogramm',
    ),
    FigureUnit.workouts => _count(whole, 'Workout', 'Workouts'),
    FigureUnit.focusSessions => _count(whole, 'Sitzung', 'Sitzungen'),
    FigureUnit.tasks => _count(whole, 'Aufgabe', 'Aufgaben'),
    FigureUnit.meals => _count(whole, 'Mahlzeit', 'Mahlzeiten'),
    FigureUnit.workoutMinutes => spokenDuration(whole),
    FigureUnit.focusSeconds => spokenFocusDuration(whole),
    FigureUnit.kcal => _count(whole, 'Kilokalorie', 'Kilokalorien'),
    FigureUnit.percent => '${formatThousands(whole)} Prozent',
  };
}

String _spokenSigned(int signedValue, String magnitudeText) {
  if (signedValue > 0) {
    return 'plus $magnitudeText';
  }
  if (signedValue < 0) {
    return 'minus $magnitudeText';
  }
  return magnitudeText;
}

/// The number of display steps of [magnitude] in [unit]: 0 means "rounds to
/// zero in the shown precision".
int _displaySteps(FigureUnit unit, double magnitude) => switch (unit) {
  FigureUnit.milliliters => (magnitude / 10).round(),
  FigureUnit.grams || FigureUnit.gramsChange => magnitude.round() ~/ 100,
  FigureUnit.focusSeconds => magnitude.round() ~/ 60,
  _ => magnitude.round(),
};

/// The unsigned text of a difference of [magnitude] (already `abs`).
String _deltaBody(FigureUnit unit, double magnitude) {
  final whole = magnitude.round();
  return switch (unit) {
    FigureUnit.steps => formatThousands(whole),
    FigureUnit.milliliters => _withUnit(_liters(magnitude), 'l'),
    FigureUnit.grams ||
    FigureUnit.gramsChange => _withUnit(formatKilograms(whole), 'kg'),
    FigureUnit.workouts ||
    FigureUnit.focusSessions ||
    FigureUnit.tasks ||
    FigureUnit.meals => formatThousands(whole),
    FigureUnit.workoutMinutes => formatDuration(whole),
    FigureUnit.focusSeconds => formatDuration(whole ~/ 60),
    FigureUnit.kcal => _withUnit(formatThousands(whole), 'kcal'),
    FigureUnit.percent => _withUnit(formatThousands(whole), 'Prozentpunkte'),
  };
}

/// A signed difference as shown next to a value: `+470`, `−0,3 kg`,
/// `+0,19 l`, `−14 Prozentpunkte`. A difference that rounds to zero in the
/// shown precision has no sign (`0`, `0 kg`).
String formatFigureDelta(FigureUnit unit, double delta) {
  final magnitude = delta.abs();
  if (_displaySteps(unit, magnitude) == 0) {
    return _deltaBody(unit, 0);
  }
  final body = _deltaBody(unit, magnitude);
  return delta < 0 ? '$_minus$body' : '+$body';
}

/// The spoken difference: `plus 470 Schritte`, `minus 0,3 Kilogramm`,
/// `plus 14 Prozentpunkte`, `unverändert` when it rounds to zero.
String spokenFigureDelta(FigureUnit unit, double delta) {
  final magnitude = delta.abs();
  if (_displaySteps(unit, magnitude) == 0) {
    return analysisUnchangedText;
  }
  final whole = magnitude.round();
  final body = switch (unit) {
    FigureUnit.steps => _count(whole, 'Schritt', 'Schritte'),
    FigureUnit.milliliters => '${_liters(magnitude)} Liter',
    FigureUnit.grams ||
    FigureUnit.gramsChange => '${formatKilograms(whole)} Kilogramm',
    FigureUnit.workouts => _count(whole, 'Workout', 'Workouts'),
    FigureUnit.focusSessions => _count(whole, 'Sitzung', 'Sitzungen'),
    FigureUnit.tasks => _count(whole, 'Aufgabe', 'Aufgaben'),
    FigureUnit.meals => _count(whole, 'Mahlzeit', 'Mahlzeiten'),
    FigureUnit.workoutMinutes => spokenDuration(whole),
    FigureUnit.focusSeconds => spokenDuration(whole ~/ 60),
    FigureUnit.kcal => _count(whole, 'Kilokalorie', 'Kilokalorien'),
    FigureUnit.percent => _count(whole, 'Prozentpunkt', 'Prozentpunkte'),
  };
  return delta < 0 ? 'minus $body' : 'plus $body';
}

/// A relative change in whole percent with sign: `+7 %`, `−3 %`, `0 %`.
String formatPercentChange(double percent) {
  final rounded = percent.round();
  if (rounded == 0) {
    return _withUnit('0', '%');
  }
  final text = _withUnit(formatThousands(rounded.abs()), '%');
  return rounded < 0 ? '$_minus$text' : '+$text';
}

/// The spoken relative change: `plus 7 Prozent`, `minus 3 Prozent`,
/// `0 Prozent`.
String spokenPercentChange(double percent) {
  final rounded = percent.round();
  if (rounded == 0) {
    return '0 Prozent';
  }
  final text = '${formatThousands(rounded.abs())} Prozent';
  return rounded < 0 ? 'minus $text' : 'plus $text';
}

/// The change of a comparison for a table cell or card line:
///
/// - relative: `+7 % (+470)`,
/// - difference only: `+0,2 kg`, `−14 Prozentpunkte`,
/// - exactly unchanged: `unverändert`,
/// - no comparison: `Noch kein Vergleich`.
String formatChange(PeriodComparison comparison) {
  final result = comparison.result;
  if (result is! ComparisonDelta) {
    return analysisNoComparisonText;
  }
  if (result.delta == 0) {
    return analysisUnchangedText;
  }
  final deltaText = formatFigureDelta(comparison.unit, result.delta);
  final percent = result.percent;
  return percent == null
      ? deltaText
      : '${formatPercentChange(percent)} ($deltaText)';
}

/// The spoken change of a comparison: `plus 7 Prozent, plus 470 Schritte`.
String spokenChange(PeriodComparison comparison) {
  final result = comparison.result;
  if (result is! ComparisonDelta) {
    return analysisNoComparisonText;
  }
  if (result.delta == 0) {
    return analysisUnchangedText;
  }
  final deltaText = spokenFigureDelta(comparison.unit, result.delta);
  final percent = result.percent;
  return percent == null
      ? deltaText
      : '${spokenPercentChange(percent)}, $deltaText';
}

/// The change with its base: `+7 % (+470) gegenüber den vorherigen 7 Tagen`
/// or `Noch kein Vergleich`. [against] is the phrase, for example
/// `AnalysisPeriodLength.againstPrevious`.
String formatComparisonSentence(PeriodComparison comparison, String against) =>
    comparison.isAvailable
    ? '${formatChange(comparison)} $against'
    : analysisNoComparisonText;

/// The spoken form of [formatComparisonSentence].
String spokenComparisonSentence(PeriodComparison comparison, String against) =>
    comparison.isAvailable
    ? '${spokenChange(comparison)} $against'
    : analysisNoComparisonText;

/// Why a comparison is impossible, in one neutral sentence. [usageStart] is
/// the profile start date used for
/// [NoComparisonReason.previousPeriodBeforeStart].
String noComparisonExplanation(
  NoComparisonReason reason, {
  LocalDate? usageStart,
}) => switch (reason) {
  NoComparisonReason.noUsageStart =>
    'Der Nutzungsstart ist noch nicht bekannt.',
  NoComparisonReason.previousPeriodBeforeStart =>
    usageStart == null
        ? 'Der Vergleichszeitraum liegt nicht vollständig in der Nutzungszeit.'
        : 'Der Vergleichszeitraum liegt nicht vollständig in der '
              'Nutzungszeit (Start: ${formatFullDate(usageStart)}).',
  NoComparisonReason.noPreviousData =>
    'Im Vergleichszeitraum liegen keine Daten vor.',
  NoComparisonReason.noCurrentData =>
    'Im aktuellen Zeitraum liegen keine Daten vor.',
  NoComparisonReason.previousIsZero => 'Der Vergleichswert ist 0.',
  NoComparisonReason.incompleteCalories =>
    'Kalorien sind nicht in beiden Zeiträumen vollständig.',
};
