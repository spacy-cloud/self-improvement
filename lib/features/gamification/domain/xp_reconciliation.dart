import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/gamification/domain/xp_award.dart';

/// What has to change in `xp_awards` to match the desired awards.
@immutable
final class AwardReconciliation {
  const AwardReconciliation({
    required this.toUpsert,
    required this.toDeleteKeys,
  });

  /// Awards to insert, or to update where the key already exists (new points,
  /// date, source or rule version). Sorted by key.
  final List<XpAward> toUpsert;

  /// Keys of stored awards that are no longer valid. Sorted.
  final List<String> toDeleteKeys;

  /// Whether the stored awards already match.
  bool get isEmpty => toUpsert.isEmpty && toDeleteKeys.isEmpty;
}

/// Compares the stored awards with the freshly computed desired ones.
///
/// Still valid keys with unchanged values are left alone, missing ones are
/// inserted, changed ones (points, date, source, rule version) updated, and
/// stored keys that are no longer desired deleted. Applying the result and
/// reconciling again yields nothing to do, so a retry or a screen rebuild
/// can never create points.
///
/// Contract for the data layer: [existing] must contain the stored awards of
/// all affected dates, and [desired] the computed awards of exactly those dates
/// (for a record moved between days, both days). A desired key that is stored
/// under a different date is simply upserted (the key is the primary key). If a
/// key occurs twice in [desired], the last occurrence wins.
AwardReconciliation reconcileAwards({
  required Iterable<XpAward> existing,
  required Iterable<XpAward> desired,
}) {
  final storedByKey = {for (final award in existing) award.key: award};
  final desiredByKey = {for (final award in desired) award.key: award};
  final toUpsert = [
    for (final award in desiredByKey.values)
      if (storedByKey[award.key] != award) award,
  ]..sort((a, b) => a.key.compareTo(b.key));
  final toDeleteKeys = [
    for (final key in storedByKey.keys)
      if (!desiredByKey.containsKey(key)) key,
  ]..sort();
  return AwardReconciliation(
    toUpsert: List.unmodifiable(toUpsert),
    toDeleteKeys: List.unmodifiable(toDeleteKeys),
  );
}
