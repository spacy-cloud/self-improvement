import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Strict, typed access to the fields of ONE JSON object.
///
/// Every accessor checks presence, JSON type, format and range, records a
/// German problem (without the offending value) instead of throwing, and
/// returns a neutral placeholder so that a DTO can still be constructed.
/// Callers must discard the result when [hasProblems] is true.
///
/// Rules of the V1 contract implemented here:
/// - every field is required; optional values are present as JSON `null`;
/// - unknown fields are rejected ([finish]);
/// - integers are JSON integers (`1.0` is not an integer), booleans are JSON
///   booleans (`0`/`1`/`"true"` are not).
final class FieldReader {
  FieldReader(this._json, this.location, this._problems);

  /// Reader for record [index] of [table].
  factory FieldReader.record(
    BackupTable table,
    int index,
    Map<String, Object?> json,
    ProblemCollector problems,
  ) => FieldReader(
    json,
    table.isSingleton ? table.key : '${table.key}[$index]',
    problems,
  );

  static final LocalDate _placeholderDate = LocalDate(1970, 1, 1);
  static final DateTime _placeholderInstant = DateTime.utc(1970);

  final Map<String, Object?> _json;
  final ProblemCollector _problems;

  /// `weight_entries[3]`, `profile`, `root`, ...
  final String location;

  int _known = 0;
  bool _failed = false;

  /// Whether any problem was recorded for this object (independent of the
  /// collector's limit).
  bool get hasProblems => _failed;

  /// Records a problem for [field] (or the whole object when `null`).
  void fail(String? field, String message) {
    _failed = true;
    _problems.add(
      ImportProblem(location: location, message: message, field: field),
    );
  }

  /// Rejects fields that were not read. Call once after reading all fields.
  void finish() {
    if (_json.length > _known) {
      fail(null, 'Unbekanntes Zusatzfeld');
    }
  }

  // --- raw access -----------------------------------------------------------

  (bool, Object?) _fetch(String key, String label, {required bool nullable}) {
    if (!_json.containsKey(key)) {
      fail(key, 'Pflichtfeld fehlt: $label');
      return (false, null);
    }
    _known++;
    final value = _json[key];
    if (value == null && !nullable) {
      fail(key, '$label darf nicht leer sein');
      return (false, null);
    }
    return (true, value);
  }

  void _wrongType(String key, String label, String expected) =>
      fail(key, '$label hat einen ungültigen Datentyp (erwartet: $expected)');

  // --- text -----------------------------------------------------------------

  String? _checkedText(
    String key,
    String label,
    Object? value,
    int min,
    int max,
  ) {
    if (value is! String) {
      _wrongType(key, label, 'Text');
      return null;
    }
    if (BackupValues.hasInvalidCharacters(value)) {
      fail(key, '$label enthält ungültige Zeichen');
      return null;
    }
    final length = BackupValues.characterCount(value);
    if (length < min || length > max) {
      fail(
        key,
        min == 0
            ? '$label ist zu lang (höchstens $max Zeichen)'
            : '$label hat eine ungültige Länge (erlaubt: $min bis $max '
                  'Zeichen)',
      );
      return null;
    }
    return value;
  }

  /// Required text of [min]..[max] characters (SQLite `length()` semantics).
  String text(String key, String label, {int min = 0, required int max}) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok ? (_checkedText(key, label, value, min, max) ?? '') : '';
  }

  /// Text or `null`.
  String? optionalText(
    String key,
    String label, {
    int min = 0,
    required int max,
  }) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedText(key, label, value, min, max);
  }

  /// Required text that must equal [expected] (singleton ids).
  String constant(String key, String label, String expected) {
    final (ok, value) = _fetch(key, label, nullable: false);
    if (!ok) {
      return expected;
    }
    if (value is! String) {
      _wrongType(key, label, 'Text');
    } else if (value != expected) {
      fail(key, '$label hat einen ungültigen Wert');
    }
    return expected;
  }

  /// Required lower case UUID.
  String uuid(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    if (!ok) {
      return '';
    }
    if (value is! String) {
      _wrongType(key, label, 'UUID');
      return '';
    }
    if (!BackupValues.isUuid(value)) {
      fail(key, '$label ist keine gültige UUID');
      return '';
    }
    return value;
  }

  String? _checkedChoice(
    String key,
    String label,
    Object? value,
    List<String> allowed,
  ) {
    if (value is! String) {
      _wrongType(key, label, 'Text');
      return null;
    }
    if (!allowed.contains(value)) {
      fail(key, '$label enthält einen unbekannten Wert');
      return null;
    }
    return value;
  }

  /// Required text that is one of [allowed] (enum keys, module ids, ...).
  String choice(String key, String label, List<String> allowed) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok ? (_checkedChoice(key, label, value, allowed) ?? '') : '';
  }

  /// One of [allowed] or `null`.
  String? optionalChoice(String key, String label, List<String> allowed) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedChoice(key, label, value, allowed);
  }

  String? _checkedTimezone(String key, String label, Object? value) {
    if (value is! String) {
      _wrongType(key, label, 'Text');
      return null;
    }
    if (value.isEmpty || value.length > 64 || !TimeZones.isKnown(value)) {
      fail(key, '$label ist keine bekannte Zeitzone');
      return null;
    }
    return value;
  }

  /// Required IANA time zone id known to the app's zone database.
  String timezone(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok ? (_checkedTimezone(key, label, value) ?? '') : '';
  }

  /// IANA time zone id or `null`.
  String? optionalTimezone(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedTimezone(key, label, value);
  }

  // --- numbers and booleans -------------------------------------------------

  int? _checkedInt(
    String key,
    String label,
    Object? value,
    int? min,
    int? max,
    int? multipleOf,
  ) {
    if (value is! int) {
      _wrongType(key, label, 'Ganzzahl');
      return null;
    }
    if ((min != null && value < min) || (max != null && value > max)) {
      fail(key, '$label außerhalb des erlaubten Bereichs');
      return null;
    }
    if (multipleOf != null && value % multipleOf != 0) {
      fail(
        key,
        '$label hat eine ungültige Schrittweite '
        '(Vielfaches von $multipleOf erforderlich)',
      );
      return null;
    }
    return value;
  }

  /// Required integer within [min]..[max] (inclusive, either may be omitted)
  /// and, if given, a multiple of [multipleOf].
  int integer(String key, String label, {int? min, int? max, int? multipleOf}) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok ? (_checkedInt(key, label, value, min, max, multipleOf) ?? 0) : 0;
  }

  /// Like [integer] but `null` is allowed.
  int? optionalInteger(
    String key,
    String label, {
    int? min,
    int? max,
    int? multipleOf,
  }) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedInt(key, label, value, min, max, multipleOf);
  }

  /// Required JSON boolean.
  bool boolean(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    if (!ok) {
      return false;
    }
    if (value is! bool) {
      _wrongType(key, label, 'Wahrheitswert');
      return false;
    }
    return value;
  }

  /// JSON boolean or `null`.
  bool? optionalBoolean(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    if (value is! bool) {
      _wrongType(key, label, 'Wahrheitswert');
      return null;
    }
    return value;
  }

  // --- dates and times ------------------------------------------------------

  DateTime? _checkedInstant(String key, String label, Object? value) {
    if (value is! String) {
      _wrongType(key, label, 'Zeitpunkt als Text');
      return null;
    }
    final instant = BackupValues.tryParseInstant(value);
    if (instant == null) {
      fail(
        key,
        '$label ist kein gültiger UTC-Zeitpunkt '
        '(Format JJJJ-MM-TTThh:mm:ss.SSSZ)',
      );
    }
    return instant;
  }

  /// Required UTC instant `YYYY-MM-DDTHH:mm:ss.SSSZ`.
  DateTime instant(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok
        ? (_checkedInstant(key, label, value) ?? _placeholderInstant)
        : _placeholderInstant;
  }

  /// UTC instant or `null`.
  DateTime? optionalInstant(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedInstant(key, label, value);
  }

  LocalDate? _checkedDate(String key, String label, Object? value) {
    if (value is! String) {
      _wrongType(key, label, 'Datum als Text');
      return null;
    }
    final date = LocalDate.tryParse(value);
    if (date == null) {
      fail(key, '$label ist kein gültiges Datum (Format JJJJ-MM-TT)');
    }
    return date;
  }

  /// Required calendar date `YYYY-MM-DD` (a real date).
  LocalDate date(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    return ok
        ? (_checkedDate(key, label, value) ?? _placeholderDate)
        : _placeholderDate;
  }

  /// Calendar date or `null`.
  LocalDate? optionalDate(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    return _checkedDate(key, label, value);
  }

  /// Wall clock time `HH:mm` or `null`.
  LocalTime? optionalTime(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: true);
    if (!ok || value == null) {
      return null;
    }
    if (value is! String) {
      _wrongType(key, label, 'Uhrzeit als Text');
      return null;
    }
    final time = LocalTime.tryParse(value);
    if (time == null) {
      fail(key, '$label ist keine gültige Uhrzeit (Format HH:mm)');
    }
    return time;
  }

  // --- containers -----------------------------------------------------------

  /// Required nested JSON object (the `data` section).
  Map<String, Object?>? object(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    if (!ok) {
      return null;
    }
    if (value is! Map<String, Object?>) {
      _wrongType(key, label, 'Objekt');
      return null;
    }
    return value;
  }

  // --- lists ----------------------------------------------------------------

  List<Object?>? _rawList(String key, String label) {
    final (ok, value) = _fetch(key, label, nullable: false);
    if (!ok) {
      return null;
    }
    if (value is! List<Object?>) {
      _wrongType(key, label, 'Liste');
      return null;
    }
    return value;
  }

  /// A JSON array of known, pairwise different keys from [allowed]
  /// (`motivation_goals`, `muscle_groups`).
  List<String> keyList(String key, String label, List<String> allowed) {
    final raw = _rawList(key, label);
    if (raw == null) {
      return const [];
    }
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) {
        fail(key, '$label muss eine Liste von Texten sein');
        return const [];
      }
      if (!allowed.contains(item)) {
        fail(key, '$label enthält einen unbekannten Eintrag');
        return const [];
      }
      if (!seen.add(item)) {
        fail(key, '$label enthält doppelte Einträge');
        return const [];
      }
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }

  /// Task tags: at most [maxTags] texts of 1-[maxLength] characters, already
  /// trimmed and unique ignoring case.
  List<String> tagList(
    String key,
    String label, {
    int maxTags = 5,
    int maxLength = 20,
  }) {
    final raw = _rawList(key, label);
    if (raw == null) {
      return const [];
    }
    if (raw.length > maxTags) {
      fail(key, '$label enthält zu viele Einträge (höchstens $maxTags)');
      return const [];
    }
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) {
        fail(key, '$label muss eine Liste von Texten sein');
        return const [];
      }
      final length = BackupValues.characterCount(item);
      if (BackupValues.hasInvalidCharacters(item) ||
          length < 1 ||
          length > maxLength ||
          item != item.trim()) {
        fail(
          key,
          '$label enthält einen ungültigen Eintrag '
          '(1 bis $maxLength Zeichen, ohne Leerzeichen am Rand)',
        );
        return const [];
      }
      if (!seen.add(item.toLowerCase())) {
        fail(key, '$label enthält doppelte Einträge');
        return const [];
      }
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }
}

/// Reads one object with [read], rejects unknown fields and returns the result
/// only if the object is free of problems.
T? readObject<T>(FieldReader reader, T Function(FieldReader reader) read) {
  final value = read(reader);
  reader.finish();
  return reader.hasProblems ? null : value;
}

/// The strict `fromJson` of a single record: parses [json] as a record of
/// [table] and throws [BackupFormatException] listing every problem.
T parseStrictRecord<T extends Object>(
  BackupTable table,
  Map<String, Object?> json,
  T Function(FieldReader reader) read,
) {
  final problems = ProblemCollector();
  final value = readObject(FieldReader.record(table, 0, json, problems), read);
  if (value == null) {
    throw BackupFormatException(problems.toReport());
  }
  return value;
}
