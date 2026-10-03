import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The selectable chart periods in local days (7, 30, 90; "3 M" means 90 days).
const List<int> weightPeriods = [7, 30, 90];

/// Everything the weight overview screen shows, derived from the database.
@immutable
final class WeightOverview {
  const WeightOverview({
    required this.periodDays,
    required this.entriesNewestFirst,
    required this.points,
    this.current,
    this.deltaToPreviousGrams,
    this.weekDeltaGrams,
    this.goal,
    this.bmi,
  });

  final int periodDays;

  /// All active measurements, newest first (the "Alle Messungen" list).
  final List<WeightEntry> entriesNewestFirst;

  /// One point per day in the period (last measurement of the day).
  final List<WeightDayPoint> points;

  final WeightEntry? current;

  /// Current minus the previous measurement; null means "Noch kein Vergleich".
  final int? deltaToPreviousGrams;

  /// Current minus the anchor a week ago; null means "Noch kein Wochenvergleich".
  final int? weekDeltaGrams;

  /// Null unless start weight, target weight and a current weight exist.
  final WeightGoalState? goal;

  /// Null unless height, age and a current weight exist.
  final Bmi? bmi;

  bool get isEmpty => entriesNewestFirst.isEmpty;
}

/// Builds the overview model. Pure: same inputs, same output.
WeightOverview buildWeightOverview({
  required List<WeightEntry> entriesNewestFirst,
  required LocalDate today,
  required int periodDays,
  int? startWeightGrams,
  int? targetWeightGrams,
  int? heightCm,
  int? ageYears,
}) {
  final samples = [
    for (final entry in entriesNewestFirst)
      WeightSample(
        id: entry.id,
        occurredAtUtc: entry.occurredAtUtc,
        localDate: entry.localDate,
        grams: entry.weightGrams,
      ),
  ];
  final currentSample = currentWeight(samples);
  final current = currentSample == null
      ? null
      : entriesNewestFirst.firstWhere((e) => e.id == currentSample.id);
  return WeightOverview(
    periodDays: periodDays,
    entriesNewestFirst: entriesNewestFirst,
    points: dailyPoints(samples, today, periodDays),
    current: current,
    deltaToPreviousGrams: current == null
        ? null
        : deltaToPrevious(samples, current.id),
    weekDeltaGrams: weekDelta(samples, today),
    goal: weightGoal(
      startGrams: startWeightGrams,
      targetGrams: targetWeightGrams,
      currentGrams: current?.weightGrams,
    ),
    bmi: calculateBmi(
      heightCm: heightCm,
      ageYears: ageYears,
      weightGrams: current?.weightGrams,
    ),
  );
}

/// What the dashboard weight card shows: the current value, the last seven
/// days as a small curve and the week comparison. Independent of the period
/// chosen on the weight screen.
@immutable
final class WeightCardModel {
  const WeightCardModel({
    this.current,
    this.weekDeltaGrams,
    this.points = const [],
  });

  final WeightEntry? current;

  /// Null means "Noch kein Wochenvergleich".
  final int? weekDeltaGrams;

  /// One point per measured day of the last seven days, ascending.
  final List<WeightDayPoint> points;

  bool get isEmpty => current == null;
}

/// Builds the dashboard card model. Pure: same inputs, same output.
WeightCardModel buildWeightCard({
  required List<WeightEntry> entriesNewestFirst,
  required LocalDate today,
}) {
  final samples = [
    for (final entry in entriesNewestFirst)
      WeightSample(
        id: entry.id,
        occurredAtUtc: entry.occurredAtUtc,
        localDate: entry.localDate,
        grams: entry.weightGrams,
      ),
  ];
  final currentSample = currentWeight(samples);
  if (currentSample == null) {
    return const WeightCardModel();
  }
  return WeightCardModel(
    current: entriesNewestFirst.firstWhere((e) => e.id == currentSample.id),
    weekDeltaGrams: weekDelta(samples, today),
    points: dailyPoints(samples, today, 7),
  );
}
