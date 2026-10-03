import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/body/application/weight_form_controller.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
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
    // Keep the entries stream alive so controllers can read the suggestion.
    container.listen(weightEntriesProvider, (_, _) {});
    await container.read(weightEntriesProvider.future);
  });
  tearDown(() => harness.dispose());

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await container.read(weightEntriesProvider.future);
  }

  WeightFormController controller(WeightFormArgs args) =>
      container.read(weightFormProvider(args).notifier);

  WeightFormState formState(WeightFormArgs args) =>
      container.read(weightFormProvider(args));

  const create = WeightFormArgs.create();

  Future<WeightEntry> seedEntry({int grams = 71800, int hour = 6}) async {
    final repository = container.read(weightRepositoryProvider);
    final outcome = await repository.create(
      commandId: harness.ids.newId(),
      draft: WeightDraft(
        weightGrams: grams,
        occurredAtUtc: DateTime.utc(2026, 10, 3, hour),
      ),
    );
    await settle();
    return (await repository.findById(outcome.entityId!))!;
  }

  group('new entry', () {
    test('starts empty without history and without a suggestion', () {
      final s = formState(create);
      expect(s.weightText, isEmpty);
      expect(s.suggestionGrams, isNull);
      expect(s.beforeToilet || s.afterDrinking || s.afterEating, isFalse);
      expect(s.dirty, isFalse);
      expect(s.date, LocalDate(2026, 10, 3));
      expect(s.time, const LocalTime(10, 0), reason: 'now in Berlin');
    });

    test(
      'an empty field is rejected with a hint and nothing is saved',
      () async {
        final result = await controller(create).submit();
        expect(result, isA<WeightRejected>());
        expect(
          formState(create).fieldErrors[WeightFields.weight],
          'Bitte gib dein Gewicht ein.',
        );
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          isEmpty,
        );
      },
    );

    test(
      'the last value is only an unconfirmed suggestion (AT: Vorschlag)',
      () async {
        await seedEntry(grams: 71800);
        final args = const WeightFormArgs.create();
        expect(formState(args).suggestionGrams, 71800);
        expect(formState(args).weightText, isEmpty, reason: 'never pre-filled');

        // Saving without confirming the suggestion is refused.
        expect(await controller(args).submit(), isA<WeightRejected>());
        controller(args).acceptSuggestion();
        expect(formState(args).weightText, '71,8');
        final result = await controller(args).submit();
        expect(result, isA<WeightSaved>());
      },
    );

    test(
      'plus and minus step by 0,1 kg from the typed value or the suggestion',
      () async {
        await seedEntry(grams: 71800);
        final args = const WeightFormArgs.create();
        controller(args).step(1);
        expect(
          formState(args).weightText,
          '71,9',
          reason: 'from the suggestion',
        );
        controller(args).step(-1);
        controller(args).step(-1);
        expect(formState(args).weightText, '71,7');
        controller(args).setWeightText('71');
        controller(args).step(1);
        expect(formState(args).weightText, '71,1');
      },
    );

    test('stepping without any base does nothing', () {
      controller(create).step(1);
      expect(formState(create).weightText, isEmpty);
      expect(formState(create).dirty, isFalse);
    });

    test(
      'saves 71,5 and 71.5 as 71500 g with "now" as the time (AT05)',
      () async {
        for (final input in ['71,5', '71.5']) {
          harness.clock.advance(const Duration(minutes: 1));
          final args = WeightFormArgs.create();
          controller(args).setWeightText(input);
          final result = await controller(args).submit();
          expect(result, isA<WeightSaved>(), reason: input);
          expect((result as WeightSaved).message, 'Gewicht gespeichert');
          expect(result.wasEdit, isFalse);
          expect(result.outcome.undo, isNotNull);
          container.invalidate(weightFormProvider(args));
        }
        final entries = await container
            .read(weightRepositoryProvider)
            .watchActive()
            .first;
        expect(entries.map((e) => e.weightGrams), [71500, 71500]);
      },
    );

    test('invalid texts give field hints and save nothing (AT05)', () async {
      const messages = {
        '': 'Bitte gib dein Gewicht ein.',
        '71,55':
            'Bitte gib höchstens eine Nachkommastelle an, zum Beispiel 71,5.',
        'NaN': 'Bitte gib eine Zahl ein, zum Beispiel 71,5.',
        '19,9': 'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.',
        '350,1': 'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.',
      };
      for (final entry in messages.entries) {
        container.invalidate(weightFormProvider(create));
        controller(create).setWeightText(entry.key);
        final result = await controller(create).submit();
        expect(result, isA<WeightRejected>(), reason: entry.key);
        expect(
          formState(create).fieldErrors[WeightFields.weight],
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        await container.read(weightRepositoryProvider).watchActive().first,
        isEmpty,
      );
    });

    test('editing a field clears only its own error', () async {
      controller(create).setWeightText('abc');
      await controller(create).submit();
      expect(formState(create).fieldErrors, isNotEmpty);
      controller(create).setNote('x');
      expect(
        formState(create).fieldErrors.containsKey(WeightFields.weight),
        isTrue,
      );
      controller(create).setWeightText('71');
      expect(
        formState(create).fieldErrors.containsKey(WeightFields.weight),
        isFalse,
      );
    });

    test('the dirty flag follows user edits', () {
      expect(formState(create).dirty, isFalse);
      controller(create).setBeforeToilet(true);
      expect(formState(create).dirty, isTrue);
    });
  });

  group('measurement time', () {
    test(
      'a future time is rejected by the repository rules and nothing is saved',
      () async {
        controller(create).setWeightText('71,5');
        controller(create).setDate(LocalDate(2026, 10, 4));
        controller(create).setTime(const LocalTime(9, 0));
        final result = await controller(create).submit();
        expect(result, isA<WeightRejected>());
        expect(
          formState(create).fieldErrors[WeightFields.measuredAt],
          contains('Zukunft'),
        );
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          isEmpty,
        );
      },
    );

    test('a time in the spring DST gap is explained', () async {
      harness.clock.setNow(DateTime.utc(2026, 4, 1, 12));
      container.invalidate(weightFormProvider(create));
      controller(create).setWeightText('71,5');
      controller(create).setDate(LocalDate(2026, 3, 29));
      controller(create).setTime(const LocalTime(2, 30));
      expect(await controller(create).submit(), isA<WeightRejected>());
      final message = formState(create).fieldErrors[WeightFields.measuredAt]!;
      expect(message, contains('Zeitumstellung'));
      expect(message, contains('03:00'));
    });

    test(
      'a back-dated entry is stored with the chosen wall clock time',
      () async {
        controller(create).setWeightText('72');
        controller(create).setDate(LocalDate(2026, 9, 20));
        controller(create).setTime(const LocalTime(7, 30));
        expect(await controller(create).submit(), isA<WeightSaved>());
        final entry =
            (await container.read(weightRepositoryProvider).watchActive().first)
                .single;
        expect(entry.occurredAtUtc, DateTime.utc(2026, 9, 20, 5, 30));
        expect(entry.localDate, LocalDate(2026, 9, 20));
      },
    );
  });

  group('same time (AT07)', () {
    test(
      'a clash is reported with the existing entry to edit, no duplicate',
      () async {
        final existing = await seedEntry(grams: 71800, hour: 6);
        controller(create).setWeightText('72');
        final local = harness.clock.toLocal(existing.occurredAtUtc);
        controller(create).setDate(local.date);
        controller(create).setTime(local.time);
        final result = await controller(create).submit();
        expect(result, isA<WeightRejected>());
        expect(formState(create).duplicateOfId, existing.id);
        expect(formState(create).submitFailure, isA<ConflictFailure>());
        expect(
          formState(create).submitFailure!.userMessage,
          'Für diesen Messzeitpunkt gibt es schon einen Eintrag.',
        );
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          hasLength(1),
        );
        // Input is kept for the user.
        expect(formState(create).weightText, '72');
      },
    );
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one entry', () async {
      controller(create).setWeightText('71,5');
      final first = controller(create).submit();
      final second = controller(create).submit();
      final results = await Future.wait([first, second]);
      expect(results.whereType<WeightSaved>(), hasLength(1));
      expect(
        await container.read(weightRepositoryProvider).watchActive().first,
        hasLength(1),
      );
    });

    test(
      'a storage failure keeps the input; retrying works and saves once',
      () async {
        controller(create).setWeightText('71,5');
        controller(create).setNote('Notiz bleibt');
        projection.failure = StateError('disk full');
        final failed = await controller(create).submit();
        expect(failed, isA<WeightRejected>());
        final s = formState(create);
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.weightText, '71,5');
        expect(s.note, 'Notiz bleibt');
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          isEmpty,
        );

        projection.failure = null;
        final saved = await controller(create).submit();
        expect(saved, isA<WeightSaved>());
        expect(formState(create).submitFailure, isNull);
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          hasLength(1),
        );
      },
    );

    test('a retry of unchanged content keeps the instant of the first attempt, '
        'so it reuses the command id (AT12)', () async {
      final firstAttempt = harness.clock.nowUtc();
      controller(create).setWeightText('71,5');
      projection.failure = StateError('disk full');
      expect(await controller(create).submit(), isA<WeightRejected>());
      harness.clock.advance(const Duration(minutes: 2));
      projection.failure = null;
      expect(await controller(create).submit(), isA<WeightSaved>());
      final entries = await container
          .read(weightRepositoryProvider)
          .watchActive()
          .first;
      expect(entries.single.occurredAtUtc, firstAttempt);
    });

    test(
      'edited content after a failure takes a fresh "now" for the new attempt',
      () async {
        controller(create).setWeightText('71,5');
        projection.failure = StateError('disk full');
        await controller(create).submit();
        harness.clock.advance(const Duration(minutes: 2));
        final later = harness.clock.nowUtc();
        projection.failure = null;
        controller(create).setWeightText('71,6');
        expect(await controller(create).submit(), isA<WeightSaved>());
        final entries = await container
            .read(weightRepositoryProvider)
            .watchActive()
            .first;
        expect(entries.single.occurredAtUtc, later);
      },
    );

    test(
      'after success a further save is a new entry (new command id)',
      () async {
        controller(create).setWeightText('71,5');
        await controller(create).submit();
        harness.clock.advance(const Duration(minutes: 5));
        controller(create).setWeightText('71,5');
        await controller(create).submit();
        expect(
          await container.read(weightRepositoryProvider).watchActive().first,
          hasLength(2),
        );
      },
    );
  });

  group('edit', () {
    test('is prefilled from the entry and saving unchanged keeps the exact instant', () async {
      final repository = container.read(weightRepositoryProvider);
      final created = await repository.create(
        commandId: 'seed',
        draft: WeightDraft(
          weightGrams: 71500,
          // Seconds and milliseconds must survive an untouched edit.
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6, 15, 42, 321),
          afterEating: true,
          note: 'abends',
        ),
      );
      await settle();
      final entry = (await repository.findById(created.entityId!))!;
      final args = WeightFormArgs.edit(entry);
      final s = formState(args);
      expect(s.weightText, '71,5');
      expect(s.afterEating, isTrue);
      expect(s.note, 'abends');
      expect(s.suggestionGrams, isNull, reason: 'no suggestion when editing');
      expect(s.time, const LocalTime(8, 15));

      controller(args).setWeightText('71,2');
      final result = await controller(args).submit();
      expect(result, isA<WeightSaved>());
      expect((result as WeightSaved).message, 'Gewicht aktualisiert');
      expect(result.wasEdit, isTrue);
      final after = (await repository.findById(entry.id))!;
      expect(after.weightGrams, 71200);
      expect(after.occurredAtUtc, DateTime.utc(2026, 10, 3, 6, 15, 42, 321));
      expect(after.rowVersion, 2);
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final entry = await seedEntry(grams: 71800);
      final args = WeightFormArgs.edit(entry);
      // Another edit happens while the form is open.
      await container
          .read(weightRepositoryProvider)
          .update(
            commandId: 'other',
            id: entry.id,
            draft: WeightDraft(
              weightGrams: 70000,
              occurredAtUtc: entry.occurredAtUtc,
            ),
            expectedRowVersion: entry.rowVersion,
          );
      controller(args).setWeightText('71,0');
      expect(await controller(args).submit(), isA<WeightRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(s.weightText, '71,0');
      expect(
        (await container.read(weightRepositoryProvider).findById(entry.id))!
            .weightGrams,
        70000,
      );
    });

    test('deleting soft-deletes; the undo restores the same id', () async {
      final entry = await seedEntry();
      final args = WeightFormArgs.edit(entry);
      final result = await controller(args).deleteEntry();
      expect(result, isA<WeightDeleted>());
      expect((result as WeightDeleted).message, 'Messung gelöscht');
      final repository = container.read(weightRepositoryProvider);
      expect(await repository.findById(entry.id), isNull);

      await result.outcome.undo!.run(harness.ids.newId());
      final restored = (await repository.findById(entry.id))!;
      expect(restored.id, entry.id);
      expect(restored.weightGrams, 71800);
    });

    test('a second delete while one is running is ignored', () async {
      final entry = await seedEntry();
      final args = WeightFormArgs.edit(entry);
      final first = controller(args).deleteEntry();
      final second = controller(args).deleteEntry();
      expect(await second, isA<WeightDeleteBusy>());
      expect(await first, isA<WeightDeleted>());
    });

    test(
      'deleting an entry that is already gone reports the failure',
      () async {
        final entry = await seedEntry();
        final args = WeightFormArgs.edit(entry);
        await container
            .read(weightRepositoryProvider)
            .delete(commandId: 'elsewhere', id: entry.id);
        final result = await controller(args).deleteEntry();
        expect(result, isA<WeightDeleteFailed>());
        expect(formState(args).submitting, isFalse);
        expect(formState(args).submitFailure, isNotNull);
      },
    );

    test('only an existing measurement can be deleted', () {
      expect(() => controller(create).deleteEntry(), throwsStateError);
    });
  });
}
