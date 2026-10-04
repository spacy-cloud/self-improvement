import 'dart:async';

import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';

/// A stream of [compute] results that is recomputed whenever one of [tables]
/// changes (insert, update or delete, including inside transactions after the
/// commit).
///
/// This is the single mechanism for derived read models (day status, streak,
/// analysis, dashboard cards): the database stays the source of truth and the
/// projection is recomputed from it, never accumulated. Changes arriving while
/// a computation runs are coalesced into exactly one follow-up computation.
Stream<T> watchComputed<T>(
  AppDatabase database,
  Iterable<ResultSetImplementation<dynamic, dynamic>> tables,
  Future<T> Function() compute,
) {
  late final StreamController<T> controller;
  StreamSubscription<Set<TableUpdate>>? subscription;
  var running = false;
  var dirty = false;

  Future<void> run() async {
    if (running) {
      dirty = true;
      return;
    }
    running = true;
    try {
      do {
        dirty = false;
        final value = await compute();
        if (!controller.isClosed) {
          controller.add(value);
        }
      } while (dirty && !controller.isClosed);
    } catch (error, stackTrace) {
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    } finally {
      running = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = database
          .tableUpdates(TableUpdateQuery.onAllTables(tables))
          .listen((_) => unawaited(run()));
      unawaited(run());
    },
    onCancel: () async {
      await subscription?.cancel();
      subscription = null;
      await controller.close();
    },
  );
  return controller.stream;
}
