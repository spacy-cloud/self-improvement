import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';

/// Whether a focus session is open (running, paused or waiting for the user's
/// confirmation). The plus menu turns "Fokus" into "Fokus fortsetzen" and the
/// module manager refuses to switch the module off while this is true.
class OpenFocusSessionSource {
  OpenFocusSessionSource(this._database);

  final AppDatabase _database;

  /// Emits whenever a session is opened or closed.
  Stream<bool> watchOpen() =>
      (_database.select(_database.focusSessions)..where(
            (f) =>
                f.status.isIn(SchemaKeys.focusOpenStatuses) &
                f.deletedAtUtc.isNull(),
          ))
          .watch()
          .map((rows) => rows.isNotEmpty);
}
