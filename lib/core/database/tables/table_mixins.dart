import 'package:drift/drift.dart';
import 'package:self_improvement/core/database/converters.dart';

/// Columns shared by all mutable business tables.
mixin AuditColumns on Table {
  IntColumn get createdAtUtc => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAtUtc => integer().map(const UtcMillisConverter())();

  /// Incremented on every mutation; used for undo conflict detection.
  IntColumn get rowVersion => integer()
      .withDefault(const Constant(1))
      .check(const CustomExpression<bool>('row_version >= 1'))();
}

/// Soft delete marker: queries exclude rows where this is set.
mixin SoftDeleteColumn on Table {
  IntColumn get deletedAtUtc =>
      integer().map(const UtcMillisConverter()).nullable()();
}
