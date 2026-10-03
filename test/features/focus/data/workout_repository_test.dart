import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/data/workout_repository.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late WorkoutRepository repository;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    repository = WorkoutRepository(
      database: harness.database,
      runner: harness.runner,
    );
  });
  tearDown(() => harness.dispose());

  // "now" is 2026-10-03 08:00Z = 10:00 in Berlin.
  DateTime at(int hour, [int minute = 0, int day = 3]) =>
      DateTime.utc(2026, 10, day, hour, minute);

  WorkoutDraft draft({
    TrainingCategory category = TrainingCategory.strength,
    int minutes = 45,
    DateTime? when,
    String? title,
    List<MuscleGroup> groups = const [],
    WorkoutIntensity? intensity,
    String? note,
  }) => WorkoutDraft(
    category: category,
    durationMinutes: minutes,
    occurredAtUtc: when ?? at(7),
    title: title,
    muscleGroups: groups,
    intensity: intensity,
    note: note,
  );

  Future<String> create(WorkoutDraft d, {String? commandId}) async {
    final outcome = await repository.create(
      commandId: commandId ?? harness.ids.newId(),
      draft: d,
    );
    return outcome.entityId!;
  }

  Future<WorkoutEntryRow> rowOf(String id) => (harness.database.select(
    harness.database.workoutEntries,
  )..where((w) => w.id.equals(id))).getSingle();

  Future<List<WorkoutEntry>> all() => repository.watchActive().first;

  Future<List<CommandReceiptRow>> receipts() =>
      harness.database.select(harness.database.commandReceipts).get();

  Matcher conflict(ConflictKind kind) =>
      throwsA(isA<ConflictFailure>().having((f) => f.kind, 'kind', kind));

  group('create (F03)', () {
    test(
      'stores category, duration, time and the frozen business date',
      () async {
        final id = await create(
          draft(
            category: TrainingCategory.cardio,
            minutes: 30,
            title: '  Intervall-Lauf  ',
            groups: [MuscleGroup.legs, MuscleGroup.core],
            intensity: WorkoutIntensity.high,
            note: '  hat Spaß gemacht  ',
          ),
        );
        final entry = (await repository.findById(id))!;
        expect(entry.category, TrainingCategory.cardio);
        expect(entry.durationMinutes, 30);
        expect(entry.title, 'Intervall-Lauf', reason: 'trimmed');
        expect(entry.muscleGroups, [MuscleGroup.legs, MuscleGroup.core]);
        expect(entry.intensity, WorkoutIntensity.high);
        expect(entry.note, 'hat Spaß gemacht');
        expect(entry.occurredAtUtc, at(7));
        expect(entry.localDate, LocalDate(2026, 10, 3));
        expect(entry.timezoneId, 'Europe/Berlin');
        expect(entry.gamificationEligible, isTrue);
        expect(entry.rowVersion, 1);
        expect(entry.displayTitle, 'Intervall-Lauf');
      },
    );

    test('saves no example selections: optional fields stay empty', () async {
      final id = await create(draft());
      final row = await rowOf(id);
      expect(row.title, isNull);
      expect(row.muscleGroups, isEmpty);
      expect(row.intensity, isNull);
      expect(row.note, isNull);
      expect(row.trainingCategory, 'strength');
      expect(row.durationMinutes, 45);
    });

    test(
      'a blank title is stored as none and the category name is displayed',
      () async {
        for (final blank in ['', '   ']) {
          final id = await create(
            draft(
              category: TrainingCategory.mobility,
              title: blank,
              when: at(6),
            ),
          );
          expect((await rowOf(id)).title, isNull, reason: 'blank "$blank"');
          expect((await repository.findById(id))!.displayTitle, 'Mobility');
        }
      },
    );

    test('muscle groups are stored deduplicated in canonical order', () async {
      final id = await create(
        draft(
          groups: [
            MuscleGroup.triceps,
            MuscleGroup.chest,
            MuscleGroup.chest,
            MuscleGroup.back,
            MuscleGroup.triceps,
          ],
        ),
      );
      expect((await rowOf(id)).muscleGroups, ['chest', 'back', 'triceps']);
      expect((await repository.findById(id))!.muscleGroups, [
        MuscleGroup.chest,
        MuscleGroup.back,
        MuscleGroup.triceps,
      ]);
    });

    test('every category, muscle group and intensity round-trips', () async {
      var hour = 0;
      for (final category in TrainingCategory.values) {
        final id = await create(draft(category: category, when: at(hour++)));
        expect((await rowOf(id)).trainingCategory, category.key);
        expect((await repository.findById(id))!.category, category);
      }
      final id = await create(
        draft(groups: MuscleGroup.values, when: at(hour++)),
      );
      expect((await repository.findById(id))!.muscleGroups, MuscleGroup.values);
      for (final intensity in WorkoutIntensity.values) {
        final id = await create(draft(intensity: intensity, when: at(hour++)));
        expect((await repository.findById(id))!.intensity, intensity);
        expect((await rowOf(id)).intensity, intensity.key);
      }
    });

    test(
      'the same workout at the same time twice is allowed (no unique time)',
      () async {
        await create(draft(when: at(7)));
        await create(draft(when: at(7)));
        expect(await all(), hasLength(2));
      },
    );

    test(
      'the business date is frozen in the zone at the time of the event',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
        final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
        );
        harness.clock.setTimeZone('America/New_York');
        expect(
          (await repository.findById(id))!.localDate,
          LocalDate(2026, 10, 4),
          reason: 'travel never moves existing records',
        );
        expect((await repository.findById(id))!.timezoneId, 'Europe/Berlin');
      },
    );

    test(
      'syncs the projection for the affected day inside the command',
      () async {
        await create(draft());
        expect(projection.syncs, [
          {LocalDate(2026, 10, 3)},
        ]);
      },
    );

    test(
      'the same command id is one record, a new id a new record (AT12)',
      () async {
        final first = await repository.create(commandId: 'c1', draft: draft());
        final replay = await repository.create(commandId: 'c1', draft: draft());
        expect(replay.replayed, isTrue);
        expect(replay.entityId, first.entityId);
        expect(await all(), hasLength(1));
        await repository.create(commandId: 'c2', draft: draft());
        expect(await all(), hasLength(2));
      },
    );

    test(
      'eligibility is frozen from the gamification state at creation (AT26)',
      () async {
        final eligibleId = await create(draft(when: at(6)));
        await harness.database
            .into(harness.database.moduleStatusHistory)
            .insert(
              ModuleStatusHistoryCompanion.insert(
                id: 'off',
                moduleId: ModuleId.gamification.key,
                effectiveAtUtc: harness.clock.nowUtc(),
                localDate: LocalDate(2026, 10, 3),
                enabled: false,
              ),
            );
        final notEligibleId = await create(draft(when: at(7)));
        expect(
          (await repository.findById(eligibleId))!.gamificationEligible,
          isTrue,
        );
        expect(
          (await repository.findById(notEligibleId))!.gamificationEligible,
          isFalse,
        );
      },
    );

    test('a workout never touches the focus sessions', () async {
      await create(draft(minutes: 120));
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        isEmpty,
      );
    });
  });

  group('validation (boundaries at the repository)', () {
    Future<ValidationFailure> failure(WorkoutDraft d) async {
      try {
        await create(d);
      } on ValidationFailure catch (error) {
        return error;
      }
      fail('expected a ValidationFailure');
    }

    test(
      'duration: 1 and 600 minutes are valid, 0 and 601 are rejected',
      () async {
        await create(draft(minutes: 1, when: at(1)));
        await create(draft(minutes: 600, when: at(2)));
        for (final bad in [0, 601, -5]) {
          expect(
            (await failure(draft(minutes: bad))).fieldErrors.keys,
            contains(WorkoutFields.duration),
            reason: '$bad',
          );
        }
      },
    );

    test('title: 80 characters are valid, 81 are rejected', () async {
      await create(draft(title: 'x' * 80, when: at(1)));
      expect(
        (await failure(draft(title: 'x' * 81))).fieldErrors.keys,
        contains(WorkoutFields.title),
      );
    });

    test('note: 500 are valid, 501 are rejected', () async {
      await create(draft(note: 'n' * 500, when: at(1)));
      expect(
        (await failure(draft(note: 'n' * 501))).fieldErrors.keys,
        contains(WorkoutFields.note),
      );
    });

    test('time: not in the future', () async {
      await create(draft(when: at(8)));
      final error = await failure(draft(when: at(8, 1)));
      expect(error.fieldErrors[WorkoutFields.occurredAt], contains('Zukunft'));
    });

    test('time: not before 2000-01-01 (Berlin)', () async {
      final error = await failure(
        draft(when: DateTime.utc(1999, 12, 31, 22, 59)),
      );
      expect(
        error.fieldErrors[WorkoutFields.occurredAt],
        contains('01.01.2000'),
      );
      await create(draft(when: DateTime.utc(1999, 12, 31, 23)));
    });

    test(
      'a rejected draft leaves no record, no receipt and no projection call',
      () async {
        await failure(draft(minutes: 0));
        expect(await all(), isEmpty);
        expect(await receipts(), isEmpty);
        expect(projection.syncs, isEmpty);
      },
    );

    test('several errors are reported together', () async {
      final error = await failure(
        draft(minutes: 0, when: at(9), title: 'x' * 81, note: 'n' * 501),
      );
      expect(
        error.fieldErrors.keys,
        containsAll([
          WorkoutFields.duration,
          WorkoutFields.occurredAt,
          WorkoutFields.title,
          WorkoutFields.note,
        ]),
      );
    });
  });

  group('update', () {
    test(
      'changes every field, bumps the version and keeps eligibility',
      () async {
        final id = await create(
          draft(
            title: 'alt',
            groups: [MuscleGroup.chest],
            intensity: WorkoutIntensity.low,
            note: 'alt',
          ),
        );
        final before = (await repository.findById(id))!;
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(
            category: TrainingCategory.sport,
            minutes: 90,
            title: 'neu',
            groups: [MuscleGroup.legs, MuscleGroup.fullBody],
            intensity: WorkoutIntensity.high,
            note: 'neu',
          ),
          expectedRowVersion: before.rowVersion,
        );
        final after = (await repository.findById(id))!;
        expect(after.category, TrainingCategory.sport);
        expect(after.durationMinutes, 90);
        expect(after.title, 'neu');
        expect(after.muscleGroups, [MuscleGroup.legs, MuscleGroup.fullBody]);
        expect(after.intensity, WorkoutIntensity.high);
        expect(after.note, 'neu');
        expect(after.rowVersion, before.rowVersion + 1);
        expect(after.gamificationEligible, before.gamificationEligible);
      },
    );

    test('optional fields can be cleared again', () async {
      final id = await create(
        draft(
          title: 'x',
          groups: [MuscleGroup.core],
          intensity: WorkoutIntensity.moderate,
          note: 'n',
        ),
      );
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(),
        expectedRowVersion: 1,
      );
      final row = await rowOf(id);
      expect(row.title, isNull);
      expect(row.muscleGroups, isEmpty);
      expect(row.intensity, isNull);
      expect(row.note, isNull);
    });

    test(
      'an edit that keeps the time never moves the frozen date or zone',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 3, 22, 45));
        final id = await create(draft(when: DateTime.utc(2026, 10, 3, 22, 30)));
        harness.clock.setTimeZone('America/New_York');
        final before = (await repository.findById(id))!;
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(when: before.occurredAtUtc, note: 'nur Notiz'),
          expectedRowVersion: before.rowVersion,
        );
        final after = (await repository.findById(id))!;
        expect(after.localDate, LocalDate(2026, 10, 4));
        expect(after.timezoneId, 'Europe/Berlin');
      },
    );

    test('moving the time to another day re-freezes the date and syncs both days (AT23)', () async {
      final id = await create(draft(when: at(7)));
      projection.syncs.clear();
      await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(when: at(7, 0, 1)),
        expectedRowVersion: 1,
      );
      expect(
        (await repository.findById(id))!.localDate,
        LocalDate(2026, 10, 1),
      );
      expect(projection.syncs.single, {
        LocalDate(2026, 10, 3),
        LocalDate(2026, 10, 1),
      });
    });

    test('a stale form version is a conflict and changes nothing', () async {
      final id = await create(draft());
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(minutes: 10),
          expectedRowVersion: 99,
        ),
        conflict(ConflictKind.staleVersion),
      );
      expect((await repository.findById(id))!.durationMinutes, 45);
    });

    test('an invalid edit is rejected before anything is written', () async {
      final id = await create(draft());
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(minutes: 601),
          expectedRowVersion: 1,
        ),
        throwsA(isA<ValidationFailure>()),
      );
      expect((await rowOf(id)).rowVersion, 1);
    });

    test('a missing entry is NotFound', () async {
      await expectLater(
        repository.update(
          commandId: harness.ids.newId(),
          id: 'missing',
          draft: draft(),
          expectedRowVersion: 1,
        ),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('delete and undo', () {
    test('delete is soft and the entry disappears from active reads', () async {
      final id = await create(draft());
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      expect(await all(), isEmpty);
      expect(await repository.findById(id), isNull);
      expect((await rowOf(id)).deletedAtUtc, isNotNull);
      expect(outcome.undo, isNotNull);
      expect(projection.syncs.last, {LocalDate(2026, 10, 3)});
    });

    test('undoing a delete restores the SAME id with all fields', () async {
      final id = await create(
        draft(
          title: 'bleibt',
          groups: [MuscleGroup.back, MuscleGroup.biceps],
          intensity: WorkoutIntensity.high,
        ),
      );
      final before = (await repository.findById(id))!;
      final outcome = await repository.delete(
        commandId: harness.ids.newId(),
        id: id,
      );
      await outcome.undo!.run(harness.ids.newId());
      final restored = (await repository.findById(id))!;
      expect(restored.id, id);
      expect(restored.title, before.title);
      expect(restored.muscleGroups, before.muscleGroups);
      expect(restored.intensity, before.intensity);
      expect(restored.durationMinutes, before.durationMinutes);
    });

    test(
      'undoing a delete is refused if the entry changed meanwhile',
      () async {
        final id = await create(draft());
        final outcome = await repository.delete(
          commandId: harness.ids.newId(),
          id: id,
        );
        await (harness.database.update(harness.database.workoutEntries)
              ..where((w) => w.id.equals(id)))
            .write(const WorkoutEntriesCompanion(rowVersion: Value(50)));
        await expectLater(
          outcome.undo!.run(harness.ids.newId()),
          conflict(ConflictKind.staleVersion),
        );
        expect(await repository.findById(id), isNull);
      },
    );

    test(
      'undoing a create removes that entry, after an edit it is refused',
      () async {
        final created = await repository.create(
          commandId: 'u1',
          draft: draft(),
        );
        final id = created.entityId!;
        await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(minutes: 20),
          expectedRowVersion: 1,
        );
        await expectLater(
          created.undo!.run(harness.ids.newId()),
          conflict(ConflictKind.staleVersion),
        );
        expect((await repository.findById(id))!.durationMinutes, 20);

        final second = await repository.create(
          commandId: 'u2',
          draft: draft(when: at(6)),
        );
        await second.undo!.run(harness.ids.newId());
        expect(await all(), hasLength(1));
      },
    );

    test(
      'undoing an update restores the previous values (all fields)',
      () async {
        final id = await create(
          draft(
            category: TrainingCategory.strength,
            minutes: 45,
            title: 'vorher',
            groups: [MuscleGroup.chest],
            intensity: WorkoutIntensity.low,
            note: 'vorher',
            when: at(7),
          ),
        );
        final outcome = await repository.update(
          commandId: harness.ids.newId(),
          id: id,
          draft: draft(
            category: TrainingCategory.cardio,
            minutes: 20,
            title: 'nachher',
            groups: [MuscleGroup.legs],
            intensity: WorkoutIntensity.high,
            note: 'nachher',
            when: at(6),
          ),
          expectedRowVersion: 1,
        );
        await outcome.undo!.run(harness.ids.newId());
        final restored = (await repository.findById(id))!;
        expect(restored.category, TrainingCategory.strength);
        expect(restored.durationMinutes, 45);
        expect(restored.title, 'vorher');
        expect(restored.muscleGroups, [MuscleGroup.chest]);
        expect(restored.intensity, WorkoutIntensity.low);
        expect(restored.note, 'vorher');
        expect(restored.occurredAtUtc, at(7));
      },
    );

    test('undoing a day move re-syncs both days', () async {
      final id = await create(draft(when: at(7)));
      final moved = await repository.update(
        commandId: harness.ids.newId(),
        id: id,
        draft: draft(when: at(7, 0, 1)),
        expectedRowVersion: 1,
      );
      projection.syncs.clear();
      await moved.undo!.run(harness.ids.newId());
      expect(projection.syncs.single, {
        LocalDate(2026, 10, 1),
        LocalDate(2026, 10, 3),
      });
      expect(
        (await repository.findById(id))!.localDate,
        LocalDate(2026, 10, 3),
      );
    });

    test('an undo is itself idempotent', () async {
      final created = await repository.create(commandId: 'u1', draft: draft());
      final first = await created.undo!.run('undo-1');
      final second = await created.undo!.run('undo-1');
      expect(first.replayed, isFalse);
      expect(second.replayed, isTrue);
    });

    test('deleting a deleted entry is NotFound', () async {
      final id = await create(draft());
      await repository.delete(commandId: 'd1', id: id);
      await expectLater(
        repository.delete(commandId: 'd2', id: id),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('atomicity (AT27)', () {
    test('a failing projection stores no workout and no receipt, a retry with the same id works', () async {
      projection.failure = StateError('disk full');
      await expectLater(
        repository.create(commandId: 'fail', draft: draft()),
        throwsA(isA<StorageFailure>()),
      );
      expect(await all(), isEmpty);
      expect(await receipts(), isEmpty);
      projection.failure = null;
      await repository.create(commandId: 'fail', draft: draft());
      expect(await all(), hasLength(1));
    });

    test('a failing update or delete changes nothing', () async {
      final id = await create(draft(minutes: 45));
      projection.failure = StateError('disk full');
      await expectLater(
        repository.update(
          commandId: 'u',
          id: id,
          draft: draft(minutes: 90),
          expectedRowVersion: 1,
        ),
        throwsA(isA<StorageFailure>()),
      );
      await expectLater(
        repository.delete(commandId: 'd', id: id),
        throwsA(isA<StorageFailure>()),
      );
      final row = await rowOf(id);
      expect(row.durationMinutes, 45);
      expect(row.deletedAtUtc, isNull);
      expect(row.rowVersion, 1);
    });
  });

  group('reads', () {
    test('watchActive is newest first and excludes deleted entries', () async {
      final a = await create(draft(when: at(6), minutes: 10));
      await create(draft(when: at(7), minutes: 20));
      final c = await create(draft(when: at(8), minutes: 30));
      await repository.delete(commandId: harness.ids.newId(), id: a);
      final list = await all();
      expect(list.map((e) => e.durationMinutes), [30, 20]);
      expect(list.first.id, c);
    });

    test(
      'entries with the same time are ordered by id, newest id first',
      () async {
        final first = await create(draft(when: at(7)));
        final second = await create(draft(when: at(7)));
        expect((await all()).map((e) => e.id), [second, first]);
      },
    );

    test('the list can be paged lazily', () async {
      final ids = <String>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await create(draft(when: at(i), minutes: 10 + i)));
      }
      final newestFirst = ids.reversed.toList();
      expect(
        (await repository.fetchPage(limit: 2)).map((e) => e.id),
        newestFirst.take(2),
      );
      expect(
        (await repository.fetchPage(limit: 2, offset: 2)).map((e) => e.id),
        newestFirst.skip(2).take(2),
      );
      expect(
        (await repository.fetchPage(limit: 10, offset: 4)).map((e) => e.id),
        newestFirst.skip(4),
      );
      expect(
        (await repository.watchActive(limit: 3).first).map((e) => e.id),
        newestFirst.take(3),
      );
    });

    test(
      'watchBetween includes both boundary days (Sunday and Monday)',
      () async {
        harness.clock.setNow(DateTime.utc(2026, 10, 6, 12));
        // Week of Monday 2026-09-28 to Sunday 2026-10-04.
        final ids = <String, String>{};
        for (final entry in {
          'sun 09-27': DateTime.utc(2026, 9, 27, 10),
          'mon 09-28': DateTime.utc(2026, 9, 28, 10),
          'sun 10-04': DateTime.utc(2026, 10, 4, 10),
          'mon 10-05': DateTime.utc(2026, 10, 5, 10),
        }.entries) {
          ids[entry.key] = await create(draft(when: entry.value));
        }
        final week = await repository
            .watchBetween(LocalDate(2026, 9, 28), LocalDate(2026, 10, 4))
            .first;
        expect(week.map((e) => e.id), [ids['sun 10-04'], ids['mon 09-28']]);
      },
    );

    test('watchById emits null after deletion', () async {
      final id = await create(draft());
      final emissions = <WorkoutEntry?>[];
      final subscription = repository.watchById(id).listen(emissions.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      await repository.delete(commandId: harness.ids.newId(), id: id);
      await Future<void>.delayed(Duration.zero);
      expect(emissions.first, isNotNull);
      expect(emissions.last, isNull);
    });

    test('the data persists as plain database rows', () async {
      await create(
        draft(groups: [MuscleGroup.core], intensity: WorkoutIntensity.low),
      );
      final rows = await harness.database
          .select(harness.database.workoutEntries)
          .get();
      expect(rows.single.muscleGroups, ['core']);
      expect(rows.single.intensity, 'low');
      expect(rows.single.trainingCategory, 'strength');
    });
  });
}
