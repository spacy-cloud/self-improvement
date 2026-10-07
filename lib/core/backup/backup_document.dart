import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_upgrade.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/dto/body_nutrition_dtos.dart';
import 'package:self_improvement/core/backup/dto/core_dtos.dart';
import 'package:self_improvement/core/backup/dto/focus_dtos.dart';
import 'package:self_improvement/core/backup/dto/task_dtos.dart';
import 'package:self_improvement/core/backup/field_reader.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';

/// The `data` object of a backup: all sections with typed records.
@immutable
final class BackupData {
  const BackupData({
    required this.profile,
    required this.appSettings,
    this.moduleStatusHistory = const [],
    this.dashboardCards = const [],
    this.goalVersions = const [],
    this.dailyGoalSnapshots = const [],
    this.weightEntries = const [],
    this.stepDays = const [],
    this.waterEntries = const [],
    this.mealEntries = const [],
    this.focusSessions = const [],
    this.workoutEntries = const [],
    this.workoutDayMarks = const [],
    this.tasks = const [],
    this.habits = const [],
    this.habitChecks = const [],
    this.reminderRules = const [],
  });

  final ProfileDto profile;
  final AppSettingsDto appSettings;
  final List<ModuleStatusDto> moduleStatusHistory;
  final List<DashboardCardDto> dashboardCards;
  final List<GoalVersionDto> goalVersions;
  final List<DailyGoalSnapshotDto> dailyGoalSnapshots;
  final List<WeightEntryDto> weightEntries;
  final List<StepDayDto> stepDays;
  final List<WaterEntryDto> waterEntries;
  final List<MealEntryDto> mealEntries;
  final List<FocusSessionDto> focusSessions;
  final List<WorkoutEntryDto> workoutEntries;
  final List<WorkoutDayMarkDto> workoutDayMarks;
  final List<TaskDto> tasks;
  final List<HabitDto> habits;
  final List<HabitCheckDto> habitChecks;
  final List<ReminderRuleDto> reminderRules;

  /// Number of records per section (the singletons count 1 each).
  Map<BackupTable, int> get counts => {
    BackupTable.profile: 1,
    BackupTable.appSettings: 1,
    BackupTable.moduleStatusHistory: moduleStatusHistory.length,
    BackupTable.dashboardCards: dashboardCards.length,
    BackupTable.goalVersions: goalVersions.length,
    BackupTable.dailyGoalSnapshots: dailyGoalSnapshots.length,
    BackupTable.weightEntries: weightEntries.length,
    BackupTable.stepDays: stepDays.length,
    BackupTable.waterEntries: waterEntries.length,
    BackupTable.mealEntries: mealEntries.length,
    BackupTable.focusSessions: focusSessions.length,
    BackupTable.workoutEntries: workoutEntries.length,
    BackupTable.workoutDayMarks: workoutDayMarks.length,
    BackupTable.tasks: tasks.length,
    BackupTable.habits: habits.length,
    BackupTable.habitChecks: habitChecks.length,
    BackupTable.reminderRules: reminderRules.length,
  };

  /// Total number of records, as counted by the import limit.
  int get recordCount => counts.values.fold(0, (sum, count) => sum + count);

  /// Sections in file order; keys are the stable table names.
  Map<String, Object?> toJson() => {
    BackupTable.profile.key: profile.toJson(),
    BackupTable.appSettings.key: appSettings.toJson(),
    BackupTable.moduleStatusHistory.key: [
      for (final r in moduleStatusHistory) r.toJson(),
    ],
    BackupTable.dashboardCards.key: [
      for (final r in dashboardCards) r.toJson(),
    ],
    BackupTable.goalVersions.key: [for (final r in goalVersions) r.toJson()],
    BackupTable.dailyGoalSnapshots.key: [
      for (final r in dailyGoalSnapshots) r.toJson(),
    ],
    BackupTable.weightEntries.key: [for (final r in weightEntries) r.toJson()],
    BackupTable.stepDays.key: [for (final r in stepDays) r.toJson()],
    BackupTable.waterEntries.key: [for (final r in waterEntries) r.toJson()],
    BackupTable.mealEntries.key: [for (final r in mealEntries) r.toJson()],
    BackupTable.focusSessions.key: [for (final r in focusSessions) r.toJson()],
    BackupTable.workoutEntries.key: [
      for (final r in workoutEntries) r.toJson(),
    ],
    BackupTable.workoutDayMarks.key: [
      for (final r in workoutDayMarks) r.toJson(),
    ],
    BackupTable.tasks.key: [for (final r in tasks) r.toJson()],
    BackupTable.habits.key: [for (final r in habits) r.toJson()],
    BackupTable.habitChecks.key: [for (final r in habitChecks) r.toJson()],
    BackupTable.reminderRules.key: [for (final r in reminderRules) r.toJson()],
  };
}

/// A complete, structurally valid backup (root fields plus [data]).
///
/// Record-level rules (types, ranges, enums, formats) hold for every object
/// that [fromJson] returns. Cross-record rules (unique ids, foreign keys, at
/// most one open session) are checked by `BackupValidator`.
///
/// A document always has the shape of the current version. One that was read
/// from an older file ([sourceSchemaVersion]) went through `BackupUpgrade`
/// and carries the values that older file means; writing it gives a current
/// file.
@immutable
final class BackupDocument {
  const BackupDocument({
    required this.exportedAtUtc,
    required this.appVersion,
    required this.data,
    this.sourceSchemaVersion = BackupFormat.schemaVersion,
  });

  /// Strict parser for the decoded root object; throws
  /// [BackupFormatException] listing every record-level problem.
  factory BackupDocument.fromJson(Map<String, Object?> json) {
    final problems = ProblemCollector();
    final draft = BackupParser(problems).parse(json);
    final document = problems.hasProblems ? null : draft.toDocument();
    if (document == null) {
      throw BackupFormatException(problems.toReport());
    }
    return document;
  }

  /// When the backup was created (UTC, millisecond precision).
  final DateTime exportedAtUtc;

  /// App version that wrote the file (informational).
  final String appVersion;

  final BackupData data;

  /// The `schemaVersion` of the file this document was read from; the current
  /// version for a document made from the database.
  final int sourceSchemaVersion;

  /// Root object in file order. Always the current version.
  Map<String, Object?> toJson() => {
    BackupFormat.rootFormat: BackupFormat.marker,
    BackupFormat.rootSchemaVersion: BackupFormat.schemaVersion,
    BackupFormat.rootExportedAtUtc: BackupValues.formatInstant(exportedAtUtc),
    BackupFormat.rootAppVersion: appVersion,
    BackupFormat.rootData: data.toJson(),
  };
}

/// Records of a parse run. Entries are `null` where a record was invalid, so
/// that list positions still equal the positions in the file. Used by the
/// validator to run cross-record checks on the valid records.
final class BackupDraft {
  /// The `schemaVersion` of the file, once it was accepted.
  int? sourceSchemaVersion;
  DateTime? exportedAtUtc;
  String? appVersion;
  ProfileDto? profile;
  AppSettingsDto? appSettings;
  final List<ModuleStatusDto?> moduleStatusHistory = [];
  final List<DashboardCardDto?> dashboardCards = [];
  final List<GoalVersionDto?> goalVersions = [];
  final List<DailyGoalSnapshotDto?> dailyGoalSnapshots = [];
  final List<WeightEntryDto?> weightEntries = [];
  final List<StepDayDto?> stepDays = [];
  final List<WaterEntryDto?> waterEntries = [];
  final List<MealEntryDto?> mealEntries = [];
  final List<FocusSessionDto?> focusSessions = [];
  final List<WorkoutEntryDto?> workoutEntries = [];
  final List<WorkoutDayMarkDto?> workoutDayMarks = [];
  final List<TaskDto?> tasks = [];
  final List<HabitDto?> habits = [];
  final List<HabitCheckDto?> habitChecks = [];
  final List<ReminderRuleDto?> reminderRules = [];

  /// Every readable habit id of the file, also of records that failed other
  /// checks, so that a broken habit does not cause bogus foreign key errors.
  final Set<String> habitIdsInFile = {};

  /// Whether the `habits` section was present as a list. Without it the
  /// foreign keys of the habit checks cannot be judged.
  bool habitsSectionRead = false;

  /// The document, or `null` if anything is missing or invalid.
  BackupDocument? toDocument() {
    final exportedAt = exportedAtUtc;
    final version = appVersion;
    final profileDto = profile;
    final settings = appSettings;
    if (exportedAt == null ||
        version == null ||
        profileDto == null ||
        settings == null) {
      return null;
    }
    List<T>? all<T extends Object>(List<T?> records) {
      final result = <T>[];
      for (final record in records) {
        if (record == null) {
          return null;
        }
        result.add(record);
      }
      return result;
    }

    final moduleStatus = all(moduleStatusHistory);
    final cards = all(dashboardCards);
    final goals = all(goalVersions);
    final snapshots = all(dailyGoalSnapshots);
    final weights = all(weightEntries);
    final steps = all(stepDays);
    final water = all(waterEntries);
    final meals = all(mealEntries);
    final focus = all(focusSessions);
    final workouts = all(workoutEntries);
    final marks = all(workoutDayMarks);
    final taskList = all(tasks);
    final habitList = all(habits);
    final checks = all(habitChecks);
    final rules = all(reminderRules);
    if (moduleStatus == null ||
        cards == null ||
        goals == null ||
        snapshots == null ||
        weights == null ||
        steps == null ||
        water == null ||
        meals == null ||
        focus == null ||
        workouts == null ||
        marks == null ||
        taskList == null ||
        habitList == null ||
        checks == null ||
        rules == null) {
      return null;
    }
    return BackupDocument(
      exportedAtUtc: exportedAt,
      appVersion: version,
      sourceSchemaVersion: sourceSchemaVersion ?? BackupFormat.schemaVersion,
      data: BackupData(
        profile: profileDto,
        appSettings: settings,
        moduleStatusHistory: moduleStatus,
        dashboardCards: cards,
        goalVersions: goals,
        dailyGoalSnapshots: snapshots,
        weightEntries: weights,
        stepDays: steps,
        waterEntries: water,
        mealEntries: meals,
        focusSessions: focus,
        workoutEntries: workouts,
        workoutDayMarks: marks,
        tasks: taskList,
        habits: habitList,
        habitChecks: checks,
        reminderRules: rules,
      ),
    );
  }
}

/// Reads the decoded root object into a [BackupDraft], collecting problems.
///
/// The format marker and the schema version are checked first; if either is
/// wrong the file is not interpreted any further (its other fields mean
/// nothing). A file of an older readable version is then brought to the
/// current version by `BackupUpgrade` and read like a current file. Likewise
/// an exceeded record limit stops before any record is parsed.
final class BackupParser {
  BackupParser(this._problems);

  final ProblemCollector _problems;

  static final RegExp _appVersionPattern = RegExp(
    r'^[0-9A-Za-z][0-9A-Za-z.+\-]*$',
  );

  /// `Version 1 und 2`, `Version 1, 2 und 3`, ...
  static String _supportedVersionsText() {
    final versions = BackupFormat.readableSchemaVersions;
    if (versions.length == 1) {
      return 'Version ${versions.single}';
    }
    final head = versions.sublist(0, versions.length - 1).join(', ');
    return 'Version $head und ${versions.last}';
  }

  BackupDraft parse(Map<String, Object?> root) {
    final draft = BackupDraft();
    if (root[BackupFormat.rootFormat] != BackupFormat.marker) {
      _problems.add(
        const ImportProblem(
          location: 'root',
          field: BackupFormat.rootFormat,
          message:
              'Die Datei ist keine Sicherung dieser App '
              '(Format-Kennung fehlt oder ist ungültig).',
        ),
      );
      return draft;
    }
    final version = root[BackupFormat.rootSchemaVersion];
    if (version is! int ||
        !BackupFormat.readableSchemaVersions.contains(version)) {
      _problems.add(
        ImportProblem(
          location: 'root',
          field: BackupFormat.rootSchemaVersion,
          message:
              'Die Schema-Version dieser Datei wird nicht unterstützt '
              '(unterstützt: ${_supportedVersionsText()}).',
        ),
      );
      return draft;
    }
    draft.sourceSchemaVersion = version;
    if (version < BackupFormat.schemaVersion) {
      root = BackupUpgrade.toCurrent(root, from: version, problems: _problems);
    }

    final reader = FieldReader(root, 'root', _problems);
    reader.constant(BackupFormat.rootFormat, 'Format', BackupFormat.marker);
    reader.integer(
      BackupFormat.rootSchemaVersion,
      'Schema-Version',
      min: BackupFormat.schemaVersion,
      max: BackupFormat.schemaVersion,
    );
    final exportedAt = reader.instant(
      BackupFormat.rootExportedAtUtc,
      'Exportzeitpunkt',
    );
    final appVersion = reader.text(
      BackupFormat.rootAppVersion,
      'App-Version',
      min: 1,
      max: 32,
    );
    if (appVersion.isNotEmpty && !_appVersionPattern.hasMatch(appVersion)) {
      reader.fail(
        BackupFormat.rootAppVersion,
        'App-Version hat ein ungültiges Format',
      );
    }
    final data = reader.object(BackupFormat.rootData, 'Datenabschnitt');
    reader.finish();
    if (!reader.hasProblems) {
      draft
        ..exportedAtUtc = exportedAt
        ..appVersion = appVersion;
    }
    if (data != null) {
      _parseData(data, draft);
    }
    return draft;
  }

  void _parseData(Map<String, Object?> data, BackupDraft draft) {
    for (final key in data.keys) {
      if (BackupTable.tryParse(key) == null) {
        _problems.add(
          ImportProblem(
            location: 'data',
            message: BackupFormat.technicalTables.contains(key)
                ? 'Technische Tabelle ist nicht Teil einer Sicherung'
                : 'Unbekannter Abschnitt',
          ),
        );
      }
    }
    var total = 0;
    for (final table in BackupTable.values) {
      final value = data[table.key];
      total += value is List ? value.length : (value is Map ? 1 : 0);
    }
    if (total > BackupFormat.maxRecords) {
      _problems.add(
        const ImportProblem(
          location: 'data',
          message:
              'Die Datei enthält mehr als 50.000 Datensätze und wird '
              'nicht importiert.',
        ),
      );
      return;
    }

    draft.profile = _readSingleton(
      data,
      BackupTable.profile,
      ProfileDto.read,
      'Es muss genau ein Profil als Objekt vorhanden sein',
    );
    draft.appSettings = _readSingleton(
      data,
      BackupTable.appSettings,
      AppSettingsDto.read,
      'Es muss genau ein Einstellungs-Objekt vorhanden sein',
    );
    _readList(
      data,
      BackupTable.moduleStatusHistory,
      ModuleStatusDto.read,
      draft.moduleStatusHistory,
    );
    _readList(
      data,
      BackupTable.dashboardCards,
      DashboardCardDto.read,
      draft.dashboardCards,
    );
    _readList(
      data,
      BackupTable.goalVersions,
      GoalVersionDto.read,
      draft.goalVersions,
    );
    _readList(
      data,
      BackupTable.dailyGoalSnapshots,
      DailyGoalSnapshotDto.read,
      draft.dailyGoalSnapshots,
    );
    _readList(
      data,
      BackupTable.weightEntries,
      WeightEntryDto.read,
      draft.weightEntries,
    );
    _readList(data, BackupTable.stepDays, StepDayDto.read, draft.stepDays);
    _readList(
      data,
      BackupTable.waterEntries,
      WaterEntryDto.read,
      draft.waterEntries,
    );
    _readList(
      data,
      BackupTable.mealEntries,
      MealEntryDto.read,
      draft.mealEntries,
    );
    _readList(
      data,
      BackupTable.focusSessions,
      FocusSessionDto.read,
      draft.focusSessions,
    );
    _readList(
      data,
      BackupTable.workoutEntries,
      WorkoutEntryDto.read,
      draft.workoutEntries,
    );
    _readList(
      data,
      BackupTable.workoutDayMarks,
      WorkoutDayMarkDto.read,
      draft.workoutDayMarks,
    );
    _readList(data, BackupTable.tasks, TaskDto.read, draft.tasks);
    draft.habitsSectionRead = _readList(
      data,
      BackupTable.habits,
      HabitDto.read,
      draft.habits,
      onRaw: (raw) {
        final id = raw['id'];
        if (id is String) {
          draft.habitIdsInFile.add(id);
        }
      },
    );
    _readList(
      data,
      BackupTable.habitChecks,
      HabitCheckDto.read,
      draft.habitChecks,
    );
    _readList(
      data,
      BackupTable.reminderRules,
      ReminderRuleDto.read,
      draft.reminderRules,
    );
  }

  T? _readSingleton<T extends Object>(
    Map<String, Object?> data,
    BackupTable table,
    T Function(FieldReader reader) read,
    String notSingleObject,
  ) {
    if (!data.containsKey(table.key)) {
      _problems.add(ImportProblem.table(table, 'Pflichtabschnitt fehlt'));
      return null;
    }
    final value = data[table.key];
    if (value is! Map<String, Object?>) {
      _problems.add(ImportProblem.table(table, notSingleObject));
      return null;
    }
    return readObject(FieldReader.record(table, 0, value, _problems), read);
  }

  /// Reads a list section into [into]; returns whether the section was a list.
  bool _readList<T extends Object>(
    Map<String, Object?> data,
    BackupTable table,
    T Function(FieldReader reader) read,
    List<T?> into, {
    void Function(Map<String, Object?> raw)? onRaw,
  }) {
    if (!data.containsKey(table.key)) {
      _problems.add(ImportProblem.table(table, 'Pflichtabschnitt fehlt'));
      return false;
    }
    final value = data[table.key];
    if (value is! List<Object?>) {
      _problems.add(
        ImportProblem.table(table, 'Abschnitt muss eine Liste sein'),
      );
      return false;
    }
    for (var index = 0; index < value.length; index++) {
      if (_problems.isFull) {
        return true;
      }
      final element = value[index];
      if (element is! Map<String, Object?>) {
        _problems.addRecord(table, index, 'Eintrag muss ein Objekt sein');
        into.add(null);
        continue;
      }
      onRaw?.call(element);
      into.add(
        readObject(FieldReader.record(table, index, element, _problems), read),
      );
    }
    return true;
  }
}
