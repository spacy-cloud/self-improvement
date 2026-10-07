import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';

/// One problem found while validating a backup file.
///
/// The [message] is German and never contains values from the file (names,
/// notes, measurements): it names the rule, not the offending data.
@immutable
final class ImportProblem {
  const ImportProblem({
    required this.location,
    required this.message,
    this.field,
  });

  /// A problem with record [index] (0-based position in the array) of
  /// [table], e.g. `weight_entries[3]`.
  ImportProblem.record(BackupTable table, int index, this.message, {this.field})
    : location = table.isSingleton ? table.key : '${table.key}[$index]';

  /// A problem with a whole section, e.g. `weight_entries`.
  ImportProblem.table(BackupTable table, this.message)
    : location = table.key,
      field = null;

  /// Where the problem is: `file`, `root`, `data`, a section key or a record
  /// such as `weight_entries[3]`.
  final String location;

  /// Technical name of the offending field (a schema column), if any.
  final String? field;

  /// German explanation without personal data.
  final String message;

  /// `location: message`, e.g. `weight_entries[3]: Gewicht außerhalb des
  /// erlaubten Bereichs`.
  String get displayText => '$location: $message';

  @override
  String toString() => displayText;
}

/// All problems of a validation run (at most
/// [BackupFormat.maxReportedProblems]).
@immutable
final class ImportValidationReport {
  const ImportValidationReport(this.problems, {this.truncated = false});

  /// A report without problems.
  static const ImportValidationReport valid = ImportValidationReport([]);

  final List<ImportProblem> problems;

  /// More problems exist than are listed here.
  final bool truncated;

  bool get isValid => problems.isEmpty;

  /// German one-liner for the UI. Always states that existing data is
  /// untouched.
  String get summary {
    if (problems.isEmpty) {
      return 'Die Sicherung ist gültig.';
    }
    final count = truncated
        ? 'mehr als ${problems.length} Probleme'
        : problems.length == 1
        ? 'ein Problem'
        : '${problems.length} Probleme';
    return 'Die Sicherung wurde abgelehnt ($count, zuerst: '
        '${problems.first.displayText}). '
        'Deine vorhandenen Daten wurden nicht verändert.';
  }
}

/// Collects problems up to a limit. Further problems only set [isFull], so
/// callers can stop early and report that more exist.
final class ProblemCollector {
  ProblemCollector({this.limit = BackupFormat.maxReportedProblems});

  final int limit;
  final List<ImportProblem> _problems = [];
  bool _overflowed = false;

  /// More problems were found than fit into the report.
  bool get isFull => _overflowed;

  /// Number of problems kept so far.
  int get count => _problems.length;

  bool get hasProblems => _problems.isNotEmpty || _overflowed;

  void add(ImportProblem problem) {
    if (_problems.length >= limit) {
      _overflowed = true;
      return;
    }
    _problems.add(problem);
  }

  /// Convenience for [add] with a record location.
  void addRecord(
    BackupTable table,
    int index,
    String message, {
    String? field,
  }) => add(ImportProblem.record(table, index, message, field: field));

  ImportValidationReport toReport() => _problems.isEmpty && !_overflowed
      ? ImportValidationReport.valid
      : ImportValidationReport(
          List<ImportProblem>.unmodifiable(_problems),
          truncated: _overflowed,
        );
}

/// Thrown by the strict `fromJson` constructors when the input violates the
/// backup contract. The [report] lists every problem, without personal data.
final class BackupFormatException implements Exception {
  const BackupFormatException(this.report);

  final ImportValidationReport report;

  @override
  String toString() =>
      'BackupFormatException(${report.problems.length} problem(s))';
}
