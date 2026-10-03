import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/time/clock_service.dart';

import 'support/backup_fixtures.dart';

/// A field rule: values the validator must reject and values (the
/// boundaries) it must accept.
final class FieldRule {
  const FieldRule(
    this.table,
    this.field, {
    this.invalid = const [],
    this.valid = const [],
    this.index = 0,
    this.alsoSet = const {},
  });

  final BackupTable table;
  final String field;
  final int index;
  final List<Object?> invalid;
  final List<Object?> valid;

  /// Other fields set together with the tested one so that no other rule
  /// interferes.
  final Map<String, Object?> alsoSet;
}

final String longText = 'x' * 600;
final String upperUuid = uuid(0xABC).toUpperCase();

const List<Object?> badInstants = [
  '2026-03-02T06:30:15Z',
  '2026-03-02T06:30:15.250+01:00',
  '2026-03-02',
  '2026-02-30T06:30:15.250Z',
  1772433015250,
  null,
];
const List<Object?> goodInstants = [
  '2026-03-02T06:30:15.250Z',
  '1999-12-31T23:59:59.999Z',
];
const List<Object?> badDates = [
  '2026-02-30',
  '2026-2-3',
  '03.10.2026',
  '2026-13-01',
  '2026-10-03T00:00:00.000Z',
  ' 2026-10-03',
  20261003,
  null,
];
const List<Object?> goodDates = ['2024-02-29', '2026-12-31', '2026-01-01'];
const List<Object?> badBools = [1, 0, 'true', null];
const List<Object?> badRowVersions = [0, -1, 1.5, '1', null];
const List<Object?> goodRowVersions = [1, 2, 4294967296];
const List<Object?> badZones = ['Mars/Base', '', 'europe/berlin', 5, null];
const List<Object?> goodZones = [
  'UTC',
  'Europe/Berlin',
  'Etc/UTC',
  'Asia/Tokyo',
];

List<FieldRule> auditRules(BackupTable table) => [
  FieldRule(table, 'created_at_utc', invalid: badInstants, valid: goodInstants),
  FieldRule(table, 'updated_at_utc', invalid: badInstants, valid: goodInstants),
  FieldRule(
    table,
    'row_version',
    invalid: badRowVersions,
    valid: goodRowVersions,
  ),
];

FieldRule idRule(BackupTable table) => FieldRule(
  table,
  'id',
  invalid: ['x', '', upperUuid, 123, null, 'local'],
  valid: [uuid(0xABC)],
);

FieldRule zoneRule(BackupTable table) =>
    FieldRule(table, 'timezone_id', invalid: badZones, valid: goodZones);

FieldRule boolRule(BackupTable table, String field) =>
    FieldRule(table, field, invalid: badBools, valid: [true, false]);

FieldRule noteRule(BackupTable table) => FieldRule(
  table,
  'note',
  invalid: [longText, 'x' * 501, 5],
  valid: ['x' * 500, '', null, '\u{1F600}' * 500, 'Zeile 1\nZeile 2'],
);

final List<FieldRule> fieldRules = [
  // --- profile -------------------------------------------------------------
  FieldRule(
    BackupTable.profile,
    'display_name',
    invalid: ['', 'x' * 41, 7, 'a\u0000b', '\ud800'],
    valid: ['A', 'x' * 40, '\u{1F600}' * 40, null],
  ),
  FieldRule(
    BackupTable.profile,
    'started_local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  FieldRule(
    BackupTable.profile,
    'height_cm',
    invalid: [99, 251, '168', 168.5, 0, -1],
    valid: [100, 250, 168, null],
  ),
  FieldRule(
    BackupTable.profile,
    'age_years',
    invalid: [17, 121, '34', 34.5, 0],
    valid: [18, 120, 34, null],
  ),
  FieldRule(
    BackupTable.profile,
    'start_weight_grams',
    invalid: [19900, 350100, 70050, 70001, '70000', 0, -100],
    valid: [20000, 350000, 70000, null],
  ),
  FieldRule(
    BackupTable.profile,
    'target_weight_grams',
    invalid: [19900, 350100, 70050, 70001, '70000', 0, -100],
    valid: [20000, 350000, 70000, null],
  ),
  FieldRule(
    BackupTable.profile,
    'motivation_goals',
    invalid: [
      ['unknown'],
      ['move_more', 'move_more'],
      'move_more',
      [1],
      null,
      ['Move_More'],
    ],
    valid: [
      <String>[],
      [
        'lose_weight',
        'get_fitter',
        'move_more',
        'live_healthier',
        'build_habits',
      ],
      ['build_habits'],
    ],
  ),
  boolRule(BackupTable.profile, 'onboarding_completed'),
  ...auditRules(BackupTable.profile),
  // --- app_settings --------------------------------------------------------
  FieldRule(
    BackupTable.appSettings,
    'theme_mode',
    invalid: ['neon', 'System', '', 1, null],
    valid: ['system', 'light', 'dark', 'oled'],
  ),
  boolRule(BackupTable.appSettings, 'reduce_motion'),
  boolRule(BackupTable.appSettings, 'haptics'),
  boolRule(BackupTable.appSettings, 'notifications_enabled'),
  FieldRule(
    BackupTable.appSettings,
    'last_known_timezone',
    invalid: ['Mars/Base', '', 5],
    valid: ['UTC', 'Europe/Berlin', null],
  ),
  ...auditRules(BackupTable.appSettings),
  // --- module_status_history -----------------------------------------------
  idRule(BackupTable.moduleStatusHistory),
  FieldRule(
    BackupTable.moduleStatusHistory,
    'module_id',
    invalid: ['sleep', 'Body', '', 3, null],
    valid: ['body', 'nutrition', 'focus', 'tasks', 'gamification'],
  ),
  FieldRule(
    BackupTable.moduleStatusHistory,
    'effective_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  FieldRule(
    BackupTable.moduleStatusHistory,
    'local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  boolRule(BackupTable.moduleStatusHistory, 'enabled'),
  // --- dashboard_cards -----------------------------------------------------
  FieldRule(
    BackupTable.dashboardCards,
    'card_id',
    invalid: ['sleep', 'XP', '', 1, null],
    valid: ['xp'],
  ),
  FieldRule(
    BackupTable.dashboardCards,
    'module_id',
    invalid: ['sleep', '', 1, null],
    valid: ['gamification'],
  ),
  boolRule(BackupTable.dashboardCards, 'visible'),
  FieldRule(
    BackupTable.dashboardCards,
    'sort_index',
    invalid: [-1, 1.5, '1', null],
    valid: [0, 1, 7, 99],
  ),
  // --- goal_versions -------------------------------------------------------
  idRule(BackupTable.goalVersions),
  FieldRule(
    BackupTable.goalVersions,
    'goal_type',
    invalid: ['sleep', 'Water', '', 1, null],
    valid: [
      'water',
      'steps',
      'weight_entry',
      'focus_minutes',
      'task_completion',
      'workout_weekly',
    ],
    // A different type does not collide with another version's date.
    index: 4,
  ),
  FieldRule(
    BackupTable.goalVersions,
    'target_integer',
    invalid: [0, -1, 2.5, '2500'],
    valid: [1, 2500, 1000000, null],
  ),
  boolRule(BackupTable.goalVersions, 'enabled'),
  FieldRule(
    BackupTable.goalVersions,
    'effective_from_date',
    invalid: badDates,
    valid: ['2024-02-29', '2026-12-31'],
  ),
  FieldRule(
    BackupTable.goalVersions,
    'created_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  // --- daily_goal_snapshots ------------------------------------------------
  idRule(BackupTable.dailyGoalSnapshots),
  FieldRule(
    BackupTable.dailyGoalSnapshots,
    'local_date',
    invalid: badDates,
    valid: ['2024-02-29', '2026-12-31'],
  ),
  FieldRule(
    BackupTable.dailyGoalSnapshots,
    'goal_key',
    invalid: ['sleep', 'habit:', 'habit:not-a-uuid', 'Water', '', 5, null],
    valid: ['steps', 'workout_weekly', 'habit:${uuid(0x999)}'],
    index: 1,
  ),
  FieldRule(
    BackupTable.dailyGoalSnapshots,
    'module_id',
    invalid: ['sleep', '', 3, null],
    valid: ['body', 'gamification'],
  ),
  FieldRule(
    BackupTable.dailyGoalSnapshots,
    'target_integer',
    invalid: [-1, 2.5, '2500'],
    valid: [0, 1, 2500, null],
  ),
  boolRule(BackupTable.dailyGoalSnapshots, 'applicable'),
  // --- weight_entries ------------------------------------------------------
  idRule(BackupTable.weightEntries),
  FieldRule(
    BackupTable.weightEntries,
    'weight_grams',
    invalid: [19900, 350100, 71550, 71501, '71500', 71500.0, 0, -100, null],
    valid: [20000, 350000, 71500, 20100],
  ),
  FieldRule(
    BackupTable.weightEntries,
    'occurred_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  FieldRule(
    BackupTable.weightEntries,
    'local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  zoneRule(BackupTable.weightEntries),
  boolRule(BackupTable.weightEntries, 'before_toilet'),
  boolRule(BackupTable.weightEntries, 'after_drinking'),
  boolRule(BackupTable.weightEntries, 'after_eating'),
  noteRule(BackupTable.weightEntries),
  boolRule(BackupTable.weightEntries, 'gamification_eligible'),
  ...auditRules(BackupTable.weightEntries),
  // --- step_days -----------------------------------------------------------
  idRule(BackupTable.stepDays),
  FieldRule(
    BackupTable.stepDays,
    'local_date',
    invalid: badDates,
    valid: ['2024-02-29', '2026-12-31'],
  ),
  FieldRule(
    BackupTable.stepDays,
    'steps',
    invalid: [-1, 100001, '8450', 8450.5, null],
    valid: [0, 1, 100000],
  ),
  FieldRule(
    BackupTable.stepDays,
    'reached_goal_eligible',
    invalid: [1, 0, 'true'],
    valid: [true, false],
  ),
  FieldRule(
    BackupTable.stepDays,
    'xp_goal_target_steps',
    invalid: [0, -1, '8000', 8000.5],
    valid: [1, 8000, 100000],
  ),
  zoneRule(BackupTable.stepDays),
  ...auditRules(BackupTable.stepDays),
  // --- water_entries -------------------------------------------------------
  idRule(BackupTable.waterEntries),
  FieldRule(
    BackupTable.waterEntries,
    'amount_ml',
    invalid: [49, 2001, 0, -250, '250', 250.5, null],
    valid: [50, 250, 2000],
  ),
  FieldRule(
    BackupTable.waterEntries,
    'occurred_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  FieldRule(
    BackupTable.waterEntries,
    'local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  zoneRule(BackupTable.waterEntries),
  noteRule(BackupTable.waterEntries),
  boolRule(BackupTable.waterEntries, 'gamification_eligible'),
  ...auditRules(BackupTable.waterEntries),
  // --- meal_entries --------------------------------------------------------
  idRule(BackupTable.mealEntries),
  FieldRule(
    BackupTable.mealEntries,
    'name',
    invalid: ['', 'x' * 81, 5, null, 'a\u0000'],
    valid: ['x', 'x' * 80, '\u{1F600}' * 80],
  ),
  FieldRule(
    BackupTable.mealEntries,
    'kcal',
    invalid: [-1, 5001, '450', 450.5],
    valid: [0, 450, 5000, null],
  ),
  FieldRule(
    BackupTable.mealEntries,
    'occurred_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  FieldRule(
    BackupTable.mealEntries,
    'local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  zoneRule(BackupTable.mealEntries),
  noteRule(BackupTable.mealEntries),
  ...auditRules(BackupTable.mealEntries),
  // --- focus_sessions (index 1 is a discarded session, 2 is paused) --------
  idRule(BackupTable.focusSessions),
  FieldRule(
    BackupTable.focusSessions,
    'category',
    invalid: ['sleep', 'Reading', '', 1, null],
    valid: ['reading', 'learning', 'programming', 'meditation', 'other'],
  ),
  FieldRule(
    BackupTable.focusSessions,
    'planned_seconds',
    invalid: [299, 10801, 0, '600', 600.5, null],
    valid: [300, 600, 10800],
    index: 1,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'accumulated_seconds',
    invalid: [-1, 601, '120', null],
    valid: [0, 120, 600],
    index: 1,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'started_at_utc',
    invalid: badInstants,
    valid: ['2026-03-03T09:00:00.000Z', '2026-03-03T08:00:00.000Z'],
    index: 1,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'timezone_id',
    invalid: badZones,
    valid: goodZones,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'status',
    invalid: ['sleeping', 'Paused', '', 1, null],
    valid: ['paused', 'awaiting_confirmation', 'discarded'],
    index: 2,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'segment_started_at_utc',
    invalid: ['2026-03-04T14:10:00Z', 5, 'x'],
    valid: [null],
    index: 2,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'ended_at_utc',
    invalid: ['x', 5, '2026-03-03', '2026-03-03T09:02:00Z'],
    valid: [null, '2026-03-03T09:00:00.000Z', '2026-03-03T10:00:00.000Z'],
    index: 1,
  ),
  FieldRule(
    BackupTable.focusSessions,
    'completed_local_date',
    invalid: ['2026-02-30', '03.10.2026', 20260302, null],
    valid: ['2026-03-02', '2024-02-29', '2026-03-03'],
  ),
  noteRule(BackupTable.focusSessions),
  boolRule(BackupTable.focusSessions, 'gamification_eligible'),
  ...auditRules(BackupTable.focusSessions),
  // --- workout_entries -----------------------------------------------------
  idRule(BackupTable.workoutEntries),
  FieldRule(
    BackupTable.workoutEntries,
    'training_category',
    invalid: ['yoga', 'Strength', '', 1, null],
    valid: ['strength', 'cardio', 'mobility', 'sport'],
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'title',
    invalid: ['', 'x' * 81, 5],
    valid: ['x', 'x' * 80, null],
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'duration_minutes',
    invalid: [0, 601, -5, '45', 45.5, null],
    valid: [1, 45, 600],
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'muscle_groups',
    invalid: [
      ['abs'],
      ['chest', 'chest'],
      'chest',
      [1],
      null,
    ],
    valid: [
      <String>[],
      [
        'chest',
        'shoulders',
        'back',
        'biceps',
        'triceps',
        'legs',
        'core',
        'full_body',
      ],
    ],
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'intensity',
    invalid: ['extreme', 'High', '', 5],
    valid: ['low', 'moderate', 'high', null],
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'occurred_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  FieldRule(
    BackupTable.workoutEntries,
    'local_date',
    invalid: badDates,
    valid: goodDates,
  ),
  zoneRule(BackupTable.workoutEntries),
  noteRule(BackupTable.workoutEntries),
  boolRule(BackupTable.workoutEntries, 'gamification_eligible'),
  ...auditRules(BackupTable.workoutEntries),
  // --- tasks (index 0 is an open task) -------------------------------------
  idRule(BackupTable.tasks),
  FieldRule(
    BackupTable.tasks,
    'title',
    invalid: ['', 'x' * 121, 5, null],
    valid: ['x', 'x' * 120, '\u{1F600}' * 120],
  ),
  FieldRule(
    BackupTable.tasks,
    'description',
    invalid: ['x' * 1001, 5],
    valid: ['x' * 1000, '', null],
  ),
  FieldRule(
    BackupTable.tasks,
    'priority',
    invalid: ['urgent', 'High', '', 1, null],
    valid: ['low', 'normal', 'high'],
  ),
  FieldRule(
    BackupTable.tasks,
    'due_local_date',
    invalid: ['2026-02-30', '03.10.2026', 20261003],
    valid: ['2024-02-29', '2026-12-31', null],
  ),
  FieldRule(
    BackupTable.tasks,
    'tags_json',
    invalid: [
      ['a', 'b', 'c', 'd', 'e', 'f'],
      [''],
      ['x' * 21],
      [' padded'],
      ['padded '],
      ['Urlaub', 'urlaub'],
      ['ÄPFEL', 'äpfel'],
      'tag',
      [1],
      null,
      ['a\u0000'],
    ],
    valid: [
      <String>[],
      ['a', 'b', 'c', 'd', 'e'],
      ['x' * 20],
      ['\u{1F600}' * 20],
      ['Büro', 'Bürste'],
    ],
  ),
  // Index 1 is a completed task.
  FieldRule(
    BackupTable.tasks,
    'completed_at_utc',
    invalid: badInstants,
    valid: goodInstants,
    index: 1,
  ),
  FieldRule(
    BackupTable.tasks,
    'completed_local_date',
    invalid: ['2026-02-30', '03.10.2026', 20260303],
    valid: ['2024-02-29', '2026-03-03'],
    index: 1,
  ),
  FieldRule(
    BackupTable.tasks,
    'timezone_id',
    invalid: ['Mars/Base', '', 5],
    valid: ['UTC', 'Europe/Berlin', null],
    index: 1,
  ),
  FieldRule(
    BackupTable.tasks,
    'completion_eligibility',
    invalid: [1, 'true', 0],
    valid: [true, false],
    index: 1,
  ),
  ...auditRules(BackupTable.tasks),
  // --- habits (their id is checked in its own test: checks refer to it) ----
  FieldRule(
    BackupTable.habits,
    'title',
    invalid: ['', 'x' * 81, 5, null],
    valid: ['x', 'x' * 80],
  ),
  FieldRule(
    BackupTable.habits,
    'started_local_date',
    invalid: badDates,
    valid: ['2024-02-29', '2026-01-05'],
  ),
  // Index 1 started 2026-02-01 and is archived from 2026-03-05.
  FieldRule(
    BackupTable.habits,
    'archived_from_date',
    invalid: ['2026-02-30', '03.10.2026', 20260305],
    valid: ['2026-02-01', '2026-12-31', null],
    index: 1,
  ),
  FieldRule(
    BackupTable.habits,
    'reminder_local_time',
    invalid: ['24:00', '7:30', '07:60', '0730', '07:30:00', 730, '', ' 07:30'],
    valid: ['00:00', '07:30', '23:59', null],
  ),
  FieldRule(
    BackupTable.habits,
    'icon_key',
    invalid: ['star', 'Book', '', 1, null],
    valid: ['book', 'moon', 'drop', 'check', 'flame', 'heart'],
  ),
  ...auditRules(BackupTable.habits),
  // --- habit_checks --------------------------------------------------------
  idRule(BackupTable.habitChecks),
  FieldRule(
    BackupTable.habitChecks,
    'habit_id',
    invalid: ['x', '', upperUuid, 5, null],
    valid: [Ids.habitMeditation],
    // Index 2 (reading, 2026-03-03) does not collide with the meditation check
    // of 2026-03-02.
    index: 2,
  ),
  FieldRule(
    BackupTable.habitChecks,
    'local_date',
    invalid: badDates,
    valid: ['2024-02-29', '2026-12-31'],
  ),
  FieldRule(
    BackupTable.habitChecks,
    'checked_at_utc',
    invalid: badInstants,
    valid: goodInstants,
  ),
  zoneRule(BackupTable.habitChecks),
  boolRule(BackupTable.habitChecks, 'eligibility'),
  ...auditRules(BackupTable.habitChecks),
  // --- reminder_rules ------------------------------------------------------
  idRule(BackupTable.reminderRules),
  FieldRule(
    BackupTable.reminderRules,
    'module_id',
    invalid: ['sleep', '', 3, null],
    valid: ['nutrition', 'tasks', 'focus', 'body', 'gamification'],
  ),
  FieldRule(
    BackupTable.reminderRules,
    'kind',
    invalid: ['sleep', 'Water', '', 1, null],
    valid: ['water', 'habit', 'focus_end'],
  ),
  FieldRule(
    BackupTable.reminderRules,
    'local_time',
    invalid: ['24:00', '7:30', '10:60', 1000, ''],
    valid: ['00:00', '10:00', '23:59', null],
  ),
  boolRule(BackupTable.reminderRules, 'enabled'),
  FieldRule(
    BackupTable.reminderRules,
    'route',
    invalid: [
      '',
      'water',
      'https://example.org/x',
      '//example.org',
      '/with space',
      '/new\nline',
      '/${'a' * 200}',
      5,
      null,
    ],
    valid: [
      '/',
      '/water',
      '/habits/${uuid(5)}',
      '/focus?x=1&y=2',
      '/${'a' * 199}',
    ],
  ),
];

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late Map<String, Object?> baseJson;
  setUpAll(() async => baseJson = await richBackupJson());

  Map<String, Object?> fresh() =>
      jsonDecode(jsonEncode(baseJson)) as Map<String, Object?>;

  Map<String, Object?> dataOf(Map<String, Object?> root) =>
      root['data']! as Map<String, Object?>;

  Map<String, Object?> record(
    Map<String, Object?> root,
    BackupTable table, [
    int index = 0,
  ]) {
    final section = dataOf(root)[table.key];
    return table.isSingleton
        ? section! as Map<String, Object?>
        : (section! as List<Object?>)[index]! as Map<String, Object?>;
  }

  List<Object?> listOf(Map<String, Object?> root, BackupTable table) =>
      dataOf(root)[table.key]! as List<Object?>;

  BackupValidationResult validate([
    void Function(Map<String, Object?> root)? mutate,
  ]) {
    final root = fresh();
    mutate?.call(root);
    return plainValidator.validateDecoded(root);
  }

  String describe(ImportValidationReport report) =>
      report.problems.map((p) => p.displayText).join(' | ');

  /// The report has exactly one problem, at [location] / [field].
  void expectSingle(
    BackupValidationResult result,
    String location,
    String? field, {
    String? messageContains,
  }) {
    expect(result.isValid, isFalse, reason: 'expected a rejection');
    expect(result.document, isNull);
    expect(
      result.report.problems,
      hasLength(1),
      reason: describe(result.report),
    );
    final problem = result.report.problems.single;
    expect(problem.location, location);
    expect(problem.field, field);
    if (messageContains != null) {
      expect(problem.message, contains(messageContains));
    }
  }

  void expectValid(BackupValidationResult result, {String? reason}) {
    expect(result.report.problems, isEmpty, reason: reason);
    expect(result.isValid, isTrue);
    expect(result.document, isNotNull);
  }

  String locationOf(BackupTable table, int index) =>
      table.isSingleton ? table.key : '${table.key}[$index]';

  test('the rich export is valid and parsed completely', () {
    final result = validate();
    expectValid(result);
    final data = result.document!.data;
    expect(data.profile.displayName, 'Mia Muster');
    expect(data.weightEntries, hasLength(3));
    expect(data.focusSessions, hasLength(3));
    expect(data.habitChecks, hasLength(3));
    expect(data.recordCount, greaterThan(40));
  });

  group('field rules: reject the invalid, accept the boundaries', () {
    for (final rule in fieldRules) {
      final name = '${rule.table.key}.${rule.field}';
      test('$name rejects invalid values', () {
        expect(rule.invalid, isNotEmpty);
        for (final value in rule.invalid) {
          final result = validate((root) {
            final target = record(root, rule.table, rule.index)
              ..addAll(rule.alsoSet);
            target[rule.field] = value;
          });
          expectSingle(result, locationOf(rule.table, rule.index), rule.field);
        }
      });

      test('$name accepts the boundary values', () {
        expect(rule.valid, isNotEmpty);
        for (final value in rule.valid) {
          final result = validate((root) {
            final target = record(root, rule.table, rule.index)
              ..addAll(rule.alsoSet);
            target[rule.field] = value;
          });
          expectValid(result, reason: '$name = ${jsonEncode(value)}');
        }
      });
    }
  });

  group('singletons', () {
    test('profile id and settings id are fixed', () {
      expectSingle(
        validate((r) => record(r, BackupTable.profile)['id'] = 'other'),
        'profile',
        'id',
      );
      expectSingle(
        validate((r) => record(r, BackupTable.appSettings)['id'] = 'local'),
        'app_settings',
        'id',
      );
    });

    test(
      'exactly one profile: an array, two profiles or none are rejected',
      () {
        for (final value in <Object?>[
          <Object?>[],
          [fresh()['data']],
          [record(fresh(), BackupTable.profile)],
          [
            record(fresh(), BackupTable.profile),
            record(fresh(), BackupTable.profile),
          ],
          null,
          'local',
        ]) {
          final result = validate((r) => dataOf(r)['profile'] = value);
          expectSingle(result, 'profile', null);
        }
        final missing = validate((r) => dataOf(r).remove('profile'));
        expectSingle(missing, 'profile', null, messageContains: 'fehlt');
      },
    );

    test('settings must be a single object as well', () {
      expectSingle(
        validate((r) => dataOf(r)['app_settings'] = <Object?>[]),
        'app_settings',
        null,
      );
    });
  });

  group('cross-field rules inside a record', () {
    test('every dashboard card is valid with its own module only', () {
      final cards = SchemaKeys.dashboardCardModule;
      BackupValidationResult withCards(Map<String, String> pairs) => validate(
        (r) => dataOf(r)['dashboard_cards'] = [
          for (final entry in pairs.entries.indexed)
            {
              'card_id': entry.$2.key,
              'module_id': entry.$2.value,
              'visible': true,
              'sort_index': entry.$1,
            },
        ],
      );
      expectValid(withCards(cards));
      for (final card in cards.keys) {
        for (final module in SchemaKeys.modules) {
          if (module == cards[card]) {
            continue;
          }
          final result = withCards({card: module});
          expectSingle(result, 'dashboard_cards[0]', 'module_id');
        }
      }
    });

    test('dashboard card and module must belong together', () {
      // Card 0 in file order is "xp" (sort index 0).
      final root = fresh();
      expect(record(root, BackupTable.dashboardCards)['card_id'], 'xp');
      expectSingle(
        validate(
          (r) => record(r, BackupTable.dashboardCards)['module_id'] = 'body',
        ),
        'dashboard_cards[0]',
        'module_id',
      );
      expectValid(
        validate(
          (r) => record(r, BackupTable.dashboardCards)['module_id'] =
              'gamification',
        ),
      );
    });

    test('step day: reached eligibility and threshold belong together', () {
      // Index 0 is 2026-03-02 with both set.
      for (final partial in <Map<String, Object?>>[
        {'reached_goal_eligible': null},
        {'xp_goal_target_steps': null},
      ]) {
        final result = validate(
          (r) => record(r, BackupTable.stepDays).addAll(partial),
        );
        expectSingle(result, 'step_days[0]', 'xp_goal_target_steps');
      }
      expectValid(
        validate(
          (r) => record(r, BackupTable.stepDays).addAll({
            'reached_goal_eligible': null,
            'xp_goal_target_steps': null,
          }),
        ),
      );
      expectValid(
        validate(
          (r) => record(
            r,
            BackupTable.stepDays,
          ).addAll({'reached_goal_eligible': false, 'xp_goal_target_steps': 1}),
        ),
      );
      expectSingle(
        validate(
          (r) => record(r, BackupTable.stepDays)['xp_goal_target_steps'] = 0,
        ),
        'step_days[0]',
        'xp_goal_target_steps',
      );
    });

    group('task completion triple', () {
      const triple = [
        'completed_at_utc',
        'completed_local_date',
        'completion_eligibility',
      ];
      const values = <String, Object?>{
        'completed_at_utc': '2026-03-03T17:45:10.500Z',
        'completed_local_date': '2026-03-03',
        'completion_eligibility': true,
      };

      test('all three set or all three null is valid', () {
        expectValid(
          validate((r) => record(r, BackupTable.tasks).addAll(values)),
        );
        expectValid(
          validate(
            (r) => record(
              r,
              BackupTable.tasks,
            ).addAll({for (final key in triple) key: null}),
          ),
        );
      });

      for (final only in triple) {
        test('only $only set is rejected', () {
          final result = validate(
            (r) => record(r, BackupTable.tasks).addAll({
              for (final key in triple) key: key == only ? values[key] : null,
            }),
          );
          expectSingle(result, 'tasks[0]', 'completed_at_utc');
        });
      }

      for (final missing in triple) {
        test('only $missing missing is rejected', () {
          final result = validate(
            (r) => record(r, BackupTable.tasks).addAll({
              for (final key in triple)
                key: key == missing ? null : values[key],
            }),
          );
          expectSingle(result, 'tasks[0]', 'completed_at_utc');
        });
      }
    });

    group('focus session', () {
      // Index 0 completed, 1 discarded, 2 paused (the only open one).
      test('the fixture has the expected sessions', () {
        final root = fresh();
        expect(
          [
            for (var i = 0; i < 3; i++)
              record(root, BackupTable.focusSessions, i)['status'],
          ],
          ['completed', 'discarded', 'paused'],
        );
      });

      test('a running session cannot be imported', () {
        final result = validate((r) {
          record(r, BackupTable.focusSessions, 2)
            ..['status'] = 'running'
            ..['segment_started_at_utc'] = '2026-03-04T14:10:00.000Z';
        });
        expectSingle(
          result,
          'focus_sessions[2]',
          'status',
          messageContains: 'laufende Sitzung',
        );
        // Without a segment it is wrong in the same way.
        expectSingle(
          validate(
            (r) =>
                record(r, BackupTable.focusSessions, 2)['status'] = 'running',
          ),
          'focus_sessions[2]',
          'status',
        );
      });

      test('a paused session must not have a running segment', () {
        expectSingle(
          validate(
            (r) => record(
              r,
              BackupTable.focusSessions,
              2,
            )['segment_started_at_utc'] = '2026-03-04T14:10:00.000Z',
          ),
          'focus_sessions[2]',
          'segment_started_at_utc',
        );
      });

      test('completed needs a completion date, others must not have one', () {
        expectSingle(
          validate(
            (r) => record(
              r,
              BackupTable.focusSessions,
              0,
            )['completed_local_date'] = null,
          ),
          'focus_sessions[0]',
          'completed_local_date',
        );
        for (final index in [1, 2]) {
          expectSingle(
            validate(
              (r) => record(
                r,
                BackupTable.focusSessions,
                index,
              )['completed_local_date'] = '2026-03-04',
            ),
            'focus_sessions[$index]',
            'completed_local_date',
          );
        }
      });

      test('a completion date does not make a discarded session completed', () {
        // status completed with a date is the valid combination.
        expectValid(
          validate((r) {
            record(r, BackupTable.focusSessions, 1)
              ..['status'] = 'completed'
              ..['completed_local_date'] = '2026-03-03';
          }),
        );
      });

      test('ended before started is rejected, equal or later is valid', () {
        // Session 1 started 2026-03-03T09:00:00.000Z.
        for (final ended in [
          '2026-03-03T08:59:59.999Z',
          '2026-03-02T09:00:00.000Z',
        ]) {
          expectSingle(
            validate(
              (r) => record(r, BackupTable.focusSessions, 1)['ended_at_utc'] =
                  ended,
            ),
            'focus_sessions[1]',
            'ended_at_utc',
          );
        }
        for (final ended in [
          '2026-03-03T09:00:00.000Z',
          '2026-03-03T09:00:00.001Z',
          null,
        ]) {
          expectValid(
            validate(
              (r) => record(r, BackupTable.focusSessions, 1)['ended_at_utc'] =
                  ended,
            ),
          );
        }
      });

      test('accumulated time above the plan is rejected, equal is valid', () {
        expectSingle(
          validate((r) {
            record(r, BackupTable.focusSessions, 2)
              ..['planned_seconds'] = 600
              ..['accumulated_seconds'] = 601;
          }),
          'focus_sessions[2]',
          'accumulated_seconds',
        );
        expectValid(
          validate((r) {
            record(r, BackupTable.focusSessions, 2)
              ..['planned_seconds'] = 600
              ..['accumulated_seconds'] = 600;
          }),
        );
      });

      test(
        'at most one open session: two are rejected, one or none is valid',
        () {
          // Make the discarded session open as well (paused, not ended).
          expectSingle(
            validate((r) {
              record(r, BackupTable.focusSessions, 1)
                ..['status'] = 'awaiting_confirmation'
                ..['ended_at_utc'] = null;
            }),
            'focus_sessions[2]',
            'status',
            messageContains: 'höchstens eine offene Sitzung',
          );
          // No open session at all.
          expectValid(
            validate(
              (r) => record(r, BackupTable.focusSessions, 2)['status'] =
                  'discarded',
            ),
          );
          // Exactly one open session in any of the open states.
          for (final status in ['paused', 'awaiting_confirmation']) {
            expectValid(
              validate(
                (r) =>
                    record(r, BackupTable.focusSessions, 2)['status'] = status,
              ),
            );
          }
        },
      );
    });

    group('habit', () {
      test(
        'archiving before the start is rejected, same day and later valid',
        () {
          // Habit 1 started 2026-02-01 and is archived from 2026-03-05.
          expectSingle(
            validate(
              (r) => record(r, BackupTable.habits, 1)['archived_from_date'] =
                  '2026-01-31',
            ),
            'habits[1]',
            'archived_from_date',
          );
          for (final date in ['2026-02-01', '2026-02-02', null]) {
            expectValid(
              validate(
                (r) => record(r, BackupTable.habits, 1)['archived_from_date'] =
                    date,
              ),
            );
          }
        },
      );
    });
  });

  group('relations between records', () {
    test('every id must be unique per table', () {
      const tables = [
        BackupTable.moduleStatusHistory,
        BackupTable.goalVersions,
        BackupTable.dailyGoalSnapshots,
        BackupTable.weightEntries,
        BackupTable.stepDays,
        BackupTable.waterEntries,
        BackupTable.mealEntries,
        BackupTable.focusSessions,
        BackupTable.workoutEntries,
        BackupTable.tasks,
        BackupTable.habits,
        BackupTable.habitChecks,
        BackupTable.reminderRules,
      ];
      for (final table in tables) {
        final result = validate((r) {
          record(r, table, 1)['id'] = record(r, table)['id'];
        });
        expect(
          result.report.problems.any(
            (p) =>
                p.location == '${table.key}[1]' &&
                p.field == 'id' &&
                p.message.contains('mehrfach'),
          ),
          isTrue,
          reason: '${table.key}: ${describe(result.report)}',
        );
        expect(result.isValid, isFalse);
      }
    });

    test('duplicate ids across different tables are fine', () {
      expectValid(
        validate((r) {
          record(r, BackupTable.waterEntries)['id'] = record(
            r,
            BackupTable.weightEntries,
          )['id'];
        }),
      );
    });

    test('dashboard card ids are unique', () {
      expectSingle(
        validate((r) {
          record(r, BackupTable.dashboardCards, 1)
            ..['card_id'] = record(r, BackupTable.dashboardCards)['card_id']
            ..['module_id'] = 'gamification';
        }),
        'dashboard_cards[1]',
        'card_id',
      );
    });

    test('goal versions are unique per type and date', () {
      // [2] and [4] are both water; [4] is the later version (2026-06-01).
      final root = fresh();
      expect(record(root, BackupTable.goalVersions, 2)['goal_type'], 'water');
      expect(record(root, BackupTable.goalVersions, 4)['goal_type'], 'water');
      expectSingle(
        validate((r) {
          record(r, BackupTable.goalVersions, 4)['effective_from_date'] =
              record(r, BackupTable.goalVersions, 2)['effective_from_date'];
        }),
        'goal_versions[4]',
        'effective_from_date',
      );
      // Same date, other type: fine.
      expectValid(
        validate((r) {
          record(r, BackupTable.goalVersions, 4)
            ..['goal_type'] = 'workout_weekly'
            ..['effective_from_date'] = record(
              r,
              BackupTable.goalVersions,
              2,
            )['effective_from_date'];
        }),
      );
    });

    test('snapshots are unique per date and goal key', () {
      final first = record(fresh(), BackupTable.dailyGoalSnapshots);
      expectSingle(
        validate((r) {
          record(r, BackupTable.dailyGoalSnapshots, 1)
            ..['local_date'] = first['local_date']
            ..['goal_key'] = first['goal_key'];
        }),
        'daily_goal_snapshots[1]',
        'goal_key',
      );
      // Same key on another day is fine.
      expectValid(
        validate((r) {
          record(r, BackupTable.dailyGoalSnapshots, 1)
            ..['local_date'] = '2026-03-09'
            ..['goal_key'] = first['goal_key'];
        }),
      );
    });

    test('a weight measurement time exists only once', () {
      final time = record(
        fresh(),
        BackupTable.weightEntries,
      )['occurred_at_utc'];
      expectSingle(
        validate(
          (r) =>
              record(r, BackupTable.weightEntries, 1)['occurred_at_utc'] = time,
        ),
        'weight_entries[1]',
        'occurred_at_utc',
      );
      // One millisecond later is a different measurement.
      expectValid(
        validate(
          (r) => record(r, BackupTable.weightEntries, 1)['occurred_at_utc'] =
              '2026-03-02T06:30:15.251Z',
        ),
      );
    });

    test('there is one step total per date', () {
      final date = record(fresh(), BackupTable.stepDays)['local_date'];
      expectSingle(
        validate(
          (r) => record(r, BackupTable.stepDays, 1)['local_date'] = date,
        ),
        'step_days[1]',
        'local_date',
      );
    });

    test('a habit has one check per day', () {
      final first = record(fresh(), BackupTable.habitChecks);
      expectSingle(
        validate((r) {
          record(r, BackupTable.habitChecks, 2)
            ..['habit_id'] = first['habit_id']
            ..['local_date'] = first['local_date'];
        }),
        'habit_checks[2]',
        'local_date',
      );
      // Another habit on the same day is fine (index 1 is the meditation
      // check, index 2 the reading check of 2026-03-03).
      expectValid(
        validate(
          (r) => record(r, BackupTable.habitChecks, 1)['local_date'] =
              '2026-03-03',
        ),
      );
    });

    test('a habit check must point at an existing habit (foreign key)', () {
      expectSingle(
        validate(
          (r) => record(r, BackupTable.habitChecks)['habit_id'] = uuid(0xFFFF),
        ),
        'habit_checks[0]',
        'habit_id',
        messageContains: 'nicht vorhandene Gewohnheit',
      );
      // The referenced habit is part of the file.
      expectValid(validate());
    });

    test('a habit id must be a UUID and the checks must still find it', () {
      final habitId = record(fresh(), BackupTable.habits)['id'];
      // Renaming the habit alone breaks the references of its checks.
      final renamed = validate(
        (r) => record(r, BackupTable.habits)['id'] = uuid(0xABC),
      );
      expect(renamed.report.problems.map((p) => p.location), [
        'habit_checks[0]',
        'habit_checks[2]',
      ]);
      // Renaming the habit together with its checks is a valid file.
      expectValid(
        validate((r) {
          record(r, BackupTable.habits)['id'] = uuid(0xABC);
          for (final index in [0, 2]) {
            record(r, BackupTable.habitChecks, index)['habit_id'] = uuid(0xABC);
          }
        }),
      );
      // A malformed id is reported at the habit.
      final broken = validate((r) => record(r, BackupTable.habits)['id'] = 'x');
      expect(
        broken.report.problems.first.displayText,
        startsWith('habits[0]: ID ist keine gültige UUID'),
      );
      expect(habitId, Ids.habitReading);
    });

    test('a broken habit record does not cause bogus foreign key errors', () {
      final result = validate(
        (r) => record(r, BackupTable.habits, 0)['title'] = '',
      );
      expectSingle(result, 'habits[0]', 'title');
    });

    test('snapshots may refer to a habit that is not in the file', () {
      // The fixture's snapshot of a deleted habit stays valid history.
      final root = fresh();
      final keys = [
        for (final s in listOf(root, BackupTable.dailyGoalSnapshots))
          (s! as Map<String, Object?>)['goal_key'],
      ];
      expect(keys, contains('habit:${Ids.habitDeleted}'));
      expectValid(validate());
    });

    test('problems of different stages are reported together', () {
      final result = validate((r) {
        record(r, BackupTable.weightEntries, 0)['weight_grams'] = 19900;
        record(r, BackupTable.habitChecks)['habit_id'] = uuid(0xFFFF);
        record(r, BackupTable.stepDays, 1)['local_date'] = record(
          r,
          BackupTable.stepDays,
        )['local_date'];
        record(r, BackupTable.focusSessions, 1)
          ..['status'] = 'awaiting_confirmation'
          ..['ended_at_utc'] = null;
      });
      // Record problems first, then the relations in a fixed order.
      expect(result.report.problems.map((p) => p.displayText), [
        startsWith('weight_entries[0]: Gewicht'),
        startsWith('step_days[1]: Für dieses Datum'),
        startsWith('habit_checks[0]: Verweis'),
        startsWith('focus_sessions[2]: Es darf höchstens eine offene'),
      ]);
    });
  });

  group('root and data sections', () {
    test('the format marker must match exactly and nothing else is read', () {
      for (final marker in <Object?>[
        'levelup_life_backup ',
        'Levelup_Life_Backup',
        'other_app_backup',
        '',
        1,
        null,
      ]) {
        final result = validate((r) {
          r['format'] = marker;
          // Further garbage must not be reported: the file is not ours.
          dataOf(r).remove('profile');
        });
        expectSingle(result, 'root', 'format');
      }
      expectSingle(validate((r) => r.remove('format')), 'root', 'format');
    });

    test('only schema version 1 is accepted', () {
      for (final version in <Object?>[
        0,
        2,
        -1,
        100,
        '1',
        1.0,
        1.5,
        null,
        true,
      ]) {
        expectSingle(
          validate((r) => r['schemaVersion'] = version),
          'root',
          'schemaVersion',
          messageContains: 'nicht unterstützt',
        );
      }
      expectSingle(
        validate((r) => r.remove('schemaVersion')),
        'root',
        'schemaVersion',
      );
      expectValid(validate((r) => r['schemaVersion'] = 1));
    });

    test('exportedAtUtc must be a valid instant', () {
      for (final bad in badInstants) {
        expectSingle(
          validate((r) => r['exportedAtUtc'] = bad),
          'root',
          'exportedAtUtc',
        );
      }
      expectValid(
        validate((r) => r['exportedAtUtc'] = '2026-10-03T08:00:00.000Z'),
      );
    });

    test('appVersion: 1-32 characters of a version', () {
      for (final bad in <Object?>[
        '',
        ' 1.0.0',
        '1.0.0 ',
        '1.0.0!',
        'a' * 33,
        1,
        null,
        '-1',
        '1/0',
      ]) {
        expectSingle(
          validate((r) => r['appVersion'] = bad),
          'root',
          'appVersion',
        );
      }
      for (final good in ['1.0.0', '2.10.3+4', '1.0.0-beta.1', 'x' * 32, '9']) {
        expectValid(validate((r) => r['appVersion'] = good));
      }
    });

    test('unknown root fields are rejected without echo', () {
      final result = validate((r) => r['secretNote'] = 'Mia');
      expectSingle(result, 'root', null, messageContains: 'Zusatzfeld');
      expect(result.report.summary, isNot(contains('secretNote')));
    });

    test('data must be an object and must exist', () {
      for (final bad in <Object?>[<Object?>[], 'x', 1, null]) {
        expectSingle(validate((r) => r['data'] = bad), 'root', 'data');
      }
      expectSingle(validate((r) => r.remove('data')), 'root', 'data');
    });

    test('technical tables are not part of a backup', () {
      for (final table in BackupFormat.technicalTables) {
        final result = validate((r) => dataOf(r)[table] = <Object?>[]);
        expectSingle(
          result,
          'data',
          null,
          messageContains: 'Technische Tabelle',
        );
        expect(describe(result.report), isNot(contains(table)));
      }
    });

    test('unknown sections are rejected without echo', () {
      final result = validate((r) => dataOf(r)['sleep_entries'] = <Object?>[]);
      expectSingle(
        result,
        'data',
        null,
        messageContains: 'Unbekannter Abschnitt',
      );
      expect(describe(result.report), isNot(contains('sleep')));
    });

    test('every section is required', () {
      for (final table in BackupTable.values) {
        final result = validate((r) => dataOf(r).remove(table.key));
        // A missing habits section is reported once, not once per check.
        expectSingle(
          result,
          table.key,
          null,
          messageContains: 'Pflichtabschnitt fehlt',
        );
      }
    });

    test('an empty list is fine for every list section', () {
      for (final table in BackupTable.values.where((t) => !t.isSingleton)) {
        final result = validate((r) => dataOf(r)[table.key] = <Object?>[]);
        // Removing habits leaves checks without habits: skip that relation.
        if (table == BackupTable.habits) {
          expect(
            result.report.problems.every(
              (p) => p.location.startsWith('habit_checks'),
            ),
            isTrue,
          );
        } else {
          expectValid(result, reason: table.key);
        }
      }
    });

    test('a list section must be a list and hold objects', () {
      for (final bad in <Object?>[<String, Object?>{}, 'x', 1, null]) {
        expectSingle(
          validate((r) => dataOf(r)['weight_entries'] = bad),
          'weight_entries',
          null,
        );
      }
      for (final bad in <Object?>[1, 'x', null, <Object?>[]]) {
        final result = validate(
          (r) => listOf(r, BackupTable.weightEntries)[1] = bad,
        );
        expectSingle(result, 'weight_entries[1]', null);
      }
    });
  });

  group('file level', () {
    List<int> validBytes() => bytesOf(baseJson);

    BackupValidationResult validateBytes(List<int> bytes) =>
        plainValidator.validateBytes(Uint8List.fromList(bytes));

    test('a valid file is accepted as bytes', () {
      final result = validateBytes(validBytes());
      expectValid(result);
    });

    test('an empty file is rejected', () {
      expectSingle(
        validateBytes(const []),
        'file',
        null,
        messageContains: 'leer',
      );
    });

    test('invalid UTF-8 is rejected', () {
      expectSingle(
        validateBytes([0x7B, 0xFF, 0xFE, 0x7D]),
        'file',
        null,
        messageContains: 'UTF-8',
      );
    });

    test('malformed JSON is rejected', () {
      for (final text in [
        '{',
        '{"format":',
        '   ',
        '{"a":1} trailing',
        'NaN',
        '{"a":1,}',
        "{'a':1}",
        'null null',
      ]) {
        expectSingle(
          validateBytes(utf8.encode(text)),
          'file',
          null,
          messageContains: 'kein gültiges JSON',
        );
      }
    });

    test('a truncated export is rejected', () {
      final bytes = validBytes();
      expectSingle(
        validateBytes(bytes.sublist(0, bytes.length ~/ 2)),
        'file',
        null,
        messageContains: 'JSON',
      );
    });

    test('the JSON root must be an object', () {
      for (final text in ['[]', '"x"', '12', 'null', 'true', '[{}]']) {
        expectSingle(
          validateBytes(utf8.encode(text)),
          'file',
          null,
          messageContains: 'JSON-Objekt erwartet',
        );
      }
    });

    test('a byte order mark and trailing whitespace are tolerated', () {
      expectValid(validateBytes([0xEF, 0xBB, 0xBF, ...validBytes()]));
      expectValid(validateBytes([...validBytes(), 0x0A, 0x20, 0x0D, 0x09]));
    });

    test('an object that is not a backup is rejected on the format marker', () {
      expectSingle(
        validateBytes(utf8.encode('{"name":"x","items":[1,2,3]}')),
        'root',
        'format',
      );
    });

    group('size limit (10 MiB)', () {
      Uint8List padded(int length) {
        final json = validBytes();
        final bytes = Uint8List(length)..fillRange(0, length, 0x20);
        bytes.setRange(0, json.length, json);
        return bytes;
      }

      test('exactly 10 MiB is accepted', () {
        const limit = 10 * 1024 * 1024;
        expect(limit, BackupFormat.maxFileBytes);
        expectValid(plainValidator.validateBytes(padded(limit)));
      });

      test('one byte more is rejected before anything is parsed', () {
        final result = plainValidator.validateBytes(
          padded(BackupFormat.maxFileBytes + 1),
        );
        expectSingle(result, 'file', null, messageContains: '10 MiB');
      });

      test('a huge file is rejected even if it is not even text', () {
        final result = plainValidator.validateBytes(
          Uint8List(BackupFormat.maxFileBytes + 1),
        );
        expectSingle(result, 'file', null, messageContains: '10 MiB');
      });
    });

    group('record limit (50,000)', () {
      /// A backup with exactly [total] records, the surplus being water
      /// entries with unique ids.
      Map<String, Object?> withRecords(int total) {
        final root = fresh();
        final base = plainValidator
            .validateDecoded(root)
            .document!
            .data
            .recordCount;
        final water = listOf(root, BackupTable.waterEntries);
        final template = Map<String, Object?>.of(
          water.first! as Map<String, Object?>,
        );
        final extra = total - base;
        expect(extra, greaterThan(0));
        for (var i = 0; i < extra; i++) {
          water.add(
            Map<String, Object?>.of(template)..['id'] = uuid(0x100000 + i),
          );
        }
        return root;
      }

      test('exactly 50,000 records are accepted', () {
        expect(BackupFormat.maxRecords, 50000);
        final result = plainValidator.validateDecoded(withRecords(50000));
        expectValid(result);
        expect(result.document!.data.recordCount, 50000);
      });

      test('50,001 records are rejected without parsing records', () {
        final root = withRecords(50001);
        // Make every record invalid: none of that may be reported.
        for (final entry in listOf(root, BackupTable.waterEntries)) {
          (entry! as Map<String, Object?>)['amount_ml'] = 1;
        }
        final result = plainValidator.validateDecoded(root);
        expectSingle(
          result,
          'data',
          null,
          messageContains: '50.000 Datensätze',
        );
      });
    });
  });

  group('reporting', () {
    /// Appends [count] water entries with an invalid amount; returns the
    /// index of the first one.
    int addBrokenWaterEntries(Map<String, Object?> root, int count) {
      final water = listOf(root, BackupTable.waterEntries);
      final first = water.length;
      final template = Map<String, Object?>.of(
        water.first! as Map<String, Object?>,
      );
      for (var i = 0; i < count; i++) {
        water.add(
          Map<String, Object?>.of(template)
            ..['id'] = uuid(0x300000 + i)
            ..['amount_ml'] = 1,
        );
      }
      return first;
    }

    test('at most 20 problems are listed and the rest is flagged', () {
      late int first;
      final result = validate((r) => first = addBrokenWaterEntries(r, 40));
      expect(result.isValid, isFalse);
      expect(result.report.problems, hasLength(20));
      expect(result.report.truncated, isTrue);
      expect(result.report.problems.first.location, 'water_entries[$first]');
      expect(
        result.report.problems.last.location,
        'water_entries[${first + 19}]',
      );
      expect(result.report.summary, contains('mehr als 20 Probleme'));
    });

    test('exactly 20 problems are listed without the truncation flag', () {
      final result = validate((r) => addBrokenWaterEntries(r, 20));
      expect(result.report.problems, hasLength(20));
      expect(result.report.truncated, isFalse);
      expect(result.report.summary, contains('20 Probleme'));
      expect(result.report.summary, isNot(contains('mehr als')));
    });

    test('21 problems are 20 listed plus the flag', () {
      final result = validate((r) => addBrokenWaterEntries(r, 21));
      expect(result.report.problems, hasLength(20));
      expect(result.report.truncated, isTrue);
    });

    test(
      'the summary names the first problem and says nothing was changed',
      () {
        final result = validate(
          (r) => record(r, BackupTable.weightEntries)['weight_grams'] = 19900,
        );
        expect(
          result.report.summary,
          'Die Sicherung wurde abgelehnt (ein Problem, zuerst: '
          'weight_entries[0]: Gewicht außerhalb des erlaubten Bereichs). '
          'Deine vorhandenen Daten wurden nicht verändert.',
        );
      },
    );

    test('a valid report has no problems', () {
      expect(ImportValidationReport.valid.isValid, isTrue);
      expect(ImportValidationReport.valid.summary, 'Die Sicherung ist gültig.');
    });

    test('messages never contain values from the file', () {
      final result = validate((r) {
        record(r, BackupTable.profile)['display_name'] = 'Mia ${'Muster' * 20}';
        record(r, BackupTable.mealEntries)['name'] =
            'Geheimes Gericht ${'x' * 100}';
        record(r, BackupTable.tasks)['title'] =
            'Streng vertraulich ${'y' * 200}';
      });
      expect(result.report.problems, hasLength(3));
      final text = describe(result.report);
      expect(text, isNot(contains('Muster')));
      expect(text, isNot(contains('Geheim')));
      expect(text, isNot(contains('vertraulich')));
    });
  });

  group('AT31: files that must be rejected without touching data', () {
    test('wrong schema version', () {
      expectSingle(
        validate((r) => r['schemaVersion'] = 2),
        'root',
        'schemaVersion',
      );
    });

    test('wrong format marker', () {
      expectSingle(
        validate((r) => r['format'] = 'something_else'),
        'root',
        'format',
      );
    });

    test('duplicate ids', () {
      final result = validate(
        (r) => record(r, BackupTable.weightEntries, 1)['id'] = record(
          r,
          BackupTable.weightEntries,
        )['id'],
      );
      expectSingle(result, 'weight_entries[1]', 'id');
    });

    test('missing foreign key target', () {
      final result = validate((r) => listOf(r, BackupTable.habits).clear());
      expect(result.report.problems.map((p) => p.location).toSet(), {
        'habit_checks[0]',
        'habit_checks[1]',
        'habit_checks[2]',
      });
      expect(result.isValid, isFalse);
    });

    test('extra fields', () {
      expectSingle(
        validate((r) => record(r, BackupTable.habits)['colour'] = 'red'),
        'habits[0]',
        null,
      );
    });

    test('wrong types', () {
      expectSingle(
        validate(
          (r) => record(r, BackupTable.waterEntries)['amount_ml'] = '250',
        ),
        'water_entries[0]',
        'amount_ml',
      );
    });

    test('bad dates', () {
      expectSingle(
        validate(
          (r) => record(r, BackupTable.stepDays)['local_date'] = '2026-02-30',
        ),
        'step_days[0]',
        'local_date',
      );
    });
  });

  group('SnapshotConsistencyChecker extension point', () {
    test('is not consulted for a file that is already invalid', () {
      var calls = 0;
      final validator = BackupValidator(
        snapshotChecker: _Checker((data) {
          calls++;
          return const [];
        }),
      );
      final root = fresh();
      record(root, BackupTable.weightEntries)['weight_grams'] = 19900;
      expect(validator.validateDecoded(root).isValid, isFalse);
      expect(calls, 0);
    });

    test('receives the typed data of a valid file', () {
      BackupData? received;
      final validator = BackupValidator(
        snapshotChecker: _Checker((data) {
          received = data;
          return const [];
        }),
      );
      final result = validator.validateDecoded(fresh());
      expectValid(result);
      expect(received, isNotNull);
      expect(identical(received, result.document!.data), isTrue);
      expect(received!.dailyGoalSnapshots, hasLength(5));
    });

    test('its problems reject the file and keep their locations', () {
      final validator = BackupValidator(
        snapshotChecker: _Checker(
          (data) => [
            ImportProblem.record(
              BackupTable.dailyGoalSnapshots,
              1,
              'Snapshot widerspricht der Modulhistorie',
              field: 'applicable',
            ),
          ],
        ),
      );
      final result = validator.validateDecoded(fresh());
      expect(result.isValid, isFalse);
      expect(result.document, isNull);
      expect(
        result.report.problems.single.displayText,
        'daily_goal_snapshots[1]: Snapshot widerspricht der Modulhistorie',
      );
    });

    test('list positions equal the positions in the file', () {
      final root = fresh();
      final ids = [
        for (final s in listOf(root, BackupTable.dailyGoalSnapshots))
          (s! as Map<String, Object?>)['id'],
      ];
      late List<String> seen;
      final validator = BackupValidator(
        snapshotChecker: _Checker((data) {
          seen = [for (final s in data.dailyGoalSnapshots) s.id];
          return const [];
        }),
      );
      expectValid(validator.validateDecoded(root));
      expect(seen, ids);
    });

    test('an empty answer leaves the file valid', () {
      final validator = BackupValidator(
        snapshotChecker: _Checker((data) => const []),
      );
      expectValid(validator.validateDecoded(fresh()));
    });
  });
}

/// A [SnapshotConsistencyChecker] backed by a closure.
final class _Checker implements SnapshotConsistencyChecker {
  _Checker(this._check);

  final List<ImportProblem> Function(BackupData data) _check;

  @override
  List<ImportProblem> check(BackupData data) => _check(data);
}
