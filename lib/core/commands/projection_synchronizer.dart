import 'package:self_improvement/shared/local_date.dart';

/// Hook that keeps derived data (goal snapshots, XP awards) consistent.
///
/// It is invoked by the command runner INSIDE the same database transaction as
/// the fact mutation, so a failure rolls back both. Implementations must be
/// idempotent: syncing the same days twice changes nothing.
abstract interface class ProjectionSynchronizer {
  /// Ensures snapshots and desired XP awards for [days] match the facts.
  Future<void> syncDays(Set<LocalDate> days);

  /// Current total XP (sum of valid awards), used for before/after events.
  Future<int> totalXp();
}

/// Projection that does nothing (tests without projections, early bootstrap).
final class NoopProjectionSynchronizer implements ProjectionSynchronizer {
  const NoopProjectionSynchronizer();

  @override
  Future<void> syncDays(Set<LocalDate> days) async {}

  @override
  Future<int> totalXp() async => 0;
}
