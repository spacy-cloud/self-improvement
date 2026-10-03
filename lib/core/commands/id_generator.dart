import 'package:uuid/uuid.dart';

/// Source of unique ids for records and commands (injectable for tests).
abstract interface class IdGenerator {
  /// A new unique id (UUID v4 format in production).
  String newId();
}

/// Production generator: random UUID v4.
final class UuidGenerator implements IdGenerator {
  const UuidGenerator();

  static const Uuid _uuid = Uuid();

  @override
  String newId() => _uuid.v4();
}

/// Deterministic generator for tests: `00000000-0000-4000-8000-000000000001`,
/// `...0002`, ... (valid UUID v4 shape, ordered).
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator([this._next = 1]);

  int _next;

  @override
  String newId() {
    final suffix = (_next++).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }
}
