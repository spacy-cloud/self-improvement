import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_codec.dart';
import 'package:self_improvement/core/backup/backup_document.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/snapshot_consistency_checker.dart';
import 'package:self_improvement/core/bootstrap/app_bootstrap.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/backup_fixtures.dart';

/// Records which SELECTs ran inside a transaction.
final class _SelectRecorder extends QueryInterceptor {
  int begins = 0;
  int commits = 0;
  final List<bool> selectsInTransaction = [];
  final List<String> statements = [];

  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    begins++;
    return super.beginTransaction(parent);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    commits++;
    return super.commitTransaction(inner);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selectsInTransaction.add(executor is TransactionExecutor);
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}

Map<String, Object?> decode(ExportedBackup backup) =>
    jsonDecode(utf8.decode(backup.bytes)) as Map<String, Object?>;

Map<String, Object?> sectionsOf(ExportedBackup backup) =>
    decode(backup)['data']! as Map<String, Object?>;

List<Map<String, Object?>> rowsOf(ExportedBackup backup, String table) =>
    (sectionsOf(backup)[table]! as List<Object?>).cast<Map<String, Object?>>();

Set<Object?> idsOf(ExportedBackup backup, String table) => {
  for (final row in rowsOf(backup, table)) row['id'],
};

void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late DataHarness harness;
  late BackupExporter exporter;

  /// A harness disposed after the test.
  Future<DataHarness> create({String nowIso = '2026-10-03T08:00:00Z'}) async {
    final created = await DataHarness.create(nowIso: nowIso);
    addTearDown(created.dispose);
    return created;
  }

  Future<void> useRichDatabase() async {
    harness = await create();
    await populateRichDatabase(harness.database);
    exporter = BackupExporter(database: harness.database, clock: harness.clock);
  }

  group('content of a rich database', () {
    setUp(useRichDatabase);

    test('root fields and the sixteen sections in file order', () async {
      final backup = await exporter.export();
      final root = decode(backup);
      expect(root.keys.toList(), [
        'format',
        'schemaVersion',
        'exportedAtUtc',
        'appVersion',
        'data',
      ]);
      expect(root['format'], 'levelup_life_backup');
      expect(root['format'], AppConfig.backupFormat);
      expect(root['schemaVersion'], 1);
      expect(root['exportedAtUtc'], '2026-10-03T08:00:00.000Z');
      expect(root['appVersion'], AppConfig.appVersion);
      expect(sectionsOf(backup).keys.toList(), [
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
      ]);
      expect(
        sectionsOf(backup).keys.toList(),
        BackupTable.values.map((t) => t.key).toList(),
      );
    });

    test('singletons are objects, all other sections are arrays', () async {
      final data = sectionsOf(await exporter.export());
      for (final table in BackupTable.values) {
        expect(
          data[table.key],
          table.isSingleton
              ? isA<Map<String, Object?>>()
              : isA<List<Object?>>(),
          reason: table.key,
        );
      }
    });

    test('is UTF-8 JSON, compact, with real JSON types', () async {
      final backup = await exporter.export();
      final text = utf8.decode(backup.bytes);
      expect(text.contains('\n'), isFalse, reason: 'compact, no indentation');
      expect(text.contains('  '), isFalse);
      final weight = rowsOf(backup, 'weight_entries').first;
      expect(weight['weight_grams'], isA<int>());
      expect(weight['before_toilet'], isA<bool>());
      expect(weight['note'], isA<String>());
      expect(weight['occurred_at_utc'], '2026-03-02T06:30:15.250Z');
      expect(weight['local_date'], '2026-03-02');
    });

    test('non-ASCII text is written as UTF-8, not escaped', () async {
      await harness.database
          .into(harness.database.mealEntries)
          .insert(
            MealEntriesCompanion.insert(
              id: uuid(0x777),
              name: 'Müsli mit Äpfeln \u{1F600}',
              occurredAtUtc: at(6, 7),
              localDate: march(6),
              timezoneId: berlin,
              createdAtUtc: at(6, 7),
              updatedAtUtc: at(6, 7),
            ),
          );
      final backup = await exporter.export();
      expect(utf8.decode(backup.bytes), contains('Müsli mit Äpfeln \u{1F600}'));
      expect(
        rowsOf(backup, 'meal_entries').map((m) => m['name']),
        contains('Müsli mit Äpfeln \u{1F600}'),
      );
    });

    test('exports only active records', () async {
      final backup = await exporter.export();
      final expectedCounts = {
        'profile': 1,
        'app_settings': 1,
        'module_status_history': 7,
        'dashboard_cards': 8,
        'goal_versions': 5,
        'daily_goal_snapshots': 5,
        'weight_entries': 3,
        'step_days': 3,
        'water_entries': 3,
        'meal_entries': 3,
        'focus_sessions': 3,
        'workout_entries': 2,
        'tasks': 3,
        'habits': 2,
        'habit_checks': 3,
        'reminder_rules': 3,
      };
      for (final table in BackupTable.values) {
        final section = sectionsOf(backup)[table.key];
        expect(
          table.isSingleton ? 1 : (section! as List<Object?>).length,
          expectedCounts[table.key],
          reason: table.key,
        );
      }
      expect(backup.counts[BackupTable.weightEntries], 3);
      expect(backup.recordCount, expectedCounts.values.reduce((a, b) => a + b));
    });

    test('soft-deleted rows are not exported', () async {
      final backup = await exporter.export();
      final deletedIds = {
        uuid(0x104), // weight
        uuid(0x114), // step day
        uuid(0x124), // water
        uuid(0x134), // meal
        uuid(0x304), // focus session
        uuid(0x143), // workout
        uuid(0x154), // task
        Ids.habitDeleted,
        uuid(0x504), // habit check
      };
      final text = utf8.decode(backup.bytes);
      for (final id in deletedIds) {
        // The snapshot of the deleted habit legitimately mentions its id.
        final mentions = RegExp(id).allMatches(text).length;
        expect(
          mentions,
          id == Ids.habitDeleted ? 1 : 0,
          reason: 'soft-deleted $id',
        );
      }
      expect(text, isNot(contains('deleted_at_utc')));
    });

    test('an active check of a deleted habit is not exported', () async {
      final backup = await exporter.export();
      expect(idsOf(backup, 'habit_checks'), isNot(contains(uuid(0x505))));
      expect(rowsOf(backup, 'habit_checks').map((c) => c['habit_id']).toSet(), {
        Ids.habitReading,
        Ids.habitMeditation,
      });
      expect(backup.isRestorable, isTrue);
    });

    test('the history snapshot of a deleted habit is kept', () async {
      final backup = await exporter.export();
      expect(
        rowsOf(backup, 'daily_goal_snapshots').map((s) => s['goal_key']),
        contains('habit:${Ids.habitDeleted}'),
      );
    });

    test('technical tables are never exported', () async {
      final backup = await exporter.export();
      final text = utf8.decode(backup.bytes);
      for (final needle in [
        'xp_awards',
        'command_receipts',
        'scheduled_notifications',
        'weight:2026-03-02', // an XP award key
        'weight.create', // a command type
        'water:2026-03-03:10:00', // a notification key
        'award_key',
        'command_id',
        'semantic_key',
      ]) {
        expect(text, isNot(contains(needle)), reason: needle);
      }
    });

    test('carries no stored XP or streak counters', () async {
      final text = utf8.decode((await exporter.export()).bytes);
      final keys = RegExp(r'"([a-z_]+)":')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        keys.where(
          (k) =>
              k.contains('streak') ||
              k.contains('total') ||
              k.contains('level') ||
              k == 'points' ||
              k == 'xp',
        ),
        isEmpty,
      );
      // The only XP-related field is the frozen step threshold.
      expect(keys.where((k) => k.contains('xp')), {'xp_goal_target_steps'});
    });

    test('keeps ids, versions and every eligibility flag', () async {
      final backup = await exporter.export();
      final weights = rowsOf(backup, 'weight_entries');
      expect(weights.map((w) => w['id']), [
        Ids.weightFirst,
        uuid(0x102),
        uuid(0x103),
      ]);
      expect(weights.map((w) => w['row_version']), [2, 1, 1]);
      expect(weights.map((w) => w['gamification_eligible']), [
        true,
        false,
        true,
      ]);
      expect(
        rowsOf(backup, 'step_days').map((s) => s['reached_goal_eligible']),
        [true, null, false],
      );
      expect(rowsOf(backup, 'tasks').map((t) => t['completion_eligibility']), [
        null,
        false,
        true,
      ]);
      expect(rowsOf(backup, 'habit_checks').map((c) => c['eligibility']), [
        true,
        true,
        false,
      ]);
      expect(
        rowsOf(backup, 'focus_sessions').map((f) => f['gamification_eligible']),
        [true, false, false],
      );
    });

    test('data of deactivated modules is included', () async {
      final db = harness.database;
      const modules = ['body', 'nutrition', 'focus', 'tasks'];
      for (final (index, module) in modules.indexed) {
        await db
            .into(db.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: uuid(0x900 + index),
                moduleId: module,
                effectiveAtUtc: at(20, 12),
                localDate: march(20),
                enabled: false,
              ),
            );
      }
      final backup = await exporter.export();
      expect(rowsOf(backup, 'weight_entries'), hasLength(3));
      expect(rowsOf(backup, 'water_entries'), hasLength(3));
      expect(rowsOf(backup, 'focus_sessions'), hasLength(3));
      expect(rowsOf(backup, 'tasks'), hasLength(3));
      expect(rowsOf(backup, 'module_status_history'), hasLength(11));
    });

    test(
      'rows are ordered by business time and id, not by insertion',
      () async {
        final backup = await exporter.export();
        List<Object?> column(String table, String key) => [
          for (final row in rowsOf(backup, table)) row[key],
        ];
        // Goal versions were inserted with the 2026-01-05 focus goal last.
        expect(column('goal_versions', 'goal_type'), [
          'focus_minutes',
          'steps',
          'water',
          'weight_entry',
          'water',
        ]);
        expect(column('dashboard_cards', 'sort_index'), [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ]);
        expect(column('dashboard_cards', 'card_id').first, 'xp');
        expect(column('weight_entries', 'occurred_at_utc'), [
          '2026-03-02T06:30:15.250Z',
          '2026-03-03T06:31:00.000Z',
          '2026-03-04T05:00:00.000Z',
        ]);
        expect(column('step_days', 'local_date'), [
          '2026-03-02',
          '2026-03-03',
          '2026-03-04',
        ]);
        expect(column('habit_checks', 'local_date'), [
          '2026-03-02',
          '2026-03-02',
          '2026-03-03',
        ]);
        expect(column('module_status_history', 'effective_at_utc'), [
          for (var i = 0; i < 5; i++) '2026-03-01T07:15:30.123Z',
          '2026-03-08T10:00:00.999Z',
          '2026-03-09T10:00:00.000Z',
        ]);
        expect(column('reminder_rules', 'id'), [
          Ids.ruleWater,
          uuid(0x702),
          uuid(0x703),
        ]);
      },
    );

    test('equal sort keys fall back to the id', () async {
      final db = harness.database;
      // Three weights at the same instant would violate the unique index, so
      // use water entries (no such index) with equal times.
      for (final n in [0x7ff, 0x700, 0x7aa]) {
        await db
            .into(db.waterEntries)
            .insert(
              WaterEntriesCompanion.insert(
                id: uuid(n),
                amountMl: 100,
                occurredAtUtc: at(7, 7),
                localDate: march(7),
                timezoneId: berlin,
                gamificationEligible: true,
                createdAtUtc: at(7, 7),
                updatedAtUtc: at(7, 7),
              ),
            );
      }
      final ids = rowsOf(await exporter.export(), 'water_entries')
          .where((w) => w['occurred_at_utc'] == '2026-03-07T07:00:00.000Z')
          .map((w) => w['id'])
          .toList();
      expect(ids, [uuid(0x700), uuid(0x7aa), uuid(0x7ff)]);
    });

    test('identical data gives byte-identical files', () async {
      final first = await exporter.export();
      final second = await exporter.export();
      expect(second.bytes, first.bytes);
      expect(second.fileName, first.fileName);
    });

    test('the export does not change the database', () async {
      final before = await dumpDatabase(harness.database);
      await exporter.export();
      expect(await dumpDatabase(harness.database), before);
    });

    test('the file passes the import validation (restorable)', () async {
      final backup = await exporter.export();
      expect(backup.importCheck.isValid, isTrue);
      expect(backup.isRestorable, isTrue);
      expect(backup.path, isNull, reason: 'no file written by the exporter');
    });

    test('the written bytes are exactly the encoded document', () async {
      final backup = await exporter.export();
      final document = await exporter.readDocument(harness.clock.nowUtc());
      expect(BackupCodec.encode(document), backup.bytes);
      expect(backup.counts, document.data.counts);
    });
  });

  group('running focus session', () {
    // The harness starts at 2026-10-03T08:00:00Z.
    final now = DateTime.utc(2026, 10, 3, 8);

    Future<void> insertRunning({
      int planned = 3600,
      int accumulated = 600,
      DateTime? segmentStart,
    }) async {
      final db = harness.database;
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: uuid(0xF01),
              category: 'programming',
              plannedSeconds: planned,
              accumulatedSeconds: Value(accumulated),
              segmentStartedAtUtc: Value(
                segmentStart ?? now.subtract(const Duration(minutes: 10)),
              ),
              startedAtUtc: now.subtract(const Duration(minutes: 40)),
              timezoneId: berlin,
              status: 'running',
              note: const Value('Zwischenstand'),
              gamificationEligible: const Value(false),
              createdAtUtc: now.subtract(const Duration(minutes: 40)),
              updatedAtUtc: now.subtract(const Duration(minutes: 10)),
              rowVersion: const Value(3),
            ),
          );
    }

    setUp(() async {
      harness = await create();
      exporter = BackupExporter(
        database: harness.database,
        clock: harness.clock,
      );
    });

    Map<String, Object?> exportedSession(ExportedBackup backup) =>
        rowsOf(backup, 'focus_sessions').single;

    test(
      'is exported as paused with the duration computed at export time',
      () async {
        await insertRunning();
        final session = exportedSession(await exporter.export());
        expect(session['status'], 'paused');
        expect(
          session['accumulated_seconds'],
          1200,
          reason: '600 + 10 minutes',
        );
        expect(session['segment_started_at_utc'], isNull);
        expect(session['planned_seconds'], 3600);
        expect(session['note'], 'Zwischenstand');
        expect(session['row_version'], 3);
      },
    );

    test('the live database is not changed', () async {
      await insertRunning();
      final before = await dumpDatabase(harness.database);
      await exporter.export();
      expect(await dumpDatabase(harness.database), before);
      final row = await harness.database
          .select(harness.database.focusSessions)
          .getSingle();
      expect(row.status, 'running');
      expect(row.accumulatedSeconds, 600);
      expect(row.segmentStartedAtUtc, isNotNull);
    });

    test('later exports see more elapsed time of the same segment', () async {
      await insertRunning();
      final first = exportedSession(await exporter.export());
      harness.clock.advance(const Duration(minutes: 5));
      final second = exportedSession(await exporter.export());
      expect(first['accumulated_seconds'], 1200);
      expect(second['accumulated_seconds'], 1500);
    });

    test('is clamped to the planned duration', () async {
      await insertRunning(planned: 900);
      final session = exportedSession(await exporter.export());
      expect(session['accumulated_seconds'], 900);
      expect(session['status'], 'paused');
    });

    test('a clock set back adds nothing', () async {
      await insertRunning(
        segmentStart: now.add(const Duration(hours: 3)),
        accumulated: 100,
      );
      final session = exportedSession(await exporter.export());
      expect(session['accumulated_seconds'], 100);
      expect(session['status'], 'paused');
    });

    test(
      'the resulting file is importable and has no running session',
      () async {
        await insertRunning();
        final backup = await exporter.export();
        expect(backup.isRestorable, isTrue);
        expect(utf8.decode(backup.bytes), isNot(contains('"running"')));
      },
    );
  });

  group('file name (local time of the export)', () {
    Future<String> nameAt(String isoUtc, {String zone = berlin}) async {
      final clock = FakeClock.at(isoUtc, timeZoneId: zone);
      return BackupFileName.forInstant(clock, clock.nowUtc());
    }

    test('summer time: UTC+2', () async {
      expect(
        await nameAt('2026-07-15T21:30:00Z'),
        'self-improvement-backup-2026-07-15-2330.json',
      );
    });

    test('winter time: UTC+1, hour and minute zero padded', () async {
      expect(
        await nameAt('2026-01-05T07:05:00Z'),
        'self-improvement-backup-2026-01-05-0805.json',
      );
    });

    test('the local date can differ from the UTC date', () async {
      expect(
        await nameAt('2026-12-31T23:05:00Z'),
        'self-improvement-backup-2027-01-01-0005.json',
      );
      expect(
        await nameAt('2026-03-02T02:30:00Z', zone: 'America/New_York'),
        'self-improvement-backup-2026-03-01-2130.json',
      );
      expect(
        await nameAt('2026-03-02T20:00:00Z', zone: 'Asia/Kolkata'),
        'self-improvement-backup-2026-03-03-0130.json',
      );
    });

    test('around the spring DST change', () async {
      expect(
        await nameAt('2026-03-29T00:59:00Z'),
        'self-improvement-backup-2026-03-29-0159.json',
      );
      expect(
        await nameAt('2026-03-29T01:00:00Z'),
        'self-improvement-backup-2026-03-29-0300.json',
      );
    });

    test('midnight and the last minute of a day', () async {
      expect(
        await nameAt('2026-05-31T22:00:00Z'),
        'self-improvement-backup-2026-06-01-0000.json',
      );
      expect(
        await nameAt('2026-06-01T21:59:00Z'),
        'self-improvement-backup-2026-06-01-2359.json',
      );
    });

    test('the exporter uses the clock of the export', () async {
      harness = await create(nowIso: '2026-07-15T21:30:00Z');
      final backup = await BackupExporter(
        database: harness.database,
        clock: harness.clock,
      ).export();
      expect(backup.fileName, 'self-improvement-backup-2026-07-15-2330.json');
      expect(decode(backup)['exportedAtUtc'], '2026-07-15T21:30:00.000Z');
      expect(backup.exportedAtUtc, DateTime.utc(2026, 7, 15, 21, 30));
    });

    test('a changed zone changes the name but not exportedAtUtc', () async {
      harness = await create(nowIso: '2026-07-15T21:30:00Z');
      harness.clock.setTimeZone('Asia/Tokyo');
      final backup = await BackupExporter(
        database: harness.database,
        clock: harness.clock,
      ).export();
      expect(backup.fileName, 'self-improvement-backup-2026-07-16-0630.json');
      expect(decode(backup)['exportedAtUtc'], '2026-07-15T21:30:00.000Z');
    });

    test('isBackupFileName accepts only exactly this shape', () {
      expect(
        BackupFileName.isBackupFileName(
          'self-improvement-backup-2026-07-15-2330.json',
        ),
        isTrue,
      );
      for (final bad in [
        '',
        '../self-improvement-backup-2026-07-15-2330.json',
        'sub/self-improvement-backup-2026-07-15-2330.json',
        'self-improvement-backup-2026-07-15-2330.json.bak',
        'self-improvement-backup-2026-07-15-233.json',
        'self-improvement-backup-2026-7-15-2330.json',
        'levelup-life-backup-2026-07-15-2330.json',
        'Self-Improvement-Backup-2026-07-15-2330.json',
        'self-improvement-backup-2026-07-15-2330.json\n',
        'xself-improvement-backup-2026-07-15-2330.json',
      ]) {
        expect(BackupFileName.isBackupFileName(bad), isFalse, reason: bad);
      }
    });

    test('every generated name has the documented shape', () {
      for (final iso in [
        '2026-01-01T00:00:00Z',
        '2026-06-30T12:34:56Z',
        '2026-10-25T00:30:00Z', // before the autumn DST change
        '2026-10-25T01:30:00Z', // after it (ambiguous local hour)
      ]) {
        final clock = FakeClock.at(iso);
        expect(
          BackupFileName.isBackupFileName(
            BackupFileName.forInstant(clock, clock.nowUtc()),
          ),
          isTrue,
          reason: iso,
        );
      }
    });
  });

  group('one consistent snapshot', () {
    test('all reads happen inside a single transaction', () async {
      final recorder = _SelectRecorder();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
      addTearDown(db.close);
      final clock = FakeClock.at('2026-10-03T08:00:00Z');
      await AppBootstrap.run(database: db, clock: clock);
      await populateRichDatabase(db);
      final exporterUnderTest = BackupExporter(database: db, clock: clock);

      recorder
        ..begins = 0
        ..commits = 0
        ..selectsInTransaction.clear()
        ..statements.clear();
      await exporterUnderTest.export();

      expect(recorder.begins, 1);
      expect(recorder.commits, 1);
      expect(
        recorder.statements.length,
        greaterThanOrEqualTo(BackupTable.values.length),
        reason: 'every section is read with its own query',
      );
      expect(
        recorder.selectsInTransaction,
        everyElement(isTrue),
        reason: 'no read outside the transaction',
      );
    });
  });

  group('self check of the export', () {
    setUp(useRichDatabase);

    test(
      'a database state the import would refuse is flagged, not hidden',
      () async {
        // Six tags are not valid (at most five); nothing in the database stops
        // them.
        await harness.database
            .into(harness.database.tasks)
            .insert(
              TasksCompanion.insert(
                id: uuid(0x999),
                title: 'Zu viele Tags',
                tagsJson: const Value(['a', 'b', 'c', 'd', 'e', 'f']),
                createdAtUtc: at(9, 9),
                updatedAtUtc: at(9, 9),
              ),
            );
        final backup = await exporter.export();
        expect(backup.isRestorable, isFalse);
        expect(
          backup.importCheck.problems.single.displayText,
          startsWith('tasks['),
        );
        expect(backup.bytes, isNotEmpty, reason: 'the backup is still created');
      },
    );

    test(
      'a failing check never prevents the backup, it only marks it',
      () async {
        final fragile = BackupExporter(
          database: harness.database,
          clock: harness.clock,
          validator: BackupValidator(snapshotChecker: _ThrowingChecker()),
        );
        final backup = await fragile.export();
        expect(backup.bytes, isNotEmpty);
        expect(backup.isRestorable, isFalse);
        expect(
          backup.importCheck.problems.single.message,
          contains('fehlgeschlagen'),
        );
        // The same bytes are what a healthy exporter writes.
        final healthy = await exporter.export();
        expect(backup.bytes, healthy.bytes);
      },
    );

    test('a file above the size limit is flagged as not restorable', () async {
      // 10,500 tasks with the longest allowed description exceed 10 MiB.
      final db = harness.database;
      final description = 'ä' * 1000;
      await db.batch((b) {
        b.insertAll(db.tasks, [
          for (var i = 0; i < 10500; i++)
            TasksCompanion.insert(
              id: uuid(0x400000 + i),
              title: 'Aufgabe',
              description: Value(description),
              createdAtUtc: at(10, 1),
              updatedAtUtc: at(10, 1),
            ),
        ]);
      });
      final backup = await exporter.export();
      expect(backup.bytes.length, greaterThan(BackupFormat.maxFileBytes));
      expect(backup.isRestorable, isFalse);
      expect(backup.importCheck.problems.single.location, 'file');
      expect(backup.importCheck.problems.single.message, contains('10 MiB'));
    });
  });

  group('edge cases', () {
    test('an empty database exports just the singletons', () async {
      harness = await create();
      final backup = await BackupExporter(
        database: harness.database,
        clock: harness.clock,
      ).export();
      expect(backup.recordCount, 2);
      expect(backup.isRestorable, isTrue);
      expect(rowsOf(backup, 'weight_entries'), isEmpty);
      final profile = sectionsOf(backup)['profile']! as Map<String, Object?>;
      expect(profile['display_name'], isNull);
      expect(profile['onboarding_completed'], false);
      expect(profile['started_local_date'], LocalDate(2026, 10, 3).toIso());
      expect(profile['motivation_goals'], <Object?>[]);
    });

    test('a database without the singleton rows cannot be exported', () async {
      harness = await create();
      await harness.database.delete(harness.database.profile).go();
      expect(
        BackupExporter(
          database: harness.database,
          clock: harness.clock,
        ).export(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// A checker with a bug.
final class _ThrowingChecker implements SnapshotConsistencyChecker {
  @override
  List<ImportProblem> check(BackupData data) => throw StateError('bug');
}
