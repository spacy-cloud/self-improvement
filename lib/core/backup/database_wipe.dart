import 'package:self_improvement/core/database/app_database.dart';

/// Deletes the content of the whole database.
abstract final class DatabaseWipe {
  /// Deletes every row of EVERY application table, the technical ones
  /// (`xp_awards`, `command_receipts`, `scheduled_notifications`) included.
  ///
  /// Must run inside a transaction. The tables are taken from the schema, not
  /// from a hand-written list, so a table added later is wiped as well; they
  /// are deleted children first, and foreign key checks are deferred to the
  /// commit as a second safety net. Going through the typed delete API (not
  /// raw SQL) keeps the database's change streams informed.
  static Future<void> deleteAllRows(AppDatabase database) async {
    await database.customStatement('PRAGMA defer_foreign_keys = ON');
    for (final table in database.allTables.toList().reversed) {
      await database.delete(table).go();
    }
  }
}
