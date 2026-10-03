import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// UTC instant stored as integer milliseconds since the epoch.
///
/// Drift's built-in DateTime storage has second resolution; business instants
/// need milliseconds.
class UtcMillisConverter extends TypeConverter<DateTime, int> {
  const UtcMillisConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) {
    assert(value.isUtc, 'Persisted instants must be UTC');
    return value.toUtc().millisecondsSinceEpoch;
  }
}

/// Business date stored as `YYYY-MM-DD` text.
class LocalDateConverter extends TypeConverter<LocalDate, String> {
  const LocalDateConverter();

  @override
  LocalDate fromSql(String fromDb) => LocalDate.parse(fromDb);

  @override
  String toSql(LocalDate value) => value.toIso();
}

/// Wall clock time stored as `HH:mm` text.
class LocalTimeConverter extends TypeConverter<LocalTime, String> {
  const LocalTimeConverter();

  @override
  LocalTime fromSql(String fromDb) => LocalTime.parse(fromDb);

  @override
  String toSql(LocalTime value) => value.toIso();
}

/// A list of strings stored as a JSON array (tags, muscle groups, goals).
class StringListConverter extends TypeConverter<List<String>, String> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) {
    final decoded = jsonDecode(fromDb);
    if (decoded is! List) {
      throw FormatException('Expected a JSON array', fromDb);
    }
    return List<String>.unmodifiable(decoded.cast<String>());
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}
