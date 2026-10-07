import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/field_reader.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A focus countdown session.
///
/// A backup never contains a `running` session: the exporter writes it as
/// `paused` with the duration computed at export time, so
/// `segment_started_at_utc` is always `null` in V1 files. The field stays in
/// the contract because it is a column of the schema.
@immutable
final class FocusSessionDto {
  const FocusSessionDto({
    required this.id,
    required this.category,
    required this.plannedSeconds,
    required this.accumulatedSeconds,
    required this.startedAtUtc,
    required this.timezoneId,
    required this.status,
    required this.gamificationEligible,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.segmentStartedAtUtc,
    this.endedAtUtc,
    this.completedLocalDate,
    this.note,
  });

  factory FocusSessionDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.focusSessions, json, read);

  factory FocusSessionDto.fromRow(FocusSessionRow row) => FocusSessionDto(
    id: row.id,
    category: row.category,
    plannedSeconds: row.plannedSeconds,
    accumulatedSeconds: row.accumulatedSeconds,
    segmentStartedAtUtc: row.segmentStartedAtUtc,
    startedAtUtc: row.startedAtUtc,
    endedAtUtc: row.endedAtUtc,
    completedLocalDate: row.completedLocalDate,
    timezoneId: row.timezoneId,
    status: row.status,
    note: row.note,
    gamificationEligible: row.gamificationEligible,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static FocusSessionDto read(FieldReader r) {
    final dto = FocusSessionDto(
      id: r.uuid('id', 'ID'),
      category: r.choice('category', 'Kategorie', SchemaKeys.focusCategories),
      plannedSeconds: r.integer(
        'planned_seconds',
        'Geplante Dauer',
        min: 300,
        max: 10800,
      ),
      accumulatedSeconds: r.integer(
        'accumulated_seconds',
        'Bisherige Dauer',
        min: 0,
      ),
      segmentStartedAtUtc: r.optionalInstant(
        'segment_started_at_utc',
        'Start des laufenden Abschnitts',
      ),
      startedAtUtc: r.instant('started_at_utc', 'Startzeitpunkt'),
      endedAtUtc: r.optionalInstant('ended_at_utc', 'Endzeitpunkt'),
      completedLocalDate: r.optionalDate(
        'completed_local_date',
        'Abschlussdatum',
      ),
      timezoneId: r.timezone('timezone_id', 'Zeitzone'),
      status: r.choice('status', 'Status', SchemaKeys.focusStatuses),
      note: r.optionalText('note', 'Notiz', max: 500),
      gamificationEligible: r.boolean(
        'gamification_eligible',
        'Gamification-Berechtigung',
      ),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
    if (!r.hasProblems) {
      dto._checkConsistency(r);
    }
    return dto;
  }

  /// Rules that span several fields (the table's CHECK constraints plus the
  /// "no running session in a backup" and "ended after started" rules).
  void _checkConsistency(FieldReader r) {
    if (accumulatedSeconds > plannedSeconds) {
      r.fail(
        'accumulated_seconds',
        'Bisherige Dauer ist größer als die geplante Dauer',
      );
    }
    if (status == 'running') {
      r.fail(
        'status',
        'Eine laufende Sitzung darf nicht in einer Sicherung stehen '
            '(sie wird als pausiert gesichert)',
      );
    } else if (segmentStartedAtUtc != null) {
      r.fail(
        'segment_started_at_utc',
        'Start des laufenden Abschnitts passt nicht zum Status',
      );
    }
    if ((status == 'completed') != (completedLocalDate != null)) {
      r.fail(
        'completed_local_date',
        'Abschlussdatum passt nicht zum Status '
            '(nur abgeschlossene Sitzungen haben eins)',
      );
    }
    final ended = endedAtUtc;
    if (ended != null && ended.isBefore(startedAtUtc)) {
      r.fail('ended_at_utc', 'Endzeitpunkt liegt vor dem Startzeitpunkt');
    }
  }

  /// Whether the session is still open (not completed or discarded).
  bool get isOpen => SchemaKeys.focusOpenStatuses.contains(status);

  /// How a `running` session is written to a backup: `paused`, with the time
  /// of the current segment added to the accumulated seconds as of [nowUtc]
  /// (`clamp(accumulated + floor(now - segmentStart), 0, planned)`; a clock
  /// set backwards counts as zero) and no running segment. Other sessions are
  /// returned unchanged. The database row itself is never touched.
  FocusSessionDto exportedAt(DateTime nowUtc) {
    final segmentStart = segmentStartedAtUtc;
    if (status != 'running' || segmentStart == null) {
      return this;
    }
    final elapsedMillis =
        nowUtc.millisecondsSinceEpoch - segmentStart.millisecondsSinceEpoch;
    final elapsedSeconds = elapsedMillis <= 0 ? 0 : elapsedMillis ~/ 1000;
    return FocusSessionDto(
      id: id,
      category: category,
      plannedSeconds: plannedSeconds,
      accumulatedSeconds: min(
        plannedSeconds,
        accumulatedSeconds + elapsedSeconds,
      ),
      startedAtUtc: startedAtUtc,
      endedAtUtc: endedAtUtc,
      completedLocalDate: completedLocalDate,
      timezoneId: timezoneId,
      status: 'paused',
      note: note,
      gamificationEligible: gamificationEligible,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc,
      rowVersion: rowVersion,
    );
  }

  final String id;
  final String category;
  final int plannedSeconds;
  final int accumulatedSeconds;
  final DateTime? segmentStartedAtUtc;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final LocalDate? completedLocalDate;
  final String timezoneId;
  final String status;
  final String? note;
  final bool gamificationEligible;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category,
    'planned_seconds': plannedSeconds,
    'accumulated_seconds': accumulatedSeconds,
    'segment_started_at_utc': segmentStartedAtUtc == null
        ? null
        : BackupValues.formatInstant(segmentStartedAtUtc!),
    'started_at_utc': BackupValues.formatInstant(startedAtUtc),
    'ended_at_utc': endedAtUtc == null
        ? null
        : BackupValues.formatInstant(endedAtUtc!),
    'completed_local_date': completedLocalDate?.toIso(),
    'timezone_id': timezoneId,
    'status': status,
    'note': note,
    'gamification_eligible': gamificationEligible,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  FocusSessionsCompanion toCompanion() => FocusSessionsCompanion.insert(
    id: id,
    category: category,
    plannedSeconds: plannedSeconds,
    accumulatedSeconds: Value(accumulatedSeconds),
    segmentStartedAtUtc: Value(segmentStartedAtUtc),
    startedAtUtc: startedAtUtc,
    endedAtUtc: Value(endedAtUtc),
    completedLocalDate: Value(completedLocalDate),
    timezoneId: timezoneId,
    status: status,
    note: Value(note),
    gamificationEligible: Value(gamificationEligible),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// One manually logged workout.
@immutable
final class WorkoutEntryDto {
  const WorkoutEntryDto({
    required this.id,
    required this.trainingCategory,
    required this.durationMinutes,
    required this.muscleGroups,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.gamificationEligible,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.title,
    this.intensity,
    this.note,
  });

  factory WorkoutEntryDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.workoutEntries, json, read);

  factory WorkoutEntryDto.fromRow(WorkoutEntryRow row) => WorkoutEntryDto(
    id: row.id,
    trainingCategory: row.trainingCategory,
    title: row.title,
    durationMinutes: row.durationMinutes,
    muscleGroups: row.muscleGroups,
    intensity: row.intensity,
    occurredAtUtc: row.occurredAtUtc,
    localDate: row.localDate,
    timezoneId: row.timezoneId,
    note: row.note,
    gamificationEligible: row.gamificationEligible,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static WorkoutEntryDto read(FieldReader r) => WorkoutEntryDto(
    id: r.uuid('id', 'ID'),
    trainingCategory: r.choice(
      'training_category',
      'Trainingsart',
      SchemaKeys.trainingCategories,
    ),
    title: r.optionalText('title', 'Titel', min: 1, max: 80),
    durationMinutes: r.integer('duration_minutes', 'Dauer', min: 1, max: 600),
    muscleGroups: r.keyList(
      'muscle_groups',
      'Muskelgruppen',
      SchemaKeys.muscleGroups,
    ),
    intensity: r.optionalChoice(
      'intensity',
      'Intensität',
      SchemaKeys.workoutIntensities,
    ),
    occurredAtUtc: r.instant('occurred_at_utc', 'Zeitpunkt'),
    localDate: r.date('local_date', 'Datum'),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    note: r.optionalText('note', 'Notiz', max: 500),
    gamificationEligible: r.boolean(
      'gamification_eligible',
      'Gamification-Berechtigung',
    ),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final String trainingCategory;
  final String? title;
  final int durationMinutes;
  final List<String> muscleGroups;
  final String? intensity;
  final DateTime occurredAtUtc;
  final LocalDate localDate;
  final String timezoneId;
  final String? note;
  final bool gamificationEligible;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'training_category': trainingCategory,
    'title': title,
    'duration_minutes': durationMinutes,
    'muscle_groups': muscleGroups,
    'intensity': intensity,
    'occurred_at_utc': BackupValues.formatInstant(occurredAtUtc),
    'local_date': localDate.toIso(),
    'timezone_id': timezoneId,
    'note': note,
    'gamification_eligible': gamificationEligible,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  WorkoutEntriesCompanion toCompanion() => WorkoutEntriesCompanion.insert(
    id: id,
    trainingCategory: trainingCategory,
    title: Value(title),
    durationMinutes: durationMinutes,
    muscleGroups: Value(muscleGroups),
    intensity: Value(intensity),
    occurredAtUtc: occurredAtUtc,
    localDate: localDate,
    timezoneId: timezoneId,
    note: Value(note),
    gamificationEligible: gamificationEligible,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// A day marked as a rest day or as a skipped workout (schema 2).
@immutable
final class WorkoutDayMarkDto {
  const WorkoutDayMarkDto({
    required this.id,
    required this.localDate,
    required this.kind,
    required this.timezoneId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
  });

  factory WorkoutDayMarkDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.workoutDayMarks, json, read);

  factory WorkoutDayMarkDto.fromRow(WorkoutDayMarkRow row) => WorkoutDayMarkDto(
    id: row.id,
    localDate: row.localDate,
    kind: row.kind,
    timezoneId: row.timezoneId,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static WorkoutDayMarkDto read(FieldReader r) => WorkoutDayMarkDto(
    id: r.uuid('id', 'ID'),
    localDate: r.date('local_date', 'Datum'),
    kind: r.choice('kind', 'Art', SchemaKeys.workoutDayMarkKinds),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final LocalDate localDate;

  /// `rest` or `skipped` (see `SchemaKeys.workoutDayMarkKinds`).
  final String kind;
  final String timezoneId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'local_date': localDate.toIso(),
    'kind': kind,
    'timezone_id': timezoneId,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  WorkoutDayMarksCompanion toCompanion() => WorkoutDayMarksCompanion.insert(
    id: id,
    localDate: localDate,
    kind: kind,
    timezoneId: timezoneId,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}
