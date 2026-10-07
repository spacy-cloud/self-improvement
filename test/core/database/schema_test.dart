import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/test_database.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../../support/db_fixtures.dart';

/// Expects a SQLite constraint violation (CHECK, UNIQUE, FOREIGN KEY, ...).
Matcher get violatesConstraint => throwsA(
  predicate<Object>(
    (e) => e.toString().toLowerCase().contains('constraint failed'),
    'a SQLite constraint violation',
  ),
);

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase db;

  setUp(() => db = createTestDatabase());
  tearDown(() => db.close());

  group('schema basics', () {
    test('starts at schema version 2 with all 20 tables', () async {
      expect(db.schemaVersion, 2);
      expect(AppDatabase.currentSchemaVersion, 2);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r.read<String>('name'))
          .get();
      expect(tables.toSet(), {
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
        'xp_awards',
        'command_receipts',
        'reminder_rules',
        'scheduled_notifications',
        'workout_day_marks',
      });
    });

    test('foreign keys are enforced', () async {
      final result = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(result.read<int>('foreign_keys'), 1);
    });

    test('schema key lists match their domain counterparts', () {
      expect(ModuleId.values.map((m) => m.key).toList(), SchemaKeys.modules);
      // Every goal type of the domain is allowed by the schema. The schema
      // additionally has `workout_daily` (BS-99), which comes with the domain
      // enum of that feature.
      for (final type in GoalType.values) {
        expect(SchemaKeys.goalTypes, contains(type.key), reason: type.key);
      }
      expect(SchemaKeys.goalTypes, contains('workout_daily'));
      expect(SchemaKeys.goalTypes.toSet(), hasLength(7));
      expect(
        SchemaKeys.dashboardCardModule.keys.toSet(),
        SchemaKeys.dashboardCards.toSet(),
      );
      expect(
        SchemaKeys.dashboardCardModule.values.toSet().difference(
          SchemaKeys.modules.toSet(),
        ),
        isEmpty,
      );
    });

    test('rows start at version 1 and reject version 0', () async {
      await db.into(db.weightEntries).insert(weightRow());
      final row = await db.select(db.weightEntries).getSingle();
      expect(row.rowVersion, 1);
      await expectLater(
        db.customStatement('UPDATE weight_entries SET row_version = 0'),
        violatesConstraint,
      );
    });
  });

  group('converters keep exact values', () {
    test('UTC milliseconds, local dates and string lists round trip', () async {
      final at = DateTime.utc(2026, 10, 3, 8, 15, 30, 123);
      await db.into(db.weightEntries).insert(weightRow(at: at));
      final weight = await db.select(db.weightEntries).getSingle();
      expect(weight.occurredAtUtc, at);
      expect(weight.occurredAtUtc.isUtc, isTrue);
      expect(weight.occurredAtUtc.millisecond, 123);
      expect(weight.localDate, fixtureDate);

      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 't1',
              title: 'x',
              tagsJson: const Value(['a', 'b ü']),
              createdAtUtc: fixtureNow,
              updatedAtUtc: fixtureNow,
            ),
          );
      final task = await db.select(db.tasks).getSingle();
      expect(task.tagsJson, ['a', 'b ü']);

      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              title: 'Lesen',
              startedLocalDate: LocalDate(2026, 2, 28),
              reminderLocalTime: const Value(LocalTime(7, 5)),
              createdAtUtc: fixtureNow,
              updatedAtUtc: fixtureNow,
            ),
          );
      final habit = await db.select(db.habits).getSingle();
      expect(habit.reminderLocalTime, const LocalTime(7, 5));
      expect(habit.startedLocalDate, LocalDate(2026, 2, 28));
      expect(habit.iconKey, 'book', reason: 'default icon');
    });

    test('invalid JSON is rejected by the database', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO workout_entries (id, training_category, '
          'duration_minutes, muscle_groups, occurred_at_utc, local_date, '
          'timezone_id, gamification_eligible, created_at_utc, updated_at_utc) '
          "VALUES ('x','cardio',30,'not json',1,'2026-10-03','Europe/Berlin',1,1,1)",
        ),
        violatesConstraint,
      );
    });
  });

  group('range and enum checks reject out-of-contract values', () {
    Future<void> insertProfile({
      int? height,
      int? age,
      int? startWeight,
      int? targetWeight,
      String? name,
    }) => db
        .into(db.profile)
        .insert(
          profileRow(
            heightCm: Value(height),
            ageYears: Value(age),
            startWeightGrams: Value(startWeight),
            targetWeightGrams: Value(targetWeight),
            displayName: Value(name),
          ),
        );

    test('profile', () async {
      await expectLater(insertProfile(height: 99), violatesConstraint);
      await expectLater(insertProfile(height: 251), violatesConstraint);
      await expectLater(insertProfile(age: 17), violatesConstraint);
      await expectLater(insertProfile(age: 121), violatesConstraint);
      await expectLater(insertProfile(startWeight: 19900), violatesConstraint);
      await expectLater(insertProfile(startWeight: 350100), violatesConstraint);
      await expectLater(insertProfile(targetWeight: 70050), violatesConstraint);
      await expectLater(insertProfile(name: ''), violatesConstraint);
      await expectLater(insertProfile(name: 'x' * 41), violatesConstraint);
      // Boundaries are valid.
      await insertProfile(
        height: 100,
        age: 18,
        startWeight: 20000,
        targetWeight: 350000,
        name: 'x' * 40,
      );
      await db.delete(db.profile).go();
      await insertProfile(height: 250, age: 120);
    });

    test('profile is a singleton with id local', () async {
      await db.into(db.profile).insert(profileRow());
      expect((await db.select(db.profile).getSingle()).id, 'local');
      await expectLater(
        db.into(db.profile).insert(profileRow(id: const Value('other'))),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.profile).insert(profileRow()),
        violatesConstraint,
        reason: 'second row with the same id',
      );
    });

    test('settings', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              createdAtUtc: fixtureNow,
              updatedAtUtc: fixtureNow,
            ),
          );
      final row = await db.select(db.appSettings).getSingle();
      expect(row.id, 'app');
      expect(row.themeMode, 'system');
      expect(row.reduceMotion, isFalse);
      expect(row.haptics, isTrue);
      expect(row.notificationsEnabled, isFalse);
      await expectLater(
        db.customStatement("UPDATE app_settings SET theme_mode = 'neon'"),
        violatesConstraint,
      );
      for (final mode in SchemaKeys.themeModes) {
        await db.customStatement(
          "UPDATE app_settings SET theme_mode = '$mode'",
        );
      }
    });

    test('weight: 20.0 to 350.0 kg in steps of 0.1 kg', () async {
      for (final bad in [19900, 350100, 71550, 71501, 0, -100]) {
        await expectLater(
          db.into(db.weightEntries).insert(weightRow(id: 'b$bad', grams: bad)),
          violatesConstraint,
          reason: '$bad g',
        );
      }
      await db
          .into(db.weightEntries)
          .insert(
            weightRow(id: 'lo', grams: 20000, at: DateTime.utc(2026, 1, 1)),
          );
      await db
          .into(db.weightEntries)
          .insert(
            weightRow(id: 'hi', grams: 350000, at: DateTime.utc(2026, 1, 2)),
          );
      await expectLater(
        db
            .into(db.weightEntries)
            .insert(
              weightRow(
                id: 'long',
                at: DateTime.utc(2026, 1, 3),
                note: Value('n' * 501),
              ),
            ),
        violatesConstraint,
      );
    });

    test('steps: 0 to 100000 (zero is a recorded value)', () async {
      await db
          .into(db.stepDays)
          .insert(stepRow(id: 'z', steps: 0, date: LocalDate(2026, 1, 1)));
      await db
          .into(db.stepDays)
          .insert(stepRow(id: 'm', steps: 100000, date: LocalDate(2026, 1, 2)));
      for (final bad in [-1, 100001]) {
        await expectLater(
          db
              .into(db.stepDays)
              .insert(
                stepRow(id: 'b$bad', steps: bad, date: LocalDate(2026, 1, 3)),
              ),
          violatesConstraint,
        );
      }
    });

    test('water: 50 to 2000 ml', () async {
      await db.into(db.waterEntries).insert(waterRow(id: 'a', ml: 50));
      await db.into(db.waterEntries).insert(waterRow(id: 'b', ml: 2000));
      for (final bad in [49, 2001, 0]) {
        await expectLater(
          db.into(db.waterEntries).insert(waterRow(id: 'x$bad', ml: bad)),
          violatesConstraint,
        );
      }
    });

    test('meal: name 1-80, kcal optional 0-5000', () async {
      await db
          .into(db.mealEntries)
          .insert(mealRow(id: 'a', kcal: const Value(0)));
      await db
          .into(db.mealEntries)
          .insert(mealRow(id: 'b', kcal: const Value(5000)));
      await db.into(db.mealEntries).insert(mealRow(id: 'c'));
      expect(
        (await (db.select(
          db.mealEntries,
        )..where((m) => m.id.equals('c'))).getSingle()).kcal,
        isNull,
        reason: 'a missing kcal stays null, never a default 0',
      );
      await expectLater(
        db
            .into(db.mealEntries)
            .insert(mealRow(id: 'd', kcal: const Value(5001))),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.mealEntries).insert(mealRow(id: 'e', kcal: const Value(-1))),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.mealEntries).insert(mealRow(id: 'f', name: '')),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.mealEntries).insert(mealRow(id: 'g', name: 'x' * 81)),
        violatesConstraint,
      );
      await db.into(db.mealEntries).insert(mealRow(id: 'h', name: 'x' * 80));
    });

    test('workout: category, duration 1-600, intensity enum', () async {
      for (final category in SchemaKeys.trainingCategories) {
        await db
            .into(db.workoutEntries)
            .insert(workoutRow(id: 'c-$category', category: category));
      }
      for (final intensity in SchemaKeys.workoutIntensities) {
        await db
            .into(db.workoutEntries)
            .insert(
              workoutRow(id: 'i-$intensity', intensity: Value(intensity)),
            );
      }
      await expectLater(
        db
            .into(db.workoutEntries)
            .insert(workoutRow(id: 'x1', category: 'upper_body')),
        violatesConstraint,
        reason: 'the old type values are not part of schema 1',
      );
      await expectLater(
        db.into(db.workoutEntries).insert(workoutRow(id: 'x2', minutes: 0)),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.workoutEntries).insert(workoutRow(id: 'x3', minutes: 601)),
        violatesConstraint,
      );
      await expectLater(
        db
            .into(db.workoutEntries)
            .insert(workoutRow(id: 'x4', intensity: const Value('extreme'))),
        violatesConstraint,
      );
      await expectLater(
        db
            .into(db.workoutEntries)
            .insert(workoutRow(id: 'x5', title: Value('t' * 81))),
        violatesConstraint,
      );
      await db
          .into(db.workoutEntries)
          .insert(workoutRow(id: 'ok1', minutes: 1));
      await db
          .into(db.workoutEntries)
          .insert(workoutRow(id: 'ok2', minutes: 600));
    });

    test(
      'task: title 1-120, priority enum, completion fields move together',
      () async {
        await db.into(db.tasks).insert(taskRow(id: 'a', title: 'x' * 120));
        await expectLater(
          db.into(db.tasks).insert(taskRow(id: 'b', title: 'x' * 121)),
          violatesConstraint,
        );
        await expectLater(
          db.into(db.tasks).insert(taskRow(id: 'c', title: '')),
          violatesConstraint,
        );
        await expectLater(
          db
              .into(db.tasks)
              .insert(taskRow(id: 'd', priority: const Value('urgent'))),
          violatesConstraint,
        );
        expect(
          (await (db.select(
            db.tasks,
          )..where((t) => t.id.equals('a'))).getSingle()).priority,
          'normal',
        );
        // completed_at without date/eligibility is inconsistent.
        await expectLater(
          db
              .into(db.tasks)
              .insert(taskRow(id: 'e', completedAt: Value(fixtureNow))),
          violatesConstraint,
        );
        await db
            .into(db.tasks)
            .insert(
              taskRow(
                id: 'f',
                completedAt: Value(fixtureNow),
                completedDate: Value(fixtureDate),
                eligibility: const Value(true),
              ),
            );
      },
    );

    test('habit: title 1-80 and icon enum', () async {
      for (final icon in SchemaKeys.habitIcons) {
        await db
            .into(db.habits)
            .insert(habitRow(id: 'h-$icon', iconKey: Value(icon)));
      }
      await expectLater(
        db
            .into(db.habits)
            .insert(habitRow(id: 'x', iconKey: const Value('star'))),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.habits).insert(habitRow(id: 'y', title: '')),
        violatesConstraint,
      );
      await expectLater(
        db.into(db.habits).insert(habitRow(id: 'z', title: 'x' * 81)),
        violatesConstraint,
      );
    });

    test('module, card, goal type, xp source and reminder enums', () async {
      Future<void> module(String id) => db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: id,
              moduleId: id,
              effectiveAtUtc: fixtureNow,
              localDate: fixtureDate,
              enabled: true,
            ),
          );
      for (final m in SchemaKeys.modules) {
        await module(m);
      }
      await expectLater(module('sleep'), violatesConstraint);

      Future<void> card(String id, String module) => db
          .into(db.dashboardCards)
          .insert(
            DashboardCardsCompanion.insert(
              cardId: id,
              moduleId: module,
              sortIndex: 0,
            ),
          );
      await card('water', 'nutrition');
      await expectLater(card('sleep', 'body'), violatesConstraint);
      await expectLater(card('steps', 'sleep'), violatesConstraint);

      Future<void> goal(String id, String type) => db
          .into(db.goalVersions)
          .insert(
            GoalVersionsCompanion.insert(
              id: id,
              goalType: type,
              enabled: true,
              effectiveFromDate: fixtureDate,
              createdAtUtc: fixtureNow,
            ),
          );
      for (final t in SchemaKeys.goalTypes) {
        await goal('g-$t', t);
      }
      await expectLater(goal('g-bad', 'calories'), violatesConstraint);

      Future<void> xp(String key, String source, int points) => db
          .into(db.xpAwards)
          .insert(
            XpAwardsCompanion.insert(
              awardKey: key,
              localDate: fixtureDate,
              sourceKind: source,
              points: points,
              ruleVersion: 1,
            ),
          );
      await xp('water:1', 'water', 5);
      await expectLater(xp('meal:1', 'meal', 0), violatesConstraint);
      await expectLater(xp('water:2', 'water', -1), violatesConstraint);

      Future<void> rule(String id, String kind) => db
          .into(db.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: id,
              moduleId: 'nutrition',
              kind: kind,
              enabled: false,
              route: '/water',
            ),
          );
      await rule('r1', 'water');
      await expectLater(rule('r2', 'task_due'), violatesConstraint);
    });
  });

  group('uniqueness and partial indexes', () {
    test('one active weight measurement per exact time (AT07)', () async {
      await db.into(db.weightEntries).insert(weightRow(id: 'a'));
      await expectLater(
        db.into(db.weightEntries).insert(weightRow(id: 'b')),
        violatesConstraint,
      );
      // A different time on the same day is fine.
      await db
          .into(db.weightEntries)
          .insert(
            weightRow(id: 'c', at: fixtureNow.add(const Duration(hours: 4))),
          );
      // A soft-deleted row no longer blocks the time (undo-delete creates the
      // conflict check in the repository, not here).
      await (db.update(db.weightEntries)..where((w) => w.id.equals('a'))).write(
        WeightEntriesCompanion(deletedAtUtc: Value(fixtureNow)),
      );
      await db.into(db.weightEntries).insert(weightRow(id: 'd'));
    });

    test('one active step total per date', () async {
      await db.into(db.stepDays).insert(stepRow(id: 'a'));
      await expectLater(
        db.into(db.stepDays).insert(stepRow(id: 'b')),
        violatesConstraint,
      );
      await db
          .into(db.stepDays)
          .insert(stepRow(id: 'c', date: LocalDate(2026, 10, 2)));
      await (db.update(db.stepDays)..where((s) => s.id.equals('a'))).write(
        StepDaysCompanion(deletedAtUtc: Value(fixtureNow)),
      );
      await db.into(db.stepDays).insert(stepRow(id: 'd'));
    });

    test('one check per habit and day (also when soft deleted)', () async {
      await db.into(db.habits).insert(habitRow());
      await db.into(db.habitChecks).insert(habitCheckRow());
      await expectLater(
        db.into(db.habitChecks).insert(habitCheckRow(id: 'hc2')),
        violatesConstraint,
      );
      await db
          .into(db.habitChecks)
          .insert(habitCheckRow(id: 'hc3', date: LocalDate(2026, 10, 2)));
    });

    test('goal versions: one per type and effective date', () async {
      Future<void> version(String id) => db
          .into(db.goalVersions)
          .insert(
            GoalVersionsCompanion.insert(
              id: id,
              goalType: 'water',
              targetInteger: const Value(2500),
              enabled: true,
              effectiveFromDate: fixtureDate,
              createdAtUtc: fixtureNow,
            ),
          );
      await version('a');
      await expectLater(version('b'), violatesConstraint);
    });

    test('snapshots: one row per day and goal key', () async {
      Future<void> snap(String id) => db
          .into(db.dailyGoalSnapshots)
          .insert(
            DailyGoalSnapshotsCompanion.insert(
              id: id,
              localDate: fixtureDate,
              goalKey: 'water',
              moduleId: 'nutrition',
              applicable: true,
            ),
          );
      await snap('a');
      await expectLater(snap('b'), violatesConstraint);
    });

    test('at most one open focus session (running/paused/awaiting)', () async {
      await db
          .into(db.focusSessions)
          .insert(focusRow(id: 'a', status: 'paused'));
      for (final status in ['running', 'paused', 'awaiting_confirmation']) {
        await expectLater(
          db
              .into(db.focusSessions)
              .insert(
                focusRow(
                  id: 'x-$status',
                  status: status,
                  segmentStartedAt: status == 'running'
                      ? Value(fixtureNow)
                      : const Value.absent(),
                ),
              ),
          violatesConstraint,
          reason: status,
        );
      }
      // Closed sessions are unlimited.
      await db
          .into(db.focusSessions)
          .insert(
            focusRow(
              id: 'c1',
              status: 'completed',
              completedDate: Value(fixtureDate),
            ),
          );
      await db
          .into(db.focusSessions)
          .insert(focusRow(id: 'd1', status: 'discarded'));
      // Resolving the open one frees the slot.
      await (db.update(db.focusSessions)..where((f) => f.id.equals('a'))).write(
        const FocusSessionsCompanion(status: Value('discarded')),
      );
      await db
          .into(db.focusSessions)
          .insert(
            focusRow(
              id: 'e',
              status: 'awaiting_confirmation',
              accumulated: 1500,
            ),
          );
    });

    test('a soft-deleted open session frees the slot', () async {
      await db.into(db.focusSessions).insert(focusRow(id: 'a'));
      await (db.update(db.focusSessions)..where((f) => f.id.equals('a'))).write(
        FocusSessionsCompanion(deletedAtUtc: Value(fixtureNow)),
      );
      await db.into(db.focusSessions).insert(focusRow(id: 'b'));
    });
  });

  group('focus session state constraints', () {
    test(
      'planned 5-180 minutes, accumulated within plan, category enum',
      () async {
        await db
            .into(db.focusSessions)
            .insert(
              focusRow(
                id: 'min',
                planned: 300,
                accumulated: 0,
                status: 'discarded',
              ),
            );
        await db
            .into(db.focusSessions)
            .insert(
              focusRow(
                id: 'max',
                planned: 10800,
                accumulated: 10800,
                status: 'discarded',
              ),
            );
        for (final planned in [299, 10801]) {
          await expectLater(
            db
                .into(db.focusSessions)
                .insert(
                  focusRow(
                    id: 'p$planned',
                    planned: planned,
                    accumulated: 0,
                    status: 'discarded',
                  ),
                ),
            violatesConstraint,
          );
        }
        await expectLater(
          db
              .into(db.focusSessions)
              .insert(
                focusRow(
                  id: 'over',
                  planned: 1500,
                  accumulated: 1501,
                  status: 'discarded',
                ),
              ),
          violatesConstraint,
        );
        await expectLater(
          db
              .into(db.focusSessions)
              .insert(
                focusRow(id: 'neg', accumulated: -1, status: 'discarded'),
              ),
          violatesConstraint,
        );
        await expectLater(
          db
              .into(db.focusSessions)
              .insert(
                focusRow(id: 'cat', category: 'gaming', status: 'discarded'),
              ),
          violatesConstraint,
        );
        await expectLater(
          db
              .into(db.focusSessions)
              .insert(focusRow(id: 'st', status: 'finished')),
          violatesConstraint,
        );
      },
    );

    test('a segment start exists exactly while running', () async {
      await expectLater(
        db.into(db.focusSessions).insert(focusRow(id: 'r1', status: 'running')),
        violatesConstraint,
        reason: 'running needs a segment start',
      );
      await expectLater(
        db
            .into(db.focusSessions)
            .insert(
              focusRow(
                id: 'p1',
                status: 'paused',
                segmentStartedAt: Value(fixtureNow),
              ),
            ),
        violatesConstraint,
        reason: 'a paused session has no running segment',
      );
      await db
          .into(db.focusSessions)
          .insert(
            focusRow(
              id: 'r2',
              status: 'running',
              segmentStartedAt: Value(fixtureNow),
            ),
          );
    });

    test('completed sessions carry their completion date', () async {
      await expectLater(
        db
            .into(db.focusSessions)
            .insert(focusRow(id: 'c1', status: 'completed')),
        violatesConstraint,
      );
      await expectLater(
        db
            .into(db.focusSessions)
            .insert(
              focusRow(
                id: 'c2',
                status: 'discarded',
                completedDate: Value(fixtureDate),
              ),
            ),
        violatesConstraint,
        reason: 'only completed sessions count on a day',
      );
    });
  });

  group('foreign keys', () {
    test('a habit check needs an existing habit', () async {
      await expectLater(
        db.into(db.habitChecks).insert(habitCheckRow(habitId: 'missing')),
        violatesConstraint,
      );
    });

    test('deleting a reminder rule clears the notification source', () async {
      await db
          .into(db.reminderRules)
          .insert(
            ReminderRulesCompanion.insert(
              id: 'r1',
              moduleId: 'nutrition',
              kind: 'water',
              enabled: true,
              route: '/water',
              localTime: const Value(LocalTime(10, 0)),
            ),
          );
      await db
          .into(db.scheduledNotifications)
          .insert(
            ScheduledNotificationsCompanion.insert(
              semanticKey: 'water:2026-10-03:10:00',
              fireAtUtc: fixtureNow,
              route: '/water',
              sourceRuleId: const Value('r1'),
            ),
          );
      final created = await db.select(db.scheduledNotifications).getSingle();
      expect(created.notificationId, greaterThan(0));
      expect(created.state, 'scheduled');
      await (db.delete(db.reminderRules)..where((r) => r.id.equals('r1'))).go();
      final after = await db.select(db.scheduledNotifications).getSingle();
      expect(after.sourceRuleId, isNull);
    });

    test(
      'notification semantic keys are unique and ids never repeat',
      () async {
        Future<void> add(String key) => db
            .into(db.scheduledNotifications)
            .insert(
              ScheduledNotificationsCompanion.insert(
                semanticKey: key,
                fireAtUtc: fixtureNow,
                route: '/',
              ),
            );
        await add('a');
        await expectLater(add('a'), violatesConstraint);
        await add('b');
        final ids = (await db.select(db.scheduledNotifications).get())
            .map((r) => r.notificationId)
            .toList();
        expect(ids.toSet(), hasLength(2));
      },
    );
  });

  group('schema 2 (BS-98): the data of BS-99, BS-97 and BS-111', () {
    WorkoutDayMarksCompanion mark({
      String id = 'k1',
      LocalDate? date,
      String kind = 'rest',
      Value<DateTime?> deletedAt = const Value.absent(),
    }) => WorkoutDayMarksCompanion.insert(
      id: id,
      localDate: date ?? fixtureDate,
      kind: kind,
      timezoneId: fixtureZone,
      deletedAtUtc: deletedAt,
      createdAtUtc: fixtureNow,
      updatedAtUtc: fixtureNow,
    );

    test(
      'workout_day_marks accepts rest and skipped, nothing else (BS-99)',
      () async {
        expect(SchemaKeys.workoutDayMarkKinds, ['rest', 'skipped']);
        var day = fixtureDate;
        for (final kind in SchemaKeys.workoutDayMarkKinds) {
          await db
              .into(db.workoutDayMarks)
              .insert(mark(id: 'k-$kind', kind: kind, date: day));
          day = day.addDays(1);
        }
        for (final kind in ['sick', 'Rest', '', 'workout']) {
          await expectLater(
            db
                .into(db.workoutDayMarks)
                .insert(mark(id: 'bad', kind: kind, date: day)),
            violatesConstraint,
            reason: '"$kind"',
          );
        }
      },
    );

    test(
      'a local date has one active mark; deleting frees the date (BS-99)',
      () async {
        await db.into(db.workoutDayMarks).insert(mark(id: 'a'));
        await expectLater(
          db.into(db.workoutDayMarks).insert(mark(id: 'b', kind: 'skipped')),
          violatesConstraint,
        );
        // Soft delete (the undo of a mark) frees the day ...
        await (db.update(db.workoutDayMarks)..where((m) => m.id.equals('a')))
            .write(WorkoutDayMarksCompanion(deletedAtUtc: Value(fixtureNow)));
        await db
            .into(db.workoutDayMarks)
            .insert(mark(id: 'b', kind: 'skipped'));
        // ... and bringing the old one back while another is active is refused,
        // which the repository must resolve (update instead of insert).
        await expectLater(
          (db.update(db.workoutDayMarks)..where((m) => m.id.equals('a'))).write(
            const WorkoutDayMarksCompanion(deletedAtUtc: Value(null)),
          ),
          violatesConstraint,
        );
        await db
            .into(db.workoutDayMarks)
            .insert(mark(id: 'c', date: fixtureDate.addDays(1)));
      },
    );

    test(
      'workout_day_marks has the audit columns of the facts (BS-99)',
      () async {
        await db.into(db.workoutDayMarks).insert(mark());
        final row = await db.select(db.workoutDayMarks).getSingle();
        expect(row.rowVersion, 1);
        expect(row.deletedAtUtc, isNull);
        expect(row.createdAtUtc, fixtureNow);
        expect(row.createdAtUtc.isUtc, isTrue);
        expect(row.localDate, fixtureDate);
        expect(row.timezoneId, fixtureZone);
        await expectLater(
          db.customStatement('UPDATE workout_day_marks SET row_version = 0'),
          violatesConstraint,
        );
      },
    );

    test(
      'goal_versions accepts every goal type including workout_daily (BS-99)',
      () async {
        for (final type in SchemaKeys.goalTypes) {
          await db
              .into(db.goalVersions)
              .insert(
                GoalVersionsCompanion.insert(
                  id: 'g-$type',
                  goalType: type,
                  targetInteger: const Value(1),
                  enabled: false,
                  effectiveFromDate: fixtureDate,
                  createdAtUtc: fixtureNow,
                ),
              );
        }
        final stored = await db.select(db.goalVersions).get();
        expect(stored.map((g) => g.goalType), contains('workout_daily'));
        await expectLater(
          db
              .into(db.goalVersions)
              .insert(
                GoalVersionsCompanion.insert(
                  id: 'g-bad',
                  goalType: 'workout_monthly',
                  enabled: true,
                  effectiveFromDate: fixtureDate,
                  createdAtUtc: fixtureNow,
                ),
              ),
          violatesConstraint,
        );
      },
    );

    test(
      'step_days.source defaults to manual and takes manual or health (BS-97)',
      () async {
        expect(SchemaKeys.stepSources, ['manual', 'health']);
        await db.into(db.stepDays).insert(stepRow(id: 'a'));
        expect((await db.select(db.stepDays).getSingle()).source, 'manual');
        var day = fixtureDate;
        for (final source in SchemaKeys.stepSources) {
          day = day.addDays(1);
          await db
              .into(db.stepDays)
              .insert(
                stepRow(
                  id: 's-$source',
                  date: day,
                ).copyWith(source: Value(source)),
              );
        }
        for (final source in ['watch', 'Health', '']) {
          day = day.addDays(1);
          await expectLater(
            db
                .into(db.stepDays)
                .insert(
                  stepRow(id: 'bad', date: day).copyWith(source: Value(source)),
                ),
            violatesConstraint,
            reason: '"$source"',
          );
        }
      },
    );

    test('app_settings: the health comparison is off and never ran by default (BS-97)', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              createdAtUtc: fixtureNow,
              updatedAtUtc: fixtureNow,
            ),
          );
      var row = await db.select(db.appSettings).getSingle();
      expect(row.healthStepsSyncEnabled, isFalse);
      expect(row.healthStepsLastSyncAtUtc, isNull);
      final at = DateTime.utc(2026, 10, 3, 7, 59, 58, 123);
      await db
          .update(db.appSettings)
          .write(
            AppSettingsCompanion(
              healthStepsSyncEnabled: const Value(true),
              healthStepsLastSyncAtUtc: Value(at),
            ),
          );
      row = await db.select(db.appSettings).getSingle();
      expect(row.healthStepsSyncEnabled, isTrue);
      expect(row.healthStepsLastSyncAtUtc, at);
      expect(row.healthStepsLastSyncAtUtc!.isUtc, isTrue);
      await expectLater(
        db.customStatement(
          'UPDATE app_settings SET health_steps_sync_enabled = 2',
        ),
        violatesConstraint,
      );
    });

    test('tasks.reminder_*: an instant with its frozen date and zone, or nothing (BS-111)', () async {
      await db.into(db.tasks).insert(taskRow(id: 'plain'));
      final plain = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('plain'))).getSingle();
      expect(plain.reminderAtUtc, isNull);
      expect(plain.reminderLocalDate, isNull);
      expect(plain.reminderTimezoneId, isNull);

      final at = DateTime.utc(2026, 10, 7, 15, 30, 0, 250);
      await db
          .into(db.tasks)
          .insert(
            taskRow(id: 'with').copyWith(
              reminderAtUtc: Value(at),
              reminderLocalDate: Value(LocalDate(2026, 10, 7)),
              reminderTimezoneId: const Value('Europe/Berlin'),
            ),
          );
      final stored = await (db.select(
        db.tasks,
      )..where((t) => t.id.equals('with'))).getSingle();
      expect(stored.reminderAtUtc, at);
      expect(stored.reminderAtUtc!.isUtc, isTrue);
      expect(stored.reminderLocalDate, LocalDate(2026, 10, 7));
      expect(stored.reminderTimezoneId, 'Europe/Berlin');

      // Partial reminders violate the coupling of the three columns.
      for (final partial in <TasksCompanion>[
        TasksCompanion(reminderAtUtc: Value(at)),
        TasksCompanion(reminderLocalDate: Value(LocalDate(2026, 10, 7))),
        const TasksCompanion(reminderTimezoneId: Value('UTC')),
        TasksCompanion(
          reminderAtUtc: Value(at),
          reminderLocalDate: Value(LocalDate(2026, 10, 7)),
        ),
      ]) {
        await expectLater(
          (db.update(
            db.tasks,
          )..where((t) => t.id.equals('plain'))).write(partial),
          violatesConstraint,
        );
      }
      // Removing the reminder clears all three together.
      await (db.update(db.tasks)..where((t) => t.id.equals('with'))).write(
        const TasksCompanion(
          reminderAtUtc: Value(null),
          reminderLocalDate: Value(null),
          reminderTimezoneId: Value(null),
        ),
      );
    });

    test(
      'a completed task keeps its reminder; the two are independent (BS-111)',
      () async {
        await db
            .into(db.tasks)
            .insert(
              taskRow(
                id: 'done',
                completedAt: Value(fixtureNow),
                completedDate: Value(fixtureDate),
                eligibility: const Value(true),
              ).copyWith(
                reminderAtUtc: Value(fixtureNow),
                reminderLocalDate: Value(fixtureDate),
                reminderTimezoneId: const Value(fixtureZone),
              ),
            );
        expect(
          (await db.select(db.tasks).getSingle()).reminderAtUtc,
          fixtureNow,
        );
      },
    );
  });

  group('persistence across reopening', () {
    test('data survives closing and reopening a file database', () async {
      final dir = await Directory.systemTemp.createTemp('si_db_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/test.sqlite');

      final first = AppDatabase(NativeDatabase(file));
      await first.into(first.weightEntries).insert(weightRow());
      await first.close();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      final rows = await second.select(second.weightEntries).get();
      expect(rows.single.weightGrams, 71500);
      final version = await second
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);
      // Constraints are still enforced after reopening.
      await expectLater(
        second.into(second.weightEntries).insert(weightRow(id: 'dup')),
        violatesConstraint,
      );
    });
  });
}
