import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/field_reader.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// A to-do task. Open means the three completion fields are all `null`.
@immutable
final class TaskDto {
  const TaskDto({
    required this.id,
    required this.title,
    required this.priority,
    required this.tags,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.description,
    this.dueLocalDate,
    this.completedAtUtc,
    this.completedLocalDate,
    this.timezoneId,
    this.completionEligibility,
  });

  factory TaskDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.tasks, json, read);

  factory TaskDto.fromRow(TaskRow row) => TaskDto(
    id: row.id,
    title: row.title,
    description: row.description,
    priority: row.priority,
    dueLocalDate: row.dueLocalDate,
    tags: row.tagsJson,
    completedAtUtc: row.completedAtUtc,
    completedLocalDate: row.completedLocalDate,
    timezoneId: row.timezoneId,
    completionEligibility: row.completionEligibility,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static TaskDto read(FieldReader r) {
    final dto = TaskDto(
      id: r.uuid('id', 'ID'),
      title: r.text('title', 'Titel', min: 1, max: 120),
      description: r.optionalText('description', 'Beschreibung', max: 1000),
      priority: r.choice('priority', 'Priorität', SchemaKeys.taskPriorities),
      dueLocalDate: r.optionalDate('due_local_date', 'Fälligkeitsdatum'),
      tags: r.tagList('tags_json', 'Tags'),
      completedAtUtc: r.optionalInstant(
        'completed_at_utc',
        'Abschlusszeitpunkt',
      ),
      completedLocalDate: r.optionalDate(
        'completed_local_date',
        'Abschlussdatum',
      ),
      timezoneId: r.optionalTimezone('timezone_id', 'Zeitzone'),
      completionEligibility: r.optionalBoolean(
        'completion_eligibility',
        'Berechtigung beim Abschluss',
      ),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
    // The table's CHECK constraints: the completion triple is all or nothing.
    final completionFields = [
      dto.completedAtUtc != null,
      dto.completedLocalDate != null,
      dto.completionEligibility != null,
    ];
    if (!r.hasProblems && completionFields.toSet().length > 1) {
      r.fail(
        'completed_at_utc',
        'Abschlussangaben unvollständig (Zeitpunkt, Datum und '
            'Berechtigung gehören zusammen)',
      );
    }
    return dto;
  }

  /// Whether the task is completed.
  bool get isCompleted => completedAtUtc != null;

  final String id;
  final String title;
  final String? description;
  final String priority;
  final LocalDate? dueLocalDate;
  final List<String> tags;
  final DateTime? completedAtUtc;
  final LocalDate? completedLocalDate;
  final String? timezoneId;
  final bool? completionEligibility;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'priority': priority,
    'due_local_date': dueLocalDate?.toIso(),
    'tags_json': tags,
    'completed_at_utc': completedAtUtc == null
        ? null
        : BackupValues.formatInstant(completedAtUtc!),
    'completed_local_date': completedLocalDate?.toIso(),
    'timezone_id': timezoneId,
    'completion_eligibility': completionEligibility,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  TasksCompanion toCompanion() => TasksCompanion.insert(
    id: id,
    title: title,
    description: Value(description),
    priority: Value(priority),
    dueLocalDate: Value(dueLocalDate),
    tagsJson: Value(tags),
    completedAtUtc: Value(completedAtUtc),
    completedLocalDate: Value(completedLocalDate),
    timezoneId: Value(timezoneId),
    completionEligibility: Value(completionEligibility),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// A daily yes/no habit.
@immutable
final class HabitDto {
  const HabitDto({
    required this.id,
    required this.title,
    required this.startedLocalDate,
    required this.iconKey,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.archivedFromDate,
    this.reminderLocalTime,
  });

  factory HabitDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.habits, json, read);

  factory HabitDto.fromRow(HabitRow row) => HabitDto(
    id: row.id,
    title: row.title,
    startedLocalDate: row.startedLocalDate,
    archivedFromDate: row.archivedFromDate,
    reminderLocalTime: row.reminderLocalTime,
    iconKey: row.iconKey,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static HabitDto read(FieldReader r) {
    final dto = HabitDto(
      id: r.uuid('id', 'ID'),
      title: r.text('title', 'Titel', min: 1, max: 80),
      startedLocalDate: r.date('started_local_date', 'Startdatum'),
      archivedFromDate: r.optionalDate('archived_from_date', 'Archiviert ab'),
      reminderLocalTime: r.optionalTime(
        'reminder_local_time',
        'Erinnerungsuhrzeit',
      ),
      iconKey: r.choice('icon_key', 'Symbol', SchemaKeys.habitIcons),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
    final archived = dto.archivedFromDate;
    if (!r.hasProblems &&
        archived != null &&
        archived.isBefore(dto.startedLocalDate)) {
      r.fail('archived_from_date', 'Archivierungsdatum liegt vor dem Start');
    }
    return dto;
  }

  final String id;
  final String title;
  final LocalDate startedLocalDate;
  final LocalDate? archivedFromDate;
  final LocalTime? reminderLocalTime;
  final String iconKey;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'started_local_date': startedLocalDate.toIso(),
    'archived_from_date': archivedFromDate?.toIso(),
    'reminder_local_time': reminderLocalTime?.toIso(),
    'icon_key': iconKey,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  HabitsCompanion toCompanion() => HabitsCompanion.insert(
    id: id,
    title: title,
    startedLocalDate: startedLocalDate,
    archivedFromDate: Value(archivedFromDate),
    reminderLocalTime: Value(reminderLocalTime),
    iconKey: Value(iconKey),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// One check of a habit on one day.
@immutable
final class HabitCheckDto {
  const HabitCheckDto({
    required this.id,
    required this.habitId,
    required this.localDate,
    required this.checkedAtUtc,
    required this.timezoneId,
    required this.eligibility,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
  });

  factory HabitCheckDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.habitChecks, json, read);

  factory HabitCheckDto.fromRow(HabitCheckRow row) => HabitCheckDto(
    id: row.id,
    habitId: row.habitId,
    localDate: row.localDate,
    checkedAtUtc: row.checkedAtUtc,
    timezoneId: row.timezoneId,
    eligibility: row.eligibility,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static HabitCheckDto read(FieldReader r) => HabitCheckDto(
    id: r.uuid('id', 'ID'),
    habitId: r.uuid('habit_id', 'Gewohnheits-ID'),
    localDate: r.date('local_date', 'Datum'),
    checkedAtUtc: r.instant('checked_at_utc', 'Zeitpunkt des Checks'),
    timezoneId: r.timezone('timezone_id', 'Zeitzone'),
    eligibility: r.boolean('eligibility', 'Gamification-Berechtigung'),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
    updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
    rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
  );

  final String id;
  final String habitId;
  final LocalDate localDate;
  final DateTime checkedAtUtc;
  final String timezoneId;
  final bool eligibility;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'habit_id': habitId,
    'local_date': localDate.toIso(),
    'checked_at_utc': BackupValues.formatInstant(checkedAtUtc),
    'timezone_id': timezoneId,
    'eligibility': eligibility,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  HabitChecksCompanion toCompanion() => HabitChecksCompanion.insert(
    id: id,
    habitId: habitId,
    localDate: localDate,
    checkedAtUtc: checkedAtUtc,
    timezoneId: timezoneId,
    eligibility: eligibility,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}
