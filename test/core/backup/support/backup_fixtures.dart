import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Synthetic data only: "Mia Muster" does not exist.

/// A valid UUID v4 shaped id, `00000000-0000-4000-8000-<n as 12 hex digits>`.
String uuid(int n) =>
    '00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';

/// An instant in March 2026 (UTC), with optional milliseconds.
DateTime at(int day, int hour, [int minute = 0, int second = 0, int ms = 0]) =>
    DateTime.utc(2026, 3, day, hour, minute, second, ms);

/// Local date in March 2026.
LocalDate march(int day) => LocalDate(2026, 3, day);

const String berlin = 'Europe/Berlin';

/// Ids of the rich database, by role.
abstract final class Ids {
  static final String habitReading = uuid(0x401);
  static final String habitMeditation = uuid(0x402);
  static final String habitDeleted = uuid(0x403);
  static final String openSession = uuid(0x303);
  static final String ruleWater = uuid(0x701);
  static final String weightFirst = uuid(0x101);
}

/// Fills the (bootstrapped) database of [db] with one or more rows in EVERY
/// table, using a distinct non-default value for every column, plus rows that
/// must NOT be exported: soft-deleted rows, an active check of a deleted
/// habit, and technical rows (XP awards, receipts, scheduled notifications).
///
/// The active rows form a valid backup: one open focus session (paused),
/// unique weight times, one step total per date, and so on.
Future<void> populateRichDatabase(AppDatabase db) async {
  final created = at(1, 7, 15, 30, 123);
  final updated = at(2, 18, 0, 0, 7);
  final deleted = at(9, 12);

  await db
      .into(db.profile)
      .insert(
        ProfileCompanion.insert(
          id: const Value('local'),
          displayName: const Value('Mia Muster'),
          startedLocalDate: LocalDate(2026, 1, 5),
          heightCm: const Value(168),
          ageYears: const Value(34),
          startWeightGrams: const Value(78000),
          targetWeightGrams: const Value(70000),
          motivationGoals: const Value(['move_more', 'build_habits']),
          onboardingCompleted: const Value(true),
          createdAtUtc: created,
          updatedAtUtc: updated,
          rowVersion: const Value(7),
        ),
        mode: InsertMode.insertOrReplace,
      );
  await db
      .into(db.appSettings)
      .insert(
        AppSettingsCompanion.insert(
          id: const Value('app'),
          themeMode: const Value('oled'),
          reduceMotion: const Value(true),
          haptics: const Value(false),
          notificationsEnabled: const Value(true),
          lastKnownTimezone: const Value('Europe/Berlin'),
          createdAtUtc: created,
          updatedAtUtc: updated,
          rowVersion: const Value(3),
        ),
        mode: InsertMode.insertOrReplace,
      );

  await db.batch((b) {
    b.insertAll(db.moduleStatusHistory, [
      for (var i = 0; i < 5; i++)
        ModuleStatusHistoryCompanion.insert(
          id: uuid(0x10 + i),
          moduleId: const [
            'body',
            'nutrition',
            'focus',
            'tasks',
            'gamification',
          ][i],
          effectiveAtUtc: at(1, 7, 15, 30, 123),
          localDate: march(1),
          enabled: true,
        ),
      ModuleStatusHistoryCompanion.insert(
        id: uuid(0x20),
        moduleId: 'body',
        effectiveAtUtc: at(8, 10, 0, 0, 999),
        localDate: march(8),
        enabled: false,
      ),
      ModuleStatusHistoryCompanion.insert(
        id: uuid(0x21),
        moduleId: 'body',
        effectiveAtUtc: at(9, 10),
        localDate: march(9),
        enabled: true,
      ),
    ]);
    // Sort indices deliberately not in card order.
    b.insertAll(db.dashboardCards, [
      DashboardCardsCompanion.insert(
        cardId: 'steps',
        moduleId: 'body',
        sortIndex: 1,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'water',
        moduleId: 'nutrition',
        sortIndex: 2,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'weight',
        moduleId: 'body',
        visible: const Value(false),
        sortIndex: 3,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'workout',
        moduleId: 'focus',
        sortIndex: 4,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'focus',
        moduleId: 'focus',
        sortIndex: 5,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'tasks',
        moduleId: 'tasks',
        sortIndex: 6,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'nutrition',
        moduleId: 'nutrition',
        visible: const Value(false),
        sortIndex: 7,
      ),
      DashboardCardsCompanion.insert(
        cardId: 'xp',
        moduleId: 'gamification',
        sortIndex: 0,
      ),
    ]);
    b.insertAll(db.goalVersions, [
      GoalVersionsCompanion.insert(
        id: uuid(0x31),
        goalType: 'water',
        targetInteger: const Value(2500),
        enabled: true,
        effectiveFromDate: LocalDate(2026, 1, 5),
        createdAtUtc: created,
      ),
      GoalVersionsCompanion.insert(
        id: uuid(0x32),
        goalType: 'water',
        targetInteger: const Value(3000),
        enabled: true,
        effectiveFromDate: LocalDate(2026, 6, 1),
        createdAtUtc: at(20, 9, 1, 2, 3),
      ),
      GoalVersionsCompanion.insert(
        id: uuid(0x33),
        goalType: 'steps',
        targetInteger: const Value(8000),
        enabled: true,
        effectiveFromDate: LocalDate(2026, 1, 5),
        createdAtUtc: created,
      ),
      GoalVersionsCompanion.insert(
        id: uuid(0x34),
        goalType: 'weight_entry',
        enabled: true,
        effectiveFromDate: LocalDate(2026, 1, 5),
        createdAtUtc: created,
      ),
      GoalVersionsCompanion.insert(
        id: uuid(0x35),
        goalType: 'focus_minutes',
        targetInteger: const Value(30),
        enabled: false,
        effectiveFromDate: LocalDate(2026, 1, 5),
        createdAtUtc: created,
      ),
    ]);
    b.insertAll(db.dailyGoalSnapshots, [
      DailyGoalSnapshotsCompanion.insert(
        id: uuid(0x41),
        localDate: march(2),
        goalKey: 'water',
        moduleId: 'nutrition',
        targetInteger: const Value(2500),
        applicable: true,
      ),
      DailyGoalSnapshotsCompanion.insert(
        id: uuid(0x42),
        localDate: march(2),
        goalKey: 'weight_entry',
        moduleId: 'body',
        applicable: true,
      ),
      DailyGoalSnapshotsCompanion.insert(
        id: uuid(0x43),
        localDate: march(2),
        goalKey: 'habit:${Ids.habitReading}',
        moduleId: 'tasks',
        applicable: true,
      ),
      DailyGoalSnapshotsCompanion.insert(
        id: uuid(0x44),
        localDate: march(3),
        goalKey: 'focus_minutes',
        moduleId: 'focus',
        targetInteger: const Value(30),
        applicable: false,
      ),
      // The snapshot of a habit that was deleted later stays as history.
      DailyGoalSnapshotsCompanion.insert(
        id: uuid(0x45),
        localDate: march(2),
        goalKey: 'habit:${Ids.habitDeleted}',
        moduleId: 'tasks',
        applicable: true,
      ),
    ]);
  });

  await db.batch((b) {
    b.insertAll(db.weightEntries, [
      WeightEntriesCompanion.insert(
        id: Ids.weightFirst,
        weightGrams: 71500,
        occurredAtUtc: at(2, 6, 30, 15, 250),
        localDate: march(2),
        timezoneId: berlin,
        beforeToilet: const Value(true),
        afterDrinking: const Value(false),
        afterEating: const Value(true),
        note: const Value('nach dem Aufstehen'),
        gamificationEligible: true,
        createdAtUtc: at(2, 6, 30, 16),
        updatedAtUtc: at(2, 6, 45, 1, 5),
        rowVersion: const Value(2),
      ),
      WeightEntriesCompanion.insert(
        id: uuid(0x102),
        weightGrams: 71200,
        occurredAtUtc: at(3, 6, 31),
        localDate: march(3),
        timezoneId: 'Asia/Tokyo',
        gamificationEligible: false,
        createdAtUtc: at(3, 6, 31),
        updatedAtUtc: at(3, 6, 31),
      ),
      WeightEntriesCompanion.insert(
        id: uuid(0x103),
        weightGrams: 350000,
        occurredAtUtc: at(4, 5),
        localDate: march(4),
        timezoneId: berlin,
        afterDrinking: const Value(true),
        note: const Value(''),
        gamificationEligible: true,
        createdAtUtc: at(4, 5),
        updatedAtUtc: at(4, 5),
      ),
      WeightEntriesCompanion.insert(
        id: uuid(0x104),
        weightGrams: 80000,
        occurredAtUtc: at(5, 5),
        localDate: march(5),
        timezoneId: berlin,
        gamificationEligible: true,
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(5, 5),
        updatedAtUtc: deleted,
        rowVersion: const Value(3),
      ),
    ]);
    b.insertAll(db.stepDays, [
      StepDaysCompanion.insert(
        id: uuid(0x111),
        localDate: march(2),
        steps: 8450,
        timezoneId: berlin,
        reachedGoalEligible: const Value(true),
        xpGoalTargetSteps: const Value(8000),
        createdAtUtc: at(2, 20),
        updatedAtUtc: at(2, 21),
        rowVersion: const Value(4),
      ),
      StepDaysCompanion.insert(
        id: uuid(0x112),
        localDate: march(3),
        steps: 0,
        timezoneId: berlin,
        createdAtUtc: at(3, 20),
        updatedAtUtc: at(3, 20),
      ),
      StepDaysCompanion.insert(
        id: uuid(0x113),
        localDate: march(4),
        steps: 100000,
        timezoneId: berlin,
        reachedGoalEligible: const Value(false),
        xpGoalTargetSteps: const Value(10000),
        createdAtUtc: at(4, 20),
        updatedAtUtc: at(4, 20),
      ),
      StepDaysCompanion.insert(
        id: uuid(0x114),
        localDate: march(5),
        steps: 500,
        timezoneId: berlin,
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(5, 20),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.waterEntries, [
      WaterEntriesCompanion.insert(
        id: uuid(0x121),
        amountMl: 250,
        occurredAtUtc: at(2, 7, 0, 0, 1),
        localDate: march(2),
        timezoneId: berlin,
        note: const Value(
          'Glas Wasser 💧 „kalt“ "x" \\ äöüß\nzweite Zeile\ttab',
        ),
        gamificationEligible: true,
        createdAtUtc: at(2, 7),
        updatedAtUtc: at(2, 7),
        rowVersion: const Value(2),
      ),
      WaterEntriesCompanion.insert(
        id: uuid(0x122),
        amountMl: 2000,
        occurredAtUtc: at(2, 12),
        localDate: march(2),
        timezoneId: berlin,
        gamificationEligible: false,
        createdAtUtc: at(2, 12),
        updatedAtUtc: at(2, 12),
      ),
      WaterEntriesCompanion.insert(
        id: uuid(0x123),
        amountMl: 50,
        occurredAtUtc: at(3, 8),
        localDate: march(3),
        timezoneId: berlin,
        gamificationEligible: true,
        createdAtUtc: at(3, 8),
        updatedAtUtc: at(3, 8),
      ),
      WaterEntriesCompanion.insert(
        id: uuid(0x124),
        amountMl: 100,
        occurredAtUtc: at(3, 9),
        localDate: march(3),
        timezoneId: berlin,
        gamificationEligible: true,
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(3, 9),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.mealEntries, [
      MealEntriesCompanion.insert(
        id: uuid(0x131),
        name: 'Haferbrei mit Beeren',
        kcal: const Value(450),
        occurredAtUtc: at(2, 6, 45),
        localDate: march(2),
        timezoneId: berlin,
        note: const Value('ohne Zucker'),
        createdAtUtc: at(2, 6, 50),
        updatedAtUtc: at(2, 6, 55),
        rowVersion: const Value(2),
      ),
      MealEntriesCompanion.insert(
        id: uuid(0x132),
        name: 'Tee',
        kcal: const Value(0),
        occurredAtUtc: at(2, 15),
        localDate: march(2),
        timezoneId: berlin,
        createdAtUtc: at(2, 15),
        updatedAtUtc: at(2, 15),
      ),
      MealEntriesCompanion.insert(
        id: uuid(0x133),
        name: 'Apfel',
        occurredAtUtc: at(3, 15),
        localDate: march(3),
        timezoneId: berlin,
        createdAtUtc: at(3, 15),
        updatedAtUtc: at(3, 15),
      ),
      MealEntriesCompanion.insert(
        id: uuid(0x134),
        name: 'Gelöschte Mahlzeit',
        kcal: const Value(5000),
        occurredAtUtc: at(3, 16),
        localDate: march(3),
        timezoneId: berlin,
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(3, 16),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.focusSessions, [
      FocusSessionsCompanion.insert(
        id: uuid(0x301),
        category: 'reading',
        plannedSeconds: 1500,
        accumulatedSeconds: const Value(1500),
        startedAtUtc: at(2, 8),
        endedAtUtc: Value(at(2, 8, 26, 3, 400)),
        completedLocalDate: Value(march(2)),
        timezoneId: berlin,
        status: 'completed',
        note: const Value('Kapitel 3'),
        gamificationEligible: const Value(true),
        createdAtUtc: at(2, 8),
        updatedAtUtc: at(2, 8, 26),
        rowVersion: const Value(5),
      ),
      FocusSessionsCompanion.insert(
        id: uuid(0x302),
        category: 'programming',
        plannedSeconds: 600,
        accumulatedSeconds: const Value(120),
        startedAtUtc: at(3, 9),
        endedAtUtc: Value(at(3, 9, 2)),
        timezoneId: berlin,
        status: 'discarded',
        createdAtUtc: at(3, 9),
        updatedAtUtc: at(3, 9, 2),
      ),
      FocusSessionsCompanion.insert(
        id: Ids.openSession,
        category: 'learning',
        plannedSeconds: 3600,
        accumulatedSeconds: const Value(900),
        startedAtUtc: at(4, 14),
        timezoneId: berlin,
        status: 'paused',
        note: const Value('Vokabeln'),
        createdAtUtc: at(4, 14),
        updatedAtUtc: at(4, 14, 15),
        rowVersion: const Value(3),
      ),
      FocusSessionsCompanion.insert(
        id: uuid(0x304),
        category: 'meditation',
        plannedSeconds: 300,
        accumulatedSeconds: const Value(300),
        startedAtUtc: at(5, 7),
        endedAtUtc: Value(at(5, 7, 5)),
        completedLocalDate: Value(march(5)),
        timezoneId: berlin,
        status: 'completed',
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(5, 7),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.workoutEntries, [
      WorkoutEntriesCompanion.insert(
        id: uuid(0x141),
        trainingCategory: 'strength',
        title: const Value('Oberkörper'),
        durationMinutes: 45,
        muscleGroups: const Value(['chest', 'shoulders', 'triceps']),
        intensity: const Value('high'),
        occurredAtUtc: at(2, 17, 30),
        localDate: march(2),
        timezoneId: berlin,
        note: const Value('neuer Rekord'),
        gamificationEligible: true,
        createdAtUtc: at(2, 18),
        updatedAtUtc: at(2, 18, 5),
        rowVersion: const Value(2),
      ),
      WorkoutEntriesCompanion.insert(
        id: uuid(0x142),
        trainingCategory: 'cardio',
        durationMinutes: 600,
        occurredAtUtc: at(3, 17),
        localDate: march(3),
        timezoneId: berlin,
        gamificationEligible: false,
        createdAtUtc: at(3, 17),
        updatedAtUtc: at(3, 17),
      ),
      WorkoutEntriesCompanion.insert(
        id: uuid(0x143),
        trainingCategory: 'sport',
        durationMinutes: 1,
        occurredAtUtc: at(4, 17),
        localDate: march(4),
        timezoneId: berlin,
        deletedAtUtc: Value(deleted),
        gamificationEligible: true,
        createdAtUtc: at(4, 17),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.tasks, [
      TasksCompanion.insert(
        id: uuid(0x151),
        title: 'Steuererklärung vorbereiten',
        description: const Value('Belege sortieren'),
        priority: const Value('high'),
        dueLocalDate: Value(march(10)),
        tagsJson: const Value(['Finanzen', 'Dringend']),
        createdAtUtc: at(1, 9),
        updatedAtUtc: at(1, 10),
        rowVersion: const Value(2),
      ),
      TasksCompanion.insert(
        id: uuid(0x152),
        title: 'Altpapier rausbringen',
        priority: const Value('low'),
        completedAtUtc: Value(at(3, 17, 45, 10, 500)),
        completedLocalDate: Value(march(3)),
        timezoneId: const Value(berlin),
        completionEligibility: const Value(false),
        createdAtUtc: at(2, 9),
        updatedAtUtc: at(3, 17, 45),
        rowVersion: const Value(3),
      ),
      TasksCompanion.insert(
        id: uuid(0x153),
        title: 'Zahnarzttermin buchen',
        completedAtUtc: Value(at(4, 10)),
        completedLocalDate: Value(march(4)),
        timezoneId: const Value('Europe/London'),
        completionEligibility: const Value(true),
        createdAtUtc: at(2, 9, 30),
        updatedAtUtc: at(4, 10),
      ),
      TasksCompanion.insert(
        id: uuid(0x154),
        title: 'Gelöschte Aufgabe',
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(2, 9, 45),
        updatedAtUtc: deleted,
      ),
    ]);
    b.insertAll(db.habits, [
      HabitsCompanion.insert(
        id: Ids.habitReading,
        title: 'Lesen',
        startedLocalDate: LocalDate(2026, 1, 5),
        reminderLocalTime: const Value(LocalTime(7, 30)),
        iconKey: const Value('flame'),
        createdAtUtc: at(1, 6),
        updatedAtUtc: at(1, 6, 5),
        rowVersion: const Value(2),
      ),
      HabitsCompanion.insert(
        id: Ids.habitMeditation,
        title: 'Meditation',
        startedLocalDate: LocalDate(2026, 2, 1),
        archivedFromDate: Value(march(5)),
        createdAtUtc: at(1, 6, 30),
        updatedAtUtc: at(4, 6),
        rowVersion: const Value(3),
      ),
      HabitsCompanion.insert(
        id: Ids.habitDeleted,
        title: 'Gelöschte Gewohnheit',
        startedLocalDate: LocalDate(2026, 2, 1),
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(1, 7),
        updatedAtUtc: deleted,
      ),
    ]);
  });

  await db.batch((b) {
    b.insertAll(db.habitChecks, [
      HabitChecksCompanion.insert(
        id: uuid(0x501),
        habitId: Ids.habitReading,
        localDate: march(2),
        checkedAtUtc: at(2, 19, 0, 0, 321),
        timezoneId: berlin,
        eligibility: true,
        createdAtUtc: at(2, 19),
        updatedAtUtc: at(2, 19, 5),
        rowVersion: const Value(2),
      ),
      HabitChecksCompanion.insert(
        id: uuid(0x502),
        habitId: Ids.habitReading,
        localDate: march(3),
        checkedAtUtc: at(3, 19),
        timezoneId: berlin,
        eligibility: false,
        createdAtUtc: at(3, 19),
        updatedAtUtc: at(3, 19),
      ),
      HabitChecksCompanion.insert(
        id: uuid(0x503),
        habitId: Ids.habitMeditation,
        localDate: march(2),
        checkedAtUtc: at(2, 20),
        timezoneId: berlin,
        eligibility: true,
        createdAtUtc: at(2, 20),
        updatedAtUtc: at(2, 20),
      ),
      HabitChecksCompanion.insert(
        id: uuid(0x504),
        habitId: Ids.habitReading,
        localDate: march(4),
        checkedAtUtc: at(4, 19),
        timezoneId: berlin,
        eligibility: true,
        deletedAtUtc: Value(deleted),
        createdAtUtc: at(4, 19),
        updatedAtUtc: deleted,
      ),
      // An active check whose habit was deleted: not an active business
      // record in effect, never exported.
      HabitChecksCompanion.insert(
        id: uuid(0x505),
        habitId: Ids.habitDeleted,
        localDate: march(2),
        checkedAtUtc: at(2, 21),
        timezoneId: berlin,
        eligibility: true,
        createdAtUtc: at(2, 21),
        updatedAtUtc: at(2, 21),
      ),
    ]);
    b.insertAll(db.reminderRules, [
      ReminderRulesCompanion.insert(
        id: Ids.ruleWater,
        moduleId: 'nutrition',
        kind: 'water',
        localTime: const Value(LocalTime(10, 0)),
        enabled: true,
        route: '/nutrition/water',
      ),
      ReminderRulesCompanion.insert(
        id: uuid(0x702),
        moduleId: 'tasks',
        kind: 'habit',
        localTime: const Value(LocalTime(7, 30)),
        enabled: false,
        route: '/habits',
      ),
      ReminderRulesCompanion.insert(
        id: uuid(0x703),
        moduleId: 'focus',
        kind: 'focus_end',
        enabled: true,
        route: '/focus',
      ),
    ]);
    // Technical tables: never exported, wiped by import and reset.
    b.insertAll(db.xpAwards, [
      XpAwardsCompanion.insert(
        awardKey: 'weight:2026-03-02',
        localDate: march(2),
        sourceKind: 'weight',
        sourceId: Value(Ids.weightFirst),
        points: 10,
        ruleVersion: 1,
      ),
      XpAwardsCompanion.insert(
        awardKey: 'water:${uuid(0x121)}',
        localDate: march(2),
        sourceKind: 'water',
        points: 4,
        ruleVersion: 1,
      ),
    ]);
    b.insertAll(db.commandReceipts, [
      CommandReceiptsCompanion.insert(
        commandId: uuid(0x601),
        commandType: 'weight.create',
        resultEntityId: Value(Ids.weightFirst),
        committedAtUtc: at(2, 6, 30, 16),
      ),
      CommandReceiptsCompanion.insert(
        commandId: uuid(0x602),
        commandType: 'water.create',
        committedAtUtc: at(2, 7),
      ),
    ]);
    b.insertAll(db.scheduledNotifications, [
      ScheduledNotificationsCompanion.insert(
        semanticKey: 'water:2026-03-03:10:00',
        fireAtUtc: at(3, 9),
        route: '/nutrition/water',
        sourceRuleId: Value(Ids.ruleWater),
      ),
    ]);
  });
}

/// All rows of every table of [db], rendered as text (sorted per table), for
/// equality checks. The keys are table names.
Future<Map<String, List<String>>> dumpDatabase(AppDatabase db) async {
  final result = <String, List<String>>{};
  for (final table in db.allTables) {
    final rows = await db.select(table).get();
    result[table.actualTableName] = rows.map((row) => row.toString()).toList()
      ..sort();
  }
  return result;
}

/// The decoded (mutable) JSON of a backup made from the rich database.
Future<Map<String, Object?>> richBackupJson() async {
  final harness = await DataHarness.create();
  try {
    await populateRichDatabase(harness.database);
    final backup = await BackupExporter(
      database: harness.database,
      clock: harness.clock,
    ).export();
    return jsonDecode(utf8.decode(backup.bytes)) as Map<String, Object?>;
  } finally {
    await harness.dispose();
  }
}

/// A deep copy of decoded JSON that tests may mutate freely.
Map<String, Object?> jsonCopy(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// Bytes of [json] as a backup file.
List<int> bytesOf(Object? json) => utf8.encode(jsonEncode(json));

/// The validator without a snapshot checker.
const BackupValidator plainValidator = BackupValidator();

/// The rows of the sixteen backup tables a correct export of [db] contains,
/// rendered as text and sorted: active rows only, and only checks of active
/// habits.
Future<Map<String, List<String>>> expectedExportRows(AppDatabase db) async {
  List<String> text(Iterable<Object> rows) =>
      rows.map((row) => row.toString()).toList()..sort();

  final habits = await (db.select(
    db.habits,
  )..where((t) => t.deletedAtUtc.isNull())).get();
  final habitIds = {for (final habit in habits) habit.id};
  final checks = await (db.select(
    db.habitChecks,
  )..where((t) => t.deletedAtUtc.isNull())).get();
  return {
    'profile': text(await db.select(db.profile).get()),
    'app_settings': text(await db.select(db.appSettings).get()),
    'module_status_history': text(
      await db.select(db.moduleStatusHistory).get(),
    ),
    'dashboard_cards': text(await db.select(db.dashboardCards).get()),
    'goal_versions': text(await db.select(db.goalVersions).get()),
    'daily_goal_snapshots': text(await db.select(db.dailyGoalSnapshots).get()),
    'weight_entries': text(
      await (db.select(
        db.weightEntries,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'step_days': text(
      await (db.select(
        db.stepDays,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'water_entries': text(
      await (db.select(
        db.waterEntries,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'meal_entries': text(
      await (db.select(
        db.mealEntries,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'focus_sessions': text(
      await (db.select(
        db.focusSessions,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'workout_entries': text(
      await (db.select(
        db.workoutEntries,
      )..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'tasks': text(
      await (db.select(db.tasks)..where((t) => t.deletedAtUtc.isNull())).get(),
    ),
    'habits': text(habits),
    'habit_checks': text(checks.where((c) => habitIds.contains(c.habitId))),
    'reminder_rules': text(await db.select(db.reminderRules).get()),
  };
}

/// ALL rows of the sixteen backup tables of [db] (no filtering).
Future<Map<String, List<String>>> backupTablesDump(AppDatabase db) async {
  final dump = await dumpDatabase(db);
  return {
    for (final entry in dump.entries)
      ...(_isBackupTable(entry.key) ? {entry.key: entry.value} : {}),
  };
}

bool _isBackupTable(String name) => const {
  'profile',
  'app_settings',
  'module_status_history',
  'dashboard_cards',
  'goal_versions',
  'daily_goal_snapshots',
  'weight_entries',
  'step_days',
  'water_entries',
  'meal_entries',
  'focus_sessions',
  'workout_entries',
  'tasks',
  'habits',
  'habit_checks',
  'reminder_rules',
}.contains(name);

/// Some rows that are unrelated to [populateRichDatabase]: other ids, other
/// values, plus XP awards, a receipt and a scheduled notification. After an
/// import none of them may exist.
Future<void> populateOtherData(AppDatabase db) async {
  await db
      .into(db.profile)
      .insert(
        ProfileCompanion.insert(
          id: const Value('local'),
          displayName: const Value('Anderes Profil'),
          startedLocalDate: LocalDate(2025, 6, 1),
          createdAtUtc: DateTime.utc(2025, 6, 1, 6),
          updatedAtUtc: DateTime.utc(2025, 6, 2, 6),
          rowVersion: const Value(11),
        ),
        mode: InsertMode.insertOrReplace,
      );
  await db
      .into(db.weightEntries)
      .insert(
        WeightEntriesCompanion.insert(
          id: uuid(0xA01),
          weightGrams: 99900,
          occurredAtUtc: DateTime.utc(2025, 6, 2, 6),
          localDate: LocalDate(2025, 6, 2),
          timezoneId: berlin,
          gamificationEligible: true,
          createdAtUtc: DateTime.utc(2025, 6, 2, 6),
          updatedAtUtc: DateTime.utc(2025, 6, 2, 6),
        ),
      );
  await db
      .into(db.habits)
      .insert(
        HabitsCompanion.insert(
          id: uuid(0xA02),
          title: 'Altes Habit',
          startedLocalDate: LocalDate(2025, 6, 1),
          createdAtUtc: DateTime.utc(2025, 6, 1, 6),
          updatedAtUtc: DateTime.utc(2025, 6, 1, 6),
        ),
      );
  await db
      .into(db.habitChecks)
      .insert(
        HabitChecksCompanion.insert(
          id: uuid(0xA03),
          habitId: uuid(0xA02),
          localDate: LocalDate(2025, 6, 2),
          checkedAtUtc: DateTime.utc(2025, 6, 2, 7),
          timezoneId: berlin,
          eligibility: true,
          createdAtUtc: DateTime.utc(2025, 6, 2, 7),
          updatedAtUtc: DateTime.utc(2025, 6, 2, 7),
        ),
      );
  await db
      .into(db.reminderRules)
      .insert(
        ReminderRulesCompanion.insert(
          id: uuid(0xA04),
          moduleId: 'nutrition',
          kind: 'water',
          localTime: const Value(LocalTime(9, 0)),
          enabled: true,
          route: '/old',
        ),
      );
  await db
      .into(db.xpAwards)
      .insert(
        XpAwardsCompanion.insert(
          awardKey: 'weight:2025-06-02',
          localDate: LocalDate(2025, 6, 2),
          sourceKind: 'weight',
          points: 10,
          ruleVersion: 1,
        ),
      );
  await db
      .into(db.commandReceipts)
      .insert(
        CommandReceiptsCompanion.insert(
          commandId: uuid(0xA05),
          commandType: 'weight.create',
          committedAtUtc: DateTime.utc(2025, 6, 2, 6),
        ),
      );
  await db
      .into(db.scheduledNotifications)
      .insert(
        ScheduledNotificationsCompanion.insert(
          semanticKey: 'old:key',
          fireAtUtc: DateTime.utc(2025, 6, 3, 9),
          route: '/old',
          sourceRuleId: Value(uuid(0xA04)),
        ),
      );
}
