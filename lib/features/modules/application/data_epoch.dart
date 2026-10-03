import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Counts how often ALL app data was replaced as a whole (a backup import or a
/// reset). Providers that cache more than a database stream, and running
/// tickers (for example the focus countdown), watch it and rebuild or stop when
/// it changes. Database streams refresh on their own.
class DataEpoch extends Notifier<int> {
  @override
  int build() => 0;

  /// Called by the app after the data was replaced.
  void bump() => state++;
}

final dataEpochProvider = NotifierProvider<DataEpoch, int>(DataEpoch.new);
