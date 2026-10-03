import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/database/app_database.dart';

/// Creates an in-memory [AppDatabase] for tests (real SQLite, real schema).
///
/// `closeStreamsSynchronously` avoids pending-timer errors in widget tests.
@visibleForTesting
AppDatabase createTestDatabase() {
  return AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}
