import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/backup_importer.dart';
import 'package:self_improvement/core/backup/backup_validator.dart';
import 'package:self_improvement/core/goals/data/day_status_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/data/workout_day_mark_repository.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Export and import with the data the commands of BS-99 write: rest days and
/// skipped days, a taken back mark, the daily goal and the snapshots with the
/// goal key `workout_daily`. The format itself is the business of the data
/// contract (BS-98); this proves that what the commands write survives it.
void main() {
  setUpAll(() {
    TimeZones.ensureInitialized();
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late DataHarness source;
  late DataHarness target;

  final today = LocalDate(2026, 10, 3);
  final days = [for (var i = -3; i <= 0; i++) today.addDays(i)];

  setUp(() async {
    source = await DataHarness.create(realProjection: true);
    target = await DataHarness.create(realProjection: true);
    addTearDown(source.dispose);
    addTearDown(target.dispose);
    await source.seedOnboarded(
      startedOn: LocalDate(2026, 9, 1),
      workoutDailyGoal: true,
    );

    final marks = WorkoutDayMarkRepository(
      database: source.database,
      runner: source.runner,
    );
    // 09-30 was marked and taken back, 10-01 is a rest day, 10-02 a skipped
    // day, 10-03 has a workout.
    final removed = await marks.mark(
      commandId: source.ids.newId(),
      kind: WorkoutDayMarkKind.rest,
      date: days[0],
    );
    await marks.unmark(commandId: source.ids.newId(), id: removed.entityId!);
    await marks.mark(
      commandId: source.ids.newId(),
      kind: WorkoutDayMarkKind.rest,
      date: days[1],
    );
    await marks.mark(
      commandId: source.ids.newId(),
      kind: WorkoutDayMarkKind.skipped,
      date: days[2],
    );
    await WorkoutRepository(
      database: source.database,
      runner: source.runner,
    ).create(
      commandId: source.ids.newId(),
      draft: WorkoutDraft(
        category: TrainingCategory.cardio,
        durationMinutes: 30,
        occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
      ),
    );
  });

  Future<ExportedBackup> exportOf(DataHarness harness) =>
      BackupExporter(database: harness.database, clock: harness.clock).export();

  Future<void> importInto(DataHarness harness, ExportedBackup backup) async {
    final result = const BackupValidator().validateBytes(backup.bytes);
    expect(result.report.problems, isEmpty);
    await BackupImporter(
      database: harness.database,
      projections: harness.projections,
    ).replaceAll(result.document!);
  }

  /// What the Workout card and the ring read for [day]: the goal, whether it
  /// is reached, and the numbers of the ring.
  Future<List<Object?>> readDay(
    DayStatusRepository status,
    LocalDate day,
  ) async {
    final dayStatus = (await status.statusFor(day))!;
    final goal = dayStatus.progressOf(GoalType.workoutDaily);
    return [
      day.toIso(),
      goal?.applicable,
      goal?.fulfilled,
      goal?.current,
      dayStatus.applicableCount,
      dayStatus.fulfilledCount,
      dayStatus.isActive,
    ];
  }

  test(
    '(BS-99, AT30) the export holds the active marks only, in date order',
    () async {
      final backup = await exportOf(source);
      final document = const BackupValidator()
          .validateBytes(backup.bytes)
          .document!;
      final marks = document.data.workoutDayMarks;
      expect(marks.map((m) => m.localDate), [days[1], days[2]]);
      expect(marks.map((m) => m.kind), [
        WorkoutDayMarkKind.rest.key,
        WorkoutDayMarkKind.skipped.key,
      ], reason: 'the mark that was taken back is not exported');
      expect(marks.every((m) => m.timezoneId == 'Europe/Berlin'), isTrue);
    },
  );

  test(
    '(BS-99, AT30) marks, the goal and the snapshots come back row by row',
    () async {
      final backup = await exportOf(source);
      await importInto(target, backup);

      final sourceMarks = await (source.database.select(
        source.database.workoutDayMarks,
      )..where((m) => m.deletedAtUtc.isNull())).get();
      final targetMarks = await target.database
          .select(target.database.workoutDayMarks)
          .get();
      expect(sourceMarks, hasLength(2));
      expect(
        [
          for (final m in targetMarks)
            (
              m.id,
              m.localDate,
              m.kind,
              m.timezoneId,
              m.createdAtUtc,
              m.updatedAtUtc,
              m.rowVersion,
              m.deletedAtUtc,
            ),
        ]..sort((a, b) => a.$2.compareTo(b.$2)),
        [
          for (final m in sourceMarks)
            (
              m.id,
              m.localDate,
              m.kind,
              m.timezoneId,
              m.createdAtUtc,
              m.updatedAtUtc,
              m.rowVersion,
              m.deletedAtUtc,
            ),
        ]..sort((a, b) => a.$2.compareTo(b.$2)),
      );

      final goal = await (target.database.select(
        target.database.goalVersions,
      )..where((v) => v.goalType.equals('workout_daily'))).getSingle();
      expect(goal.enabled, isTrue);
      expect(goal.effectiveFromDate, LocalDate(2026, 9, 1));

      final snapshots = await (target.database.select(
        target.database.dailyGoalSnapshots,
      )..where((s) => s.goalKey.equals('workout_daily'))).get();
      expect(
        snapshots.map((s) => s.localDate).toSet(),
        containsAll(days.map((d) => d)),
      );
      expect(snapshots.every((s) => s.applicable), isTrue);
      expect(snapshots.every((s) => s.moduleId == 'focus'), isTrue);
      expect(snapshots.every((s) => s.targetInteger == 1), isTrue);
    },
  );

  test('(BS-99, AT30) after the import the days read the same: states, ring, streak and XP', () async {
    await importInto(target, await exportOf(source));

    final sourceStatus = source.dayStatusRepository();
    final targetStatus = target.dayStatusRepository();
    for (final day in days) {
      expect(
        await readDay(targetStatus, day),
        await readDay(sourceStatus, day),
        reason: day.toIso(),
      );
    }
    // The concrete states, so the comparison above cannot be equal by being
    // empty: 09-30 open, 10-01 rest, 10-02 skipped, 10-03 a workout.
    expect((await readDay(targetStatus, days[0]))[2], isFalse);
    expect((await readDay(targetStatus, days[1]))[2], isTrue);
    expect((await readDay(targetStatus, days[2]))[2], isTrue);
    expect((await readDay(targetStatus, days[3]))[2], isTrue);

    final sourceStreak = (await sourceStatus.computeStreakSummary())!;
    final targetStreak = (await targetStatus.computeStreakSummary())!;
    expect(targetStreak.current, 3, reason: 'rest, skipped and a workout');
    expect(targetStreak.current, sourceStreak.current);
    expect(targetStreak.longest, sourceStreak.longest);
    expect(targetStreak.activeDays, sourceStreak.activeDays);

    expect(await target.totalXp(), 15, reason: 'only the workout earned XP');
    expect(await target.totalXp(), await source.totalXp());
  });

  test(
    '(BS-99, AT30) export -> import -> export gives the identical file',
    () async {
      final first = await exportOf(source);
      await importInto(target, first);
      final second = await exportOf(target);
      expect(second.bytes, first.bytes);
    },
  );

  test('(BS-99, AT30) an imported mark can be taken back and set again with the commands', () async {
    await importInto(target, await exportOf(source));
    final marks = WorkoutDayMarkRepository(
      database: target.database,
      runner: target.runner,
    );
    final imported = (await marks.findDay(days[1]))!;
    expect(imported.kind, WorkoutDayMarkKind.rest);

    await marks.unmark(commandId: target.ids.newId(), id: imported.id);
    expect(await marks.findDay(days[1]), isNull);
    expect((await readDay(target.dayStatusRepository(), days[1]))[2], isFalse);

    await marks.mark(
      commandId: target.ids.newId(),
      kind: WorkoutDayMarkKind.skipped,
      date: days[1],
    );
    expect((await marks.findDay(days[1]))!.kind, WorkoutDayMarkKind.skipped);
    expect((await readDay(target.dayStatusRepository(), days[1]))[2], isTrue);
  });
}
