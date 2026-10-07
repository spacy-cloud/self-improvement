import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_values.dart';
import 'package:self_improvement/core/backup/field_reader.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Backup record of the singleton `profile` (database id is always `local`).
@immutable
final class ProfileDto {
  const ProfileDto({
    required this.startedLocalDate,
    required this.motivationGoals,
    required this.onboardingCompleted,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.displayName,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.targetWeightGrams,
  });

  /// Strict parser; throws [BackupFormatException] listing every problem.
  factory ProfileDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.profile, json, read);

  factory ProfileDto.fromRow(ProfileRow row) => ProfileDto(
    displayName: row.displayName,
    startedLocalDate: row.startedLocalDate,
    heightCm: row.heightCm,
    ageYears: row.ageYears,
    startWeightGrams: row.startWeightGrams,
    targetWeightGrams: row.targetWeightGrams,
    motivationGoals: row.motivationGoals,
    onboardingCompleted: row.onboardingCompleted,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  /// Reads one object; problems go to the reader.
  static ProfileDto read(FieldReader r) {
    r.constant('id', 'ID', 'local');
    return ProfileDto(
      displayName: r.optionalText(
        'display_name',
        'Anzeigename',
        min: 1,
        max: 40,
      ),
      startedLocalDate: r.date('started_local_date', 'Startdatum'),
      heightCm: r.optionalInteger('height_cm', 'Größe', min: 100, max: 250),
      ageYears: r.optionalInteger('age_years', 'Alter', min: 18, max: 120),
      startWeightGrams: r.optionalInteger(
        'start_weight_grams',
        'Startgewicht',
        min: 20000,
        max: 350000,
        multipleOf: 100,
      ),
      targetWeightGrams: r.optionalInteger(
        'target_weight_grams',
        'Zielgewicht',
        min: 20000,
        max: 350000,
        multipleOf: 100,
      ),
      motivationGoals: r.keyList(
        'motivation_goals',
        'Motivationsziele',
        SchemaKeys.motivationGoals,
      ),
      onboardingCompleted: r.boolean(
        'onboarding_completed',
        'Onboarding-Status',
      ),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
  }

  final String? displayName;
  final LocalDate startedLocalDate;
  final int? heightCm;
  final int? ageYears;
  final int? startWeightGrams;
  final int? targetWeightGrams;
  final List<String> motivationGoals;
  final bool onboardingCompleted;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': 'local',
    'display_name': displayName,
    'started_local_date': startedLocalDate.toIso(),
    'height_cm': heightCm,
    'age_years': ageYears,
    'start_weight_grams': startWeightGrams,
    'target_weight_grams': targetWeightGrams,
    'motivation_goals': motivationGoals,
    'onboarding_completed': onboardingCompleted,
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  ProfileCompanion toCompanion() => ProfileCompanion.insert(
    id: const Value('local'),
    displayName: Value(displayName),
    startedLocalDate: startedLocalDate,
    heightCm: Value(heightCm),
    ageYears: Value(ageYears),
    startWeightGrams: Value(startWeightGrams),
    targetWeightGrams: Value(targetWeightGrams),
    motivationGoals: Value(motivationGoals),
    onboardingCompleted: Value(onboardingCompleted),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// Backup record of the singleton `app_settings` (database id is `app`).
///
/// `notifications_enabled` and `health_steps_sync_enabled` are desired states
/// only; the real permissions are never taken from a file.
@immutable
final class AppSettingsDto {
  const AppSettingsDto({
    required this.themeMode,
    required this.reduceMotion,
    required this.haptics,
    required this.notificationsEnabled,
    required this.healthStepsSyncEnabled,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.rowVersion,
    this.lastKnownTimezone,
    this.healthStepsLastSyncAtUtc,
  });

  factory AppSettingsDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.appSettings, json, read);

  factory AppSettingsDto.fromRow(AppSettingsRow row) => AppSettingsDto(
    themeMode: row.themeMode,
    reduceMotion: row.reduceMotion,
    haptics: row.haptics,
    notificationsEnabled: row.notificationsEnabled,
    lastKnownTimezone: row.lastKnownTimezone,
    healthStepsSyncEnabled: row.healthStepsSyncEnabled,
    healthStepsLastSyncAtUtc: row.healthStepsLastSyncAtUtc,
    createdAtUtc: row.createdAtUtc,
    updatedAtUtc: row.updatedAtUtc,
    rowVersion: row.rowVersion,
  );

  static AppSettingsDto read(FieldReader r) {
    r.constant('id', 'ID', 'app');
    return AppSettingsDto(
      themeMode: r.choice('theme_mode', 'Darstellung', SchemaKeys.themeModes),
      reduceMotion: r.boolean('reduce_motion', 'Bewegung reduzieren'),
      haptics: r.boolean('haptics', 'Haptik'),
      notificationsEnabled: r.boolean(
        'notifications_enabled',
        'Erinnerungen gewünscht',
      ),
      lastKnownTimezone: r.optionalTimezone(
        'last_known_timezone',
        'Zuletzt bekannte Zeitzone',
      ),
      healthStepsSyncEnabled: r.boolean(
        'health_steps_sync_enabled',
        'Schritte aus Health übernehmen',
      ),
      healthStepsLastSyncAtUtc: r.optionalInstant(
        'health_steps_last_sync_at_utc',
        'Letzter Schritteabgleich',
      ),
      createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
      updatedAtUtc: r.instant('updated_at_utc', 'Änderungszeitpunkt'),
      rowVersion: r.integer('row_version', 'Zeilenversion', min: 1),
    );
  }

  final String themeMode;
  final bool reduceMotion;
  final bool haptics;
  final bool notificationsEnabled;
  final String? lastKnownTimezone;

  /// Desired state of "Schritte aus Health übernehmen" (schema 2).
  final bool healthStepsSyncEnabled;

  /// When the last comparison with the health app finished (schema 2);
  /// informational.
  final DateTime? healthStepsLastSyncAtUtc;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final int rowVersion;

  Map<String, Object?> toJson() => {
    'id': 'app',
    'theme_mode': themeMode,
    'reduce_motion': reduceMotion,
    'haptics': haptics,
    'notifications_enabled': notificationsEnabled,
    'last_known_timezone': lastKnownTimezone,
    'health_steps_sync_enabled': healthStepsSyncEnabled,
    'health_steps_last_sync_at_utc': healthStepsLastSyncAtUtc == null
        ? null
        : BackupValues.formatInstant(healthStepsLastSyncAtUtc!),
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
    'updated_at_utc': BackupValues.formatInstant(updatedAtUtc),
    'row_version': rowVersion,
  };

  AppSettingsCompanion toCompanion() => AppSettingsCompanion.insert(
    id: const Value('app'),
    themeMode: Value(themeMode),
    reduceMotion: Value(reduceMotion),
    haptics: Value(haptics),
    notificationsEnabled: Value(notificationsEnabled),
    lastKnownTimezone: Value(lastKnownTimezone),
    healthStepsSyncEnabled: Value(healthStepsSyncEnabled),
    healthStepsLastSyncAtUtc: Value(healthStepsLastSyncAtUtc),
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc,
    rowVersion: Value(rowVersion),
  );
}

/// One entry of the append-only `module_status_history`.
@immutable
final class ModuleStatusDto {
  const ModuleStatusDto({
    required this.id,
    required this.moduleId,
    required this.effectiveAtUtc,
    required this.localDate,
    required this.enabled,
  });

  factory ModuleStatusDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.moduleStatusHistory, json, read);

  factory ModuleStatusDto.fromRow(ModuleStatusRow row) => ModuleStatusDto(
    id: row.id,
    moduleId: row.moduleId,
    effectiveAtUtc: row.effectiveAtUtc,
    localDate: row.localDate,
    enabled: row.enabled,
  );

  static ModuleStatusDto read(FieldReader r) => ModuleStatusDto(
    id: r.uuid('id', 'ID'),
    moduleId: r.choice('module_id', 'Modul', SchemaKeys.modules),
    effectiveAtUtc: r.instant('effective_at_utc', 'Gültig ab (Zeitpunkt)'),
    localDate: r.date('local_date', 'Datum'),
    enabled: r.boolean('enabled', 'Aktiv-Status'),
  );

  final String id;
  final String moduleId;
  final DateTime effectiveAtUtc;
  final LocalDate localDate;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'id': id,
    'module_id': moduleId,
    'effective_at_utc': BackupValues.formatInstant(effectiveAtUtc),
    'local_date': localDate.toIso(),
    'enabled': enabled,
  };

  ModuleStatusHistoryCompanion toCompanion() =>
      ModuleStatusHistoryCompanion.insert(
        id: id,
        moduleId: moduleId,
        effectiveAtUtc: effectiveAtUtc,
        localDate: localDate,
        enabled: enabled,
      );
}

/// Visibility and order of one dashboard card.
@immutable
final class DashboardCardDto {
  const DashboardCardDto({
    required this.cardId,
    required this.moduleId,
    required this.visible,
    required this.sortIndex,
  });

  factory DashboardCardDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.dashboardCards, json, read);

  factory DashboardCardDto.fromRow(DashboardCardRow row) => DashboardCardDto(
    cardId: row.cardId,
    moduleId: row.moduleId,
    visible: row.visible,
    sortIndex: row.sortIndex,
  );

  static DashboardCardDto read(FieldReader r) {
    final dto = DashboardCardDto(
      cardId: r.choice('card_id', 'Karten-ID', SchemaKeys.dashboardCards),
      moduleId: r.choice('module_id', 'Modul', SchemaKeys.modules),
      visible: r.boolean('visible', 'Sichtbarkeit'),
      sortIndex: r.integer('sort_index', 'Position', min: 0),
    );
    if (!r.hasProblems &&
        SchemaKeys.dashboardCardModule[dto.cardId] != dto.moduleId) {
      r.fail('module_id', 'Modul passt nicht zur Dashboard-Karte');
    }
    return dto;
  }

  final String cardId;
  final String moduleId;
  final bool visible;
  final int sortIndex;

  Map<String, Object?> toJson() => {
    'card_id': cardId,
    'module_id': moduleId,
    'visible': visible,
    'sort_index': sortIndex,
  };

  DashboardCardsCompanion toCompanion() => DashboardCardsCompanion.insert(
    cardId: cardId,
    moduleId: moduleId,
    visible: Value(visible),
    sortIndex: sortIndex,
  );
}

/// A goal value that applies from [effectiveFromDate] on.
@immutable
final class GoalVersionDto {
  const GoalVersionDto({
    required this.id,
    required this.goalType,
    required this.enabled,
    required this.effectiveFromDate,
    required this.createdAtUtc,
    this.targetInteger,
  });

  factory GoalVersionDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.goalVersions, json, read);

  factory GoalVersionDto.fromRow(GoalVersionRow row) => GoalVersionDto(
    id: row.id,
    goalType: row.goalType,
    targetInteger: row.targetInteger,
    enabled: row.enabled,
    effectiveFromDate: row.effectiveFromDate,
    createdAtUtc: row.createdAtUtc,
  );

  static GoalVersionDto read(FieldReader r) => GoalVersionDto(
    id: r.uuid('id', 'ID'),
    goalType: r.choice('goal_type', 'Zielart', SchemaKeys.goalTypes),
    targetInteger: r.optionalInteger('target_integer', 'Zielwert', min: 1),
    enabled: r.boolean('enabled', 'Aktiv-Status'),
    effectiveFromDate: r.date('effective_from_date', 'Gültig ab'),
    createdAtUtc: r.instant('created_at_utc', 'Erstellzeitpunkt'),
  );

  final String id;
  final String goalType;
  final int? targetInteger;
  final bool enabled;
  final LocalDate effectiveFromDate;
  final DateTime createdAtUtc;

  Map<String, Object?> toJson() => {
    'id': id,
    'goal_type': goalType,
    'target_integer': targetInteger,
    'enabled': enabled,
    'effective_from_date': effectiveFromDate.toIso(),
    'created_at_utc': BackupValues.formatInstant(createdAtUtc),
  };

  GoalVersionsCompanion toCompanion() => GoalVersionsCompanion.insert(
    id: id,
    goalType: goalType,
    targetInteger: Value(targetInteger),
    enabled: enabled,
    effectiveFromDate: effectiveFromDate,
    createdAtUtc: createdAtUtc,
  );
}

/// The goals that applied on one day (frozen thresholds). Whether a goal was
/// fulfilled is never stored.
@immutable
final class DailyGoalSnapshotDto {
  const DailyGoalSnapshotDto({
    required this.id,
    required this.localDate,
    required this.goalKey,
    required this.moduleId,
    required this.applicable,
    this.targetInteger,
  });

  factory DailyGoalSnapshotDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.dailyGoalSnapshots, json, read);

  factory DailyGoalSnapshotDto.fromRow(DailyGoalSnapshotRow row) =>
      DailyGoalSnapshotDto(
        id: row.id,
        localDate: row.localDate,
        goalKey: row.goalKey,
        moduleId: row.moduleId,
        targetInteger: row.targetInteger,
        applicable: row.applicable,
      );

  /// Prefix of the goal key of a habit goal: `habit:<habit id>`.
  static const String habitKeyPrefix = 'habit:';

  /// Whether [key] is a goal type or `habit:<uuid>`.
  static bool isKnownGoalKey(String key) {
    if (SchemaKeys.goalTypes.contains(key)) {
      return true;
    }
    return key.startsWith(habitKeyPrefix) &&
        BackupValues.isUuid(key.substring(habitKeyPrefix.length));
  }

  static DailyGoalSnapshotDto read(FieldReader r) {
    final dto = DailyGoalSnapshotDto(
      id: r.uuid('id', 'ID'),
      localDate: r.date('local_date', 'Datum'),
      goalKey: r.text('goal_key', 'Zielschlüssel', min: 1, max: 100),
      moduleId: r.choice('module_id', 'Modul', SchemaKeys.modules),
      targetInteger: r.optionalInteger('target_integer', 'Zielwert', min: 0),
      applicable: r.boolean('applicable', 'Anwendbarkeit'),
    );
    if (!r.hasProblems && !isKnownGoalKey(dto.goalKey)) {
      r.fail('goal_key', 'Zielschlüssel ist unbekannt');
    }
    return dto;
  }

  final String id;
  final LocalDate localDate;
  final String goalKey;
  final String moduleId;
  final int? targetInteger;
  final bool applicable;

  Map<String, Object?> toJson() => {
    'id': id,
    'local_date': localDate.toIso(),
    'goal_key': goalKey,
    'module_id': moduleId,
    'target_integer': targetInteger,
    'applicable': applicable,
  };

  DailyGoalSnapshotsCompanion toCompanion() =>
      DailyGoalSnapshotsCompanion.insert(
        id: id,
        localDate: localDate,
        goalKey: goalKey,
        moduleId: moduleId,
        targetInteger: Value(targetInteger),
        applicable: applicable,
      );
}

/// A user-configured reminder rule.
@immutable
final class ReminderRuleDto {
  const ReminderRuleDto({
    required this.id,
    required this.moduleId,
    required this.kind,
    required this.enabled,
    required this.route,
    this.localTime,
  });

  factory ReminderRuleDto.fromJson(Map<String, Object?> json) =>
      parseStrictRecord(BackupTable.reminderRules, json, read);

  factory ReminderRuleDto.fromRow(ReminderRuleRow row) => ReminderRuleDto(
    id: row.id,
    moduleId: row.moduleId,
    kind: row.kind,
    localTime: row.localTime,
    enabled: row.enabled,
    route: row.route,
  );

  /// An in-app route: starts with a single `/`, only URL path characters, no
  /// scheme and no host (`//host`).
  static final RegExp _routePattern = RegExp(
    r'^/(?!/)[A-Za-z0-9_\-./?=&%:~+@]*$',
  );

  static ReminderRuleDto read(FieldReader r) {
    final dto = ReminderRuleDto(
      id: r.uuid('id', 'ID'),
      moduleId: r.choice('module_id', 'Modul', SchemaKeys.modules),
      kind: r.choice('kind', 'Erinnerungsart', SchemaKeys.reminderKinds),
      localTime: r.optionalTime('local_time', 'Uhrzeit'),
      enabled: r.boolean('enabled', 'Aktiv-Status'),
      route: r.text('route', 'Ziel-Route', min: 1, max: 200),
    );
    if (!r.hasProblems && !_routePattern.hasMatch(dto.route)) {
      r.fail('route', 'Ziel-Route ist keine gültige App-Route');
    }
    return dto;
  }

  final String id;
  final String moduleId;
  final String kind;
  final LocalTime? localTime;
  final bool enabled;
  final String route;

  Map<String, Object?> toJson() => {
    'id': id,
    'module_id': moduleId,
    'kind': kind,
    'local_time': localTime?.toIso(),
    'enabled': enabled,
    'route': route,
  };

  ReminderRulesCompanion toCompanion() => ReminderRulesCompanion.insert(
    id: id,
    moduleId: moduleId,
    kind: kind,
    localTime: Value(localTime),
    enabled: enabled,
    route: route,
  );
}
