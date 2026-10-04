import 'package:drift/drift.dart';

/// A query executor that fails when opened, like a corrupt or unmigratable
/// database file. Used to test the startup error path.
final class BrokenQueryExecutor extends QueryExecutor {
  @override
  SqlDialect get dialect => SqlDialect.sqlite;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) async =>
      throw StateError('simulated open failure');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
