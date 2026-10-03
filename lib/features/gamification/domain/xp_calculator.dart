import 'package:self_improvement/features/gamification/domain/xp_award.dart';
import 'package:self_improvement/features/gamification/domain/xp_facts.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The XP awards that should exist for one local day: a pure function of the
/// day's facts and the fixed [XpRules]. Nothing is accumulated; recomputing
/// the same day always yields the same awards.
///
/// Rules (limits apply per stored local day):
/// - water: the first 4 eligible entries of at least 100 ml, 5 XP each;
/// - weight: 10 XP once, if at least one eligible entry exists;
/// - steps: 10 XP once, if the frozen eligibility says so and the current value
///   still reaches the frozen threshold ([StepsXpFact.earnsAward]);
/// - task: the first 5 eligible completed tasks, 10 XP each;
/// - focus: the first 4 eligible completed sessions of at least 300 seconds,
///   10 XP each;
/// - workout: 15 XP once, if at least one eligible entry exists;
/// - habit: the first 5 eligible checks, 5 XP each.
///
/// Records that do not qualify (not eligible, below the minimum) never take
/// one of the limited places. "First" is the order of `compareXpEvents`. When
/// an earlier record disappears, the next one moves up and takes its place, so
/// the daily total never exceeds the limits.
///
/// Facts of days before [profileStart] earn nothing. Eligibility is taken
/// from the facts as stored; it is never recomputed here, so a later change of
/// the gamification switch has no influence.
///
/// The result is ordered by source (water, weight, steps, task, focus,
/// workout, habit) and by the award order within a source.
List<XpAward> computeDayAwards(
  XpDayFacts facts, {
  required LocalDate profileStart,
}) {
  final date = facts.date;
  if (date.isBefore(profileStart)) {
    return const [];
  }
  XpAward award(String key, XpSource source, int points, {String? sourceId}) =>
      XpAward(
        key: key,
        date: date,
        source: source,
        sourceId: sourceId,
        points: points,
      );

  final awards = <XpAward>[];

  for (final fact in _firstEligible(
    facts.water.where((fact) => fact.amountMl >= XpRules.waterMinAmountMl),
    XpRules.waterMaxAwardsPerDay,
  )) {
    awards.add(
      award(
        XpKeys.water(fact.id),
        XpSource.water,
        XpRules.waterPoints,
        sourceId: fact.id,
      ),
    );
  }

  if (facts.weights.any((fact) => fact.eligible)) {
    awards.add(
      award(XpKeys.weight(date), XpSource.weight, XpRules.weightPoints),
    );
  }

  final steps = facts.steps;
  if (steps != null && steps.earnsAward) {
    awards.add(award(XpKeys.steps(date), XpSource.steps, XpRules.stepsPoints));
  }

  for (final fact in _firstEligible(facts.tasks, XpRules.taskMaxAwardsPerDay)) {
    awards.add(
      award(
        XpKeys.task(fact.id),
        XpSource.task,
        XpRules.taskPoints,
        sourceId: fact.id,
      ),
    );
  }

  for (final fact in _firstEligible(
    facts.focusSessions.where(
      (fact) => fact.accumulatedSeconds >= XpRules.focusMinSeconds,
    ),
    XpRules.focusMaxAwardsPerDay,
  )) {
    awards.add(
      award(
        XpKeys.focus(fact.id),
        XpSource.focus,
        XpRules.focusPoints,
        sourceId: fact.id,
      ),
    );
  }

  if (facts.workouts.any((fact) => fact.eligible)) {
    awards.add(
      award(XpKeys.workout(date), XpSource.workout, XpRules.workoutPoints),
    );
  }

  for (final fact in _firstEligible(
    facts.habitChecks,
    XpRules.habitMaxAwardsPerDay,
  )) {
    awards.add(
      award(
        XpKeys.habit(fact.habitId, date),
        XpSource.habit,
        XpRules.habitPoints,
        sourceId: fact.habitId,
      ),
    );
  }

  return List.unmodifiable(awards);
}

/// The first [limit] eligible facts in award order.
List<T> _firstEligible<T extends XpEventFact>(Iterable<T> facts, int limit) {
  final eligible = [
    for (final fact in facts)
      if (fact.eligible) fact,
  ]..sort(compareXpEvents);
  return eligible.take(limit).toList();
}
