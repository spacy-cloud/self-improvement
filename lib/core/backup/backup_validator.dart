import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';

/// Outcome of validating a backup file: the [report] and, if it is valid, the
/// typed [document].
@immutable
final class BackupValidationResult {
  const BackupValidationResult(this.report, this.document);

  final ImportValidationReport report;

  /// The validated document; `null` exactly when [report] has problems.
  final BackupDocument? document;

  bool get isValid => report.isValid;
}

/// Validates a backup file completely and without side effects.
///
/// Stages, each reporting every problem it finds (at most
/// [BackupFormat.maxReportedProblems] in total):
/// 1. file: size limit, UTF-8, JSON syntax, root is an object;
/// 2. root: format marker and schema version (a wrong one ends validation;
///    a readable older version is brought to the current one by
///    `BackupUpgrade`), the other root fields, no unknown fields;
/// 3. data: required sections, record limit (ends validation when exceeded);
/// 4. records: types, formats, ranges, enums, record-level rules (see the
///    DTOs);
/// 5. relations: unique ids and keys, foreign keys, at most one open session;
/// 6. optional [snapshotChecker], only for an otherwise valid file.
///
/// Nothing here touches the database: a rejected file never changes data.
final class BackupValidator {
  const BackupValidator({this.snapshotChecker});

  /// Optional cross-check of the daily goal snapshots (see
  /// [SnapshotConsistencyChecker]).
  final SnapshotConsistencyChecker? snapshotChecker;

  /// Validates the raw bytes of a backup file.
  BackupValidationResult validateBytes(Uint8List bytes) {
    final problems = ProblemCollector();
    if (bytes.length > BackupFormat.maxFileBytes) {
      return _rejected(
        problems,
        'file',
        'Die Datei ist größer als 10 MiB und wird nicht importiert.',
      );
    }
    if (bytes.isEmpty) {
      return _rejected(problems, 'file', 'Die Datei ist leer.');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return _rejected(
        problems,
        'file',
        'Die Datei ist kein gültiger UTF-8-Text.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return _rejected(
        problems,
        'file',
        'Die Datei enthält kein gültiges JSON.',
      );
    }
    return validateDecoded(decoded);
  }

  /// Validates an already decoded JSON value (stages 2 to 6).
  BackupValidationResult validateDecoded(Object? decoded) {
    final problems = ProblemCollector();
    if (decoded is! Map<String, Object?>) {
      return _rejected(
        problems,
        'file',
        'Die Datei hat nicht die erwartete Struktur '
            '(JSON-Objekt erwartet).',
      );
    }
    final draft = BackupParser(problems).parse(decoded);
    // Lists are incomplete once the report overflowed; relations would lie.
    if (!problems.isFull) {
      _checkRelations(draft, problems);
    }
    BackupDocument? document;
    if (!problems.hasProblems) {
      document = draft.toDocument();
      if (document == null) {
        problems.add(
          const ImportProblem(
            location: 'data',
            message: 'Die Datei ist unvollständig.',
          ),
        );
      }
    }
    final checker = snapshotChecker;
    if (document != null && checker != null) {
      checker.check(document.data).forEach(problems.add);
    }
    final report = problems.toReport();
    return BackupValidationResult(report, report.isValid ? document : null);
  }

  BackupValidationResult _rejected(
    ProblemCollector problems,
    String location,
    String message,
  ) {
    problems.add(ImportProblem(location: location, message: message));
    return BackupValidationResult(problems.toReport(), null);
  }

  // --- relations ------------------------------------------------------------

  void _checkRelations(BackupDraft d, ProblemCollector p) {
    _unique(
      p,
      BackupTable.moduleStatusHistory,
      d.moduleStatusHistory,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.dashboardCards,
      d.dashboardCards,
      (r) => r.cardId,
      'Dashboard-Karte kommt mehrfach vor',
      'card_id',
    );
    _unique(
      p,
      BackupTable.goalVersions,
      d.goalVersions,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.goalVersions,
      d.goalVersions,
      (r) => (r.goalType, r.effectiveFromDate),
      'Zielart und Gültig-ab-Datum kommen mehrfach vor',
      'effective_from_date',
    );
    _unique(
      p,
      BackupTable.dailyGoalSnapshots,
      d.dailyGoalSnapshots,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.dailyGoalSnapshots,
      d.dailyGoalSnapshots,
      (r) => (r.localDate, r.goalKey),
      'Datum und Zielschlüssel kommen mehrfach vor',
      'goal_key',
    );
    _unique(
      p,
      BackupTable.weightEntries,
      d.weightEntries,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.weightEntries,
      d.weightEntries,
      (r) => r.occurredAtUtc.millisecondsSinceEpoch,
      'Messzeitpunkt kommt mehrfach vor',
      'occurred_at_utc',
    );
    _unique(
      p,
      BackupTable.stepDays,
      d.stepDays,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.stepDays,
      d.stepDays,
      (r) => r.localDate,
      'Für dieses Datum gibt es mehrere Schritte-Einträge',
      'local_date',
    );
    _unique(
      p,
      BackupTable.waterEntries,
      d.waterEntries,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.mealEntries,
      d.mealEntries,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.focusSessions,
      d.focusSessions,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.workoutEntries,
      d.workoutEntries,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.workoutDayMarks,
      d.workoutDayMarks,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.workoutDayMarks,
      d.workoutDayMarks,
      (r) => r.localDate,
      'Für dieses Datum gibt es mehrere Markierungen',
      'local_date',
    );
    _unique(
      p,
      BackupTable.tasks,
      d.tasks,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.habits,
      d.habits,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.habitChecks,
      d.habitChecks,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );
    _unique(
      p,
      BackupTable.habitChecks,
      d.habitChecks,
      (r) => (r.habitId, r.localDate),
      'Für diese Gewohnheit und dieses Datum gibt es mehrere Checks',
      'local_date',
    );
    _unique(
      p,
      BackupTable.reminderRules,
      d.reminderRules,
      (r) => r.id,
      'ID kommt mehrfach vor',
      'id',
    );

    for (var i = 0; i < d.habitChecks.length && !p.isFull; i++) {
      final check = d.habitChecks[i];
      // Without a readable habits section the references cannot be judged.
      if (d.habitsSectionRead &&
          check != null &&
          !d.habitIdsInFile.contains(check.habitId)) {
        p.addRecord(
          BackupTable.habitChecks,
          i,
          'Verweis auf eine nicht vorhandene Gewohnheit',
          field: 'habit_id',
        );
      }
    }

    var openSessions = 0;
    for (var i = 0; i < d.focusSessions.length && !p.isFull; i++) {
      final session = d.focusSessions[i];
      if (session != null && session.isOpen && ++openSessions > 1) {
        p.addRecord(
          BackupTable.focusSessions,
          i,
          'Es darf höchstens eine offene Sitzung geben',
          field: 'status',
        );
      }
    }
  }

  /// Reports every record of [records] whose key was already used by an
  /// earlier record. Invalid (`null`) records are skipped.
  void _unique<T extends Object, K extends Object>(
    ProblemCollector problems,
    BackupTable table,
    List<T?> records,
    K Function(T record) keyOf,
    String message,
    String field,
  ) {
    final seen = <K>{};
    for (var i = 0; i < records.length; i++) {
      if (problems.isFull) {
        return;
      }
      final record = records[i];
      if (record != null && !seen.add(keyOf(record))) {
        problems.addRecord(table, i, message, field: field);
      }
    }
  }
}
