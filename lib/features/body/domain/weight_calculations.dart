/// Pure weight overview rules (specification section 6.2/6.3).
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A measurement as needed for calculations.
@immutable
final class WeightSample {
  const WeightSample({
    required this.id,
    required this.occurredAtUtc,
    required this.localDate,
    required this.grams,
  });

  final String id;
  final DateTime occurredAtUtc;
  final LocalDate localDate;
  final int grams;
}

/// Sorts chronologically (time, then id) without modifying the input.
List<WeightSample> chronological(Iterable<WeightSample> samples) {
  final list = samples.toList();
  list.sort((a, b) {
    final byTime = a.occurredAtUtc.compareTo(b.occurredAtUtc);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });
  return list;
}

/// The current weight: the latest measurement by time (ties by id), or null.
WeightSample? currentWeight(Iterable<WeightSample> samples) {
  final sorted = chronological(samples);
  return sorted.isEmpty ? null : sorted.last;
}

/// Change of [id] compared with the chronologically previous measurement, or
/// null when there is no predecessor ("Noch kein Vergleich").
int? deltaToPrevious(Iterable<WeightSample> samples, String id) {
  final sorted = chronological(samples);
  final index = sorted.indexWhere((sample) => sample.id == id);
  if (index <= 0) {
    return null;
  }
  return sorted[index].grams - sorted[index - 1].grams;
}

/// Week comparison: current minus the latest measurement dated on or before
/// `today - 7` calendar days; null without that anchor ("Noch kein
/// Wochenvergleich") or without a current weight.
int? weekDelta(Iterable<WeightSample> samples, LocalDate today) {
  final sorted = chronological(samples);
  if (sorted.isEmpty) {
    return null;
  }
  final cutoff = today.addDays(-7);
  final anchors = sorted.where((s) => s.localDate <= cutoff).toList();
  if (anchors.isEmpty) {
    return null;
  }
  return sorted.last.grams - anchors.last.grams;
}

/// One chart point: the last measurement of a local day.
@immutable
final class WeightDayPoint {
  const WeightDayPoint({required this.date, required this.grams});

  final LocalDate date;
  final int grams;
}

/// Chart points for the window of [days] local days ending today (inclusive):
/// per day the last measurement, ascending by date. Days without a
/// measurement have no point (never an artificial zero).
List<WeightDayPoint> dailyPoints(
  Iterable<WeightSample> samples,
  LocalDate today,
  int days,
) {
  assert(days >= 1, 'a window has at least one day');
  final start = today.addDays(-(days - 1));
  final lastPerDay = <LocalDate, WeightSample>{};
  for (final sample in chronological(samples)) {
    if (sample.localDate < start || sample.localDate > today) {
      continue;
    }
    lastPerDay[sample.localDate] = sample;
  }
  final dates = lastPerDay.keys.toList()..sort();
  return [
    for (final date in dates)
      WeightDayPoint(date: date, grams: lastPerDay[date]!.grams),
  ];
}

/// State of the optional weight goal.
@immutable
final class WeightGoalState {
  const WeightGoalState({
    required this.progress,
    required this.remainingGrams,
    required this.reached,
  });

  /// 0..1, for gaining and losing alike.
  final double progress;

  /// Absolute distance to the target; 0 once reached in the chosen direction.
  final int remainingGrams;

  /// True when the target is reached or passed in its direction.
  final bool reached;
}

/// Goal progress, or null if start, target or current weight is missing.
///
/// `progress = clamp((current - start) / (target - start), 0, 1)`. If start
/// equals target, progress is 1 only when current equals target, else 0.
/// Remaining is `|target - current|`, 0 once the goal is reached/exceeded in
/// its direction.
WeightGoalState? weightGoal({
  required int? startGrams,
  required int? targetGrams,
  required int? currentGrams,
}) {
  if (startGrams == null || targetGrams == null || currentGrams == null) {
    return null;
  }
  final bool reached;
  final double progress;
  if (startGrams == targetGrams) {
    reached = currentGrams == targetGrams;
    progress = reached ? 1 : 0;
  } else {
    reached = targetGrams < startGrams
        ? currentGrams <= targetGrams
        : currentGrams >= targetGrams;
    progress = ((currentGrams - startGrams) / (targetGrams - startGrams)).clamp(
      0.0,
      1.0,
    );
  }
  return WeightGoalState(
    progress: progress,
    remainingGrams: reached ? 0 : (targetGrams - currentGrams).abs(),
    reached: reached,
  );
}

/// Neutral calculated BMI.
@immutable
final class Bmi {
  const Bmi(this.tenths);

  /// BMI times ten, rounded half up (`233` is 23,3).
  final int tenths;
}

/// BMI only when height, age and weight are all present (adults only).
///
/// `kg / (m * m)` with one decimal, computed in integers:
/// `BMI * 10 = grams * 100 / cm^2`.
Bmi? calculateBmi({
  required int? heightCm,
  required int? ageYears,
  required int? weightGrams,
}) {
  if (heightCm == null || ageYears == null || weightGrams == null) {
    return null;
  }
  if (heightCm < 100 || heightCm > 250 || ageYears < 18 || ageYears > 120) {
    return null;
  }
  final denominator = heightCm * heightCm;
  final tenths = (weightGrams * 100 * 2 + denominator) ~/ (2 * denominator);
  return Bmi(tenths);
}
