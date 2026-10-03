import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A projection whose commit can be made to fail: simulates a database write
/// error (the command runner rolls back and reports a storage failure).
final class FlakyProjection implements ProjectionSynchronizer {
  /// When set, every command fails with it.
  Object? failure;

  @override
  Future<void> syncDays(Set<LocalDate> days) async {}

  @override
  Future<int> totalXp() async {
    final error = failure;
    if (error != null) {
      throw error;
    }
    return 0;
  }
}
