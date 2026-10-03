import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/application/workout_form_controller.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/features/focus/domain/workout_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late ProviderContainer container;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    container = harness.createContainer();
  });
  tearDown(() => harness.dispose());

  const create = WorkoutFormArgs.create();

  WorkoutFormController controller(WorkoutFormArgs args) =>
      container.read(workoutFormProvider(args).notifier);

  WorkoutFormState formState(WorkoutFormArgs args) =>
      container.read(workoutFormProvider(args));

  Future<List<WorkoutEntry>> entries() =>
      container.read(workoutRepositoryProvider).watchActive().first;

  /// Fills the two required fields.
  void fillRequired(
    WorkoutFormArgs args, {
    TrainingCategory category = TrainingCategory.strength,
    String minutes = '45',
  }) {
    controller(args).selectCategory(category);
    controller(args).setDurationText(minutes);
  }

  Future<WorkoutEntry> seedEntry({
    TrainingCategory category = TrainingCategory.cardio,
    int minutes = 30,
    String? title,
    List<MuscleGroup> groups = const [],
    WorkoutIntensity? intensity,
    String? note,
    DateTime? when,
  }) async {
    final repository = container.read(workoutRepositoryProvider);
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: WorkoutDraft(
        category: category,
        durationMinutes: minutes,
        occurredAtUtc: when ?? DateTime.utc(2026, 10, 3, 6),
        title: title,
        muscleGroups: groups,
        intensity: intensity,
        note: note,
      ),
    );
    return (await repository.findById(outcome.entityId!))!;
  }

  group('a new form', () {
    test('starts EMPTY: no category, duration, muscle group or intensity preselected', () {
      final s = formState(create);
      expect(s.category, isNull);
      expect(s.title, isEmpty);
      expect(s.durationText, isEmpty);
      expect(s.durationMinutes, isNull);
      expect(s.muscleGroups, isEmpty);
      expect(s.intensity, isNull);
      expect(s.note, isEmpty);
      expect(s.dirty, isFalse);
      expect(s.date, LocalDate(2026, 10, 3));
      expect(s.time, const LocalTime(10, 0), reason: 'now in Berlin');
      expect(s.fieldErrors, isEmpty);
      expect(s.submitting, isFalse);
    });

    test('saving the untouched form is rejected and nothing is saved (no example selections)', () async {
      final result = await controller(create).submit();
      expect(result, isA<WorkoutRejected>());
      final errors = formState(create).fieldErrors;
      expect(
        errors[WorkoutFields.category],
        'Bitte wähle eine Trainingskategorie.',
      );
      expect(
        errors[WorkoutFields.duration],
        'Bitte gib die Dauer in Minuten ein.',
      );
      expect(await entries(), isEmpty);
    });

    test(
      'category and duration are enough: nothing else is invented',
      () async {
        fillRequired(
          create,
          category: TrainingCategory.mobility,
          minutes: '20',
        );
        final result = await controller(create).submit();
        expect(result, isA<WorkoutSaved>());
        expect((result as WorkoutSaved).message, 'Training gespeichert');
        expect(result.wasEdit, isFalse);
        expect(result.outcome.undo, isNotNull);
        final entry = (await entries()).single;
        expect(entry.category, TrainingCategory.mobility);
        expect(entry.durationMinutes, 20);
        expect(entry.title, isNull);
        expect(entry.displayTitle, 'Mobility');
        expect(entry.muscleGroups, isEmpty);
        expect(entry.intensity, isNull);
        expect(entry.note, isNull);
        expect(entry.occurredAtUtc, harness.clock.nowUtc(), reason: 'now');
        expect(formState(create).dirty, isFalse);
      },
    );

    test('saves everything the user chose', () async {
      fillRequired(create, category: TrainingCategory.strength, minutes: '60');
      controller(create).setTitle('  Oberkörper A  ');
      controller(create).toggleMuscleGroup(MuscleGroup.chest);
      controller(create).toggleMuscleGroup(MuscleGroup.back);
      controller(create).toggleIntensity(WorkoutIntensity.moderate);
      controller(create).setNote('  gut gelaufen ');
      expect(await controller(create).submit(), isA<WorkoutSaved>());
      final entry = (await entries()).single;
      expect(entry.title, 'Oberkörper A');
      expect(entry.muscleGroups, [MuscleGroup.chest, MuscleGroup.back]);
      expect(entry.intensity, WorkoutIntensity.moderate);
      expect(entry.note, 'gut gelaufen');
      expect(entry.displayTitle, 'Oberkörper A');
    });

    test('the dirty flag follows user edits', () {
      expect(formState(create).dirty, isFalse);
      controller(create).toggleMuscleGroup(MuscleGroup.legs);
      expect(formState(create).dirty, isTrue);
    });
  });

  group('muscle groups and intensity', () {
    test(
      'toggling selects and deselects, the list stays deduplicated and ordered',
      () {
        controller(create).toggleMuscleGroup(MuscleGroup.triceps);
        controller(create).toggleMuscleGroup(MuscleGroup.chest);
        controller(create).toggleMuscleGroup(MuscleGroup.back);
        expect(formState(create).muscleGroups, [
          MuscleGroup.chest,
          MuscleGroup.back,
          MuscleGroup.triceps,
        ]);
        controller(create).toggleMuscleGroup(MuscleGroup.back);
        expect(formState(create).muscleGroups, [
          MuscleGroup.chest,
          MuscleGroup.triceps,
        ]);
        controller(create).toggleMuscleGroup(MuscleGroup.chest);
        controller(create).toggleMuscleGroup(MuscleGroup.triceps);
        expect(formState(create).muscleGroups, isEmpty);
      },
    );

    test('setMuscleGroups removes duplicates', () {
      controller(create).setMuscleGroups([
        MuscleGroup.core,
        MuscleGroup.core,
        MuscleGroup.legs,
        MuscleGroup.core,
      ]);
      expect(formState(create).muscleGroups, [
        MuscleGroup.legs,
        MuscleGroup.core,
      ]);
    });

    test('the stored list never contains duplicates', () async {
      fillRequired(create);
      controller(create)
          .setMuscleGroups([MuscleGroup.biceps, MuscleGroup.biceps]);
      await controller(create).submit();
      expect((await entries()).single.muscleGroups, [MuscleGroup.biceps]);
    });

    test('the intensity is optional: select, switch, tap again to clear', () {
      expect(formState(create).intensity, isNull);
      controller(create).toggleIntensity(WorkoutIntensity.low);
      expect(formState(create).intensity, WorkoutIntensity.low);
      controller(create).toggleIntensity(WorkoutIntensity.high);
      expect(formState(create).intensity, WorkoutIntensity.high);
      controller(create).toggleIntensity(WorkoutIntensity.high);
      expect(formState(create).intensity, isNull);
      controller(create).setIntensity(WorkoutIntensity.moderate);
      controller(create).setIntensity(null);
      expect(formState(create).intensity, isNull);
    });

    test('selecting a category clears its own error only', () async {
      await controller(create).submit();
      expect(formState(create).fieldErrors, hasLength(2));
      controller(create).selectCategory(TrainingCategory.sport);
      expect(
        formState(create).fieldErrors.containsKey(WorkoutFields.category),
        isFalse,
      );
      expect(
        formState(create).fieldErrors.containsKey(WorkoutFields.duration),
        isTrue,
      );
    });
  });

  group('duration', () {
    test('the stepper starts at 30 minutes and moves in 5 minute steps', () {
      controller(create).stepDuration(1);
      expect(formState(create).durationText, '30');
      controller(create).stepDuration(1);
      expect(formState(create).durationText, '35');
      controller(create).stepDuration(-1);
      controller(create).stepDuration(-1);
      controller(create).stepDuration(-1);
      expect(formState(create).durationText, '20');
      expect(formState(create).durationMinutes, 20);
    });

    test('the stepper stays within 1 and 600', () {
      controller(create).setDurationText('3');
      controller(create).stepDuration(-1);
      expect(formState(create).durationText, '1');
      controller(create).setDurationText('598');
      controller(create).stepDuration(1);
      expect(formState(create).durationText, '600');
      controller(create).stepDuration(1);
      expect(formState(create).durationText, '600');
    });

    test('invalid texts give a hint and save nothing', () async {
      const messages = {
        '': 'Bitte gib die Dauer in Minuten ein.',
        'abc': 'Bitte gib eine ganze Zahl ein, zum Beispiel 45.',
        '45,5': 'Bitte gib eine ganze Zahl ein, zum Beispiel 45.',
        '-5': 'Bitte gib eine ganze Zahl ein, zum Beispiel 45.',
        '0': 'Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.',
        '601': 'Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.',
      };
      for (final entry in messages.entries) {
        container.invalidate(workoutFormProvider(create));
        fillRequired(create, minutes: entry.key);
        expect(await controller(create).submit(), isA<WorkoutRejected>());
        expect(
          formState(create).fieldErrors[WorkoutFields.duration],
          entry.value,
          reason: '"${entry.key}"',
        );
      }
      expect(await entries(), isEmpty);
    });

    test('1 and 600 minutes are saved', () async {
      for (final minutes in ['1', '600']) {
        container.invalidate(workoutFormProvider(create));
        harness.clock.advance(const Duration(minutes: 1));
        fillRequired(create, minutes: minutes);
        expect(await controller(create).submit(), isA<WorkoutSaved>());
      }
      expect((await entries()).map((e) => e.durationMinutes), [600, 1]);
    });
  });

  group('title and note limits', () {
    test(
      'a title of 80 characters is saved, 81 are rejected with a hint',
      () async {
        fillRequired(create);
        controller(create).setTitle('t' * 81);
        expect(await controller(create).submit(), isA<WorkoutRejected>());
        expect(
          formState(create).fieldErrors[WorkoutFields.title],
          'Der Titel darf höchstens 80 Zeichen lang sein.',
        );
        expect(formState(create).title, 't' * 81, reason: 'input is kept');
        controller(create).setTitle('t' * 80);
        expect(formState(create).fieldErrors, isEmpty);
        expect(await controller(create).submit(), isA<WorkoutSaved>());
        expect((await entries()).single.title, 't' * 80);
      },
    );

    test('a note of 500 characters is saved, 501 are rejected', () async {
      fillRequired(create);
      controller(create).setNote('n' * 501);
      expect(await controller(create).submit(), isA<WorkoutRejected>());
      expect(
        formState(create).fieldErrors[WorkoutFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
      controller(create).setNote('n' * 500);
      expect(await controller(create).submit(), isA<WorkoutSaved>());
    });

    test('a blank title means the category name is displayed', () async {
      fillRequired(create, category: TrainingCategory.cardio);
      controller(create).setTitle('   ');
      await controller(create).submit();
      final entry = (await entries()).single;
      expect(entry.title, isNull);
      expect(entry.displayTitle, 'Cardio');
    });
  });

  group('workout time', () {
    test('a future time is rejected by the repository rules', () async {
      fillRequired(create);
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(9, 0));
      expect(await controller(create).submit(), isA<WorkoutRejected>());
      expect(
        formState(create).fieldErrors[WorkoutFields.occurredAt],
        contains('Zukunft'),
      );
      expect(await entries(), isEmpty);
    });

    test('a time in the spring DST gap is explained', () async {
      harness.clock.setNow(DateTime.utc(2026, 4, 1, 12));
      container.invalidate(workoutFormProvider(create));
      fillRequired(create);
      controller(create).setDate(LocalDate(2026, 3, 29));
      controller(create).setTime(const LocalTime(2, 30));
      expect(await controller(create).submit(), isA<WorkoutRejected>());
      final message = formState(create).fieldErrors[WorkoutFields.occurredAt]!;
      expect(message, contains('Zeitumstellung'));
      expect(message, contains('03:00'));
      expect(await entries(), isEmpty);
    });

    test(
      'a back-dated workout is stored with the chosen wall clock time',
      () async {
        fillRequired(create);
        controller(create).setDate(LocalDate(2026, 9, 20));
        controller(create).setTime(const LocalTime(7, 30));
        expect(await controller(create).submit(), isA<WorkoutSaved>());
        final entry = (await entries()).single;
        expect(entry.occurredAtUtc, DateTime.utc(2026, 9, 20, 5, 30));
        expect(entry.localDate, LocalDate(2026, 9, 20));
      },
    );

    test('an untouched new form uses "now" at the moment of saving', () async {
      fillRequired(create);
      harness.clock.advance(const Duration(minutes: 17));
      await controller(create).submit();
      expect((await entries()).single.occurredAtUtc, harness.clock.nowUtc());
    });
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one entry', () async {
      fillRequired(create);
      final results = await Future.wait([
        controller(create).submit(),
        controller(create).submit(),
      ]);
      expect(results.whereType<WorkoutSaved>(), hasLength(1));
      expect(await entries(), hasLength(1));
    });

    test(
      'a storage failure keeps the input; retrying works and saves once',
      () async {
        fillRequired(create, minutes: '50');
        controller(create).setTitle('Titel bleibt');
        controller(create).toggleMuscleGroup(MuscleGroup.legs);
        projection.failure = StateError('disk full');
        expect(await controller(create).submit(), isA<WorkoutRejected>());
        final s = formState(create);
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.durationText, '50');
        expect(s.title, 'Titel bleibt');
        expect(s.muscleGroups, [MuscleGroup.legs]);
        expect(await entries(), isEmpty);

        projection.failure = null;
        expect(await controller(create).submit(), isA<WorkoutSaved>());
        expect(formState(create).submitFailure, isNull);
        expect(await entries(), hasLength(1));
      },
    );

    test(
      'after success a further save is a new entry (new command id)',
      () async {
        fillRequired(create);
        await controller(create).submit();
        harness.clock.advance(const Duration(minutes: 5));
        fillRequired(create);
        await controller(create).submit();
        expect(await entries(), hasLength(2));
      },
    );

    test(
      'changed content after a failure is a new request (new command id)',
      () async {
        fillRequired(create, minutes: '30');
        projection.failure = StateError('disk full');
        await controller(create).submit();
        projection.failure = null;
        controller(create).setDurationText('40');
        await controller(create).submit();
        expect((await entries()).single.durationMinutes, 40);
      },
    );
  });

  group('edit', () {
    test('is prefilled from the entry', () async {
      final entry = await seedEntry(
        category: TrainingCategory.strength,
        minutes: 60,
        title: 'Oberkörper',
        groups: [MuscleGroup.chest, MuscleGroup.shoulders],
        intensity: WorkoutIntensity.high,
        note: 'abends',
      );
      final args = WorkoutFormArgs.edit(entry);
      final s = formState(args);
      expect(s.category, TrainingCategory.strength);
      expect(s.title, 'Oberkörper');
      expect(s.durationText, '60');
      expect(s.muscleGroups, [MuscleGroup.chest, MuscleGroup.shoulders]);
      expect(s.intensity, WorkoutIntensity.high);
      expect(s.note, 'abends');
      expect(s.time, const LocalTime(8, 0));
      expect(s.dirty, isFalse);
    });

    test(
      'saving unchanged keeps the exact instant; changes are stored',
      () async {
        final entry = await seedEntry(
          when: DateTime.utc(2026, 10, 3, 6, 15, 42, 321),
        );
        final args = WorkoutFormArgs.edit(entry);
        controller(args).setDurationText('75');
        controller(args).toggleMuscleGroup(MuscleGroup.core);
        final result = await controller(args).submit();
        expect(result, isA<WorkoutSaved>());
        expect((result as WorkoutSaved).message, 'Training aktualisiert');
        expect(result.wasEdit, isTrue);
        final after = (await container
            .read(workoutRepositoryProvider)
            .findById(entry.id))!;
        expect(after.durationMinutes, 75);
        expect(after.muscleGroups, [MuscleGroup.core]);
        expect(after.occurredAtUtc, DateTime.utc(2026, 10, 3, 6, 15, 42, 321));
        expect(after.rowVersion, 2);
      },
    );

    test('optional fields can be cleared in the form', () async {
      final entry = await seedEntry(
        title: 'weg',
        groups: [MuscleGroup.legs],
        intensity: WorkoutIntensity.low,
        note: 'weg',
      );
      final args = WorkoutFormArgs.edit(entry);
      controller(args).setTitle('');
      controller(args).setMuscleGroups(const []);
      controller(args).setIntensity(null);
      controller(args).setNote('');
      expect(await controller(args).submit(), isA<WorkoutSaved>());
      final after = (await container
          .read(workoutRepositoryProvider)
          .findById(entry.id))!;
      expect(after.title, isNull);
      expect(after.muscleGroups, isEmpty);
      expect(after.intensity, isNull);
      expect(after.note, isNull);
      expect(after.displayTitle, 'Cardio');
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final entry = await seedEntry(minutes: 30);
      final args = WorkoutFormArgs.edit(entry);
      await container
          .read(workoutRepositoryProvider)
          .update(
            commandId: 'other',
            id: entry.id,
            draft: WorkoutDraft(
              category: entry.category,
              durationMinutes: 99,
              occurredAtUtc: entry.occurredAtUtc,
            ),
            expectedRowVersion: entry.rowVersion,
          );
      controller(args).setDurationText('40');
      expect(await controller(args).submit(), isA<WorkoutRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(s.durationText, '40');
      expect(
        (await container.read(workoutRepositoryProvider).findById(entry.id))!
            .durationMinutes,
        99,
      );
    });
  });

  test('form arguments are equal for the same entry version', () async {
    final entry = await seedEntry();
    expect(WorkoutFormArgs.edit(entry), WorkoutFormArgs.edit(entry));
    expect(
      WorkoutFormArgs.edit(entry).hashCode,
      WorkoutFormArgs.edit(entry).hashCode,
    );
    expect(WorkoutFormArgs.edit(entry), isNot(const WorkoutFormArgs.create()));
  });
}
