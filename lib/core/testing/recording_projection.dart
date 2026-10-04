import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Test double that records which days were synced and can be told to fail.
final class RecordingProjectionSynchronizer implements ProjectionSynchronizer {
  /// Every `syncDays` call, in order.
  final List<Set<LocalDate>> syncs = [];

  /// If set, `syncDays` throws it (simulates a failing projection/commit).
  Object? failure;

  /// Fake total XP that grows by [xpPerSync] with every sync.
  int xp = 0;
  int xpPerSync = 0;

  /// All days ever synced.
  Set<LocalDate> get allDays => syncs.expand((days) => days).toSet();

  @override
  Future<void> syncDays(Set<LocalDate> days) async {
    syncs.add(days);
    if (failure != null) {
      throw failure!;
    }
    xp += xpPerSync;
  }

  @override
  Future<int> totalXp() async => xp;
}
