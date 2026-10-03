import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/nutrition/application/water_form_controller.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/nutrition_test_kit.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late NutritionKit kit;
  late RecordingProjectionSynchronizer projection;
  late RecordingIdGenerator ids;
  late ProviderContainer container;

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    kit = await NutritionKit.create(projections: projection);
    ids = RecordingIdGenerator(kit.harness.ids);
    container = containerFor(kit, ids: ids, projection: projection);
  });
  tearDown(() => kit.dispose());

  /// The controller; also keeps the (auto-disposed) form alive.
  WaterFormController controller(WaterFormArgs args) {
    container.listen(waterFormProvider(args), (_, _) {});
    return container.read(waterFormProvider(args).notifier);
  }

  WaterFormState formState(WaterFormArgs args) =>
      container.read(waterFormProvider(args));

  const create = WaterFormArgs.create();

  Future<List<WaterEntry>> stored() async =>
      (await container.read(waterRepositoryProvider).loadToday(kitToday))
          .entriesNewestFirst;

  Future<WaterEntry> seedEntry({int ml = 250, DateTime? when}) async {
    final repository = container.read(waterRepositoryProvider);
    final outcome = await repository.create(
      commandId: kit.newId(),
      draft: WaterDraft(amountMl: ml, occurredAtUtc: when ?? at(6)),
    );
    return (await repository.findById(outcome.entityId!))!;
  }

  group('new entry (Eigene Menge)', () {
    test('starts empty with the current time and no errors', () {
      final s = formState(create);
      expect(s.amountText, isEmpty);
      expect(s.note, isEmpty);
      expect(s.dirty, isFalse);
      expect(s.submitting, isFalse);
      expect(s.fieldErrors, isEmpty);
      expect(s.submitFailure, isNull);
      expect(s.date, LocalDate(2026, 10, 3));
      expect(s.time, const LocalTime(10, 0), reason: 'now in Berlin');
    });

    test(
      'an empty field is rejected with a hint and nothing is saved',
      () async {
        final result = await controller(create).submit();
        expect(result, isA<WaterRejected>());
        expect(
          formState(create).fieldErrors[WaterFields.amount],
          'Bitte gib die Menge in Millilitern ein.',
        );
        expect(await stored(), isEmpty);
        expect(await kit.receipts(), isEmpty);
      },
    );

    test('invalid texts give field hints and save nothing', () async {
      const messages = {
        '': 'Bitte gib die Menge in Millilitern ein.',
        'abc':
            'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
        '250,5':
            'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
        '250 ml':
            'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
        '-5': 'Bitte gib eine ganze Zahl in Millilitern ein, zum Beispiel 250.',
        '49': 'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
        '0': 'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
        '2001': 'Bitte gib eine Menge zwischen 50 und 2.000 ml ein.',
      };
      for (final entry in messages.entries) {
        container.invalidate(waterFormProvider(create));
        controller(create).setAmountText(entry.key);
        final result = await controller(create).submit();
        expect(result, isA<WaterRejected>(), reason: '"${entry.key}"');
        expect(
          formState(create).fieldErrors[WaterFields.amount],
          entry.value,
          reason: '"${entry.key}"',
        );
      }
      expect(await stored(), isEmpty);
    });

    test('both sides of the amount bounds: 50 and 2000 are saved', () async {
      for (final text in ['50', '2000']) {
        container.invalidate(waterFormProvider(create));
        controller(create).setAmountText(text);
        kit.harness.clock.advance(const Duration(minutes: 1));
        expect(
          await controller(create).submit(),
          isA<WaterSaved>(),
          reason: text,
        );
      }
      expect((await stored()).map((e) => e.amountMl), [2000, 50]);
    });

    test(
      'saves 250 with "now" as the time and a snackbar message with undo',
      () async {
        controller(create).setAmountText(' 250 ');
        final result = await controller(create).submit();
        expect(result, isA<WaterSaved>());
        final saved = result as WaterSaved;
        expect(saved.message, '250 ml hinzugefügt');
        expect(saved.wasEdit, isFalse);
        expect(saved.amountMl, 250);
        expect(saved.outcome.undo, isNotNull);
        final entry = (await stored()).single;
        expect(entry.amountMl, 250);
        expect(entry.occurredAtUtc, kit.harness.clock.nowUtc());
        expect(entry.note, isNull);
        expect(formState(create).dirty, isFalse);
        expect(formState(create).submitting, isFalse);
      },
    );

    test(
      'the untouched time is the moment of saving, not of opening',
      () async {
        controller(create).setAmountText('250');
        kit.harness.clock.advance(const Duration(minutes: 7));
        await controller(create).submit();
        expect((await stored()).single.occurredAtUtc, at(8, 7));
      },
    );

    test('a note is trimmed, a blank note is saved as none', () async {
      controller(create).setAmountText('250');
      controller(create).setNote('  nach dem Sport  ');
      await controller(create).submit();
      expect((await stored()).single.note, 'nach dem Sport');

      container.invalidate(waterFormProvider(create));
      controller(create).setAmountText('300');
      controller(create).setNote('   ');
      kit.harness.clock.advance(const Duration(minutes: 1));
      await controller(create).submit();
      expect((await stored()).first.note, isNull);
    });

    test('a note of 500 characters is fine, 501 gives a hint', () async {
      controller(create).setAmountText('250');
      controller(create).setNote('x' * 501);
      expect(await controller(create).submit(), isA<WaterRejected>());
      expect(
        formState(create).fieldErrors[WaterFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
      controller(create).setNote('x' * 500);
      expect(formState(create).fieldErrors, isEmpty);
      expect(await controller(create).submit(), isA<WaterSaved>());
    });

    test('all hints appear at once', () async {
      controller(create).setAmountText('abc');
      controller(create).setNote('x' * 501);
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(9, 0));
      expect(await controller(create).submit(), isA<WaterRejected>());
      expect(
        formState(create).fieldErrors.keys,
        unorderedEquals([
          WaterFields.amount,
          WaterFields.note,
          WaterFields.occurredAt,
        ]),
      );
      expect(await stored(), isEmpty);
    });

    test('editing a field clears only its own error', () async {
      controller(create).setAmountText('abc');
      controller(create).setNote('x' * 501);
      await controller(create).submit();
      expect(formState(create).fieldErrors.keys, hasLength(2));
      controller(create).setNote('kurz');
      expect(formState(create).fieldErrors.keys, [
        WaterFields.amount,
      ], reason: 'the amount error stays until the amount changes');
      controller(create).setAmountText('250');
      expect(formState(create).fieldErrors, isEmpty);
    });

    test('the dirty flag follows every kind of user edit', () {
      expect(formState(create).dirty, isFalse);
      controller(create).setAmountText('1');
      expect(formState(create).dirty, isTrue);
      container.invalidate(waterFormProvider(create));
      expect(formState(create).dirty, isFalse);
      controller(create).setNote('x');
      expect(formState(create).dirty, isTrue);
      container.invalidate(waterFormProvider(create));
      controller(create).setDate(LocalDate(2026, 10, 2));
      expect(formState(create).dirty, isTrue);
      container.invalidate(waterFormProvider(create));
      controller(create).setTime(const LocalTime(8, 0));
      expect(formState(create).dirty, isTrue);
    });
  });

  group('time of the drink (device zone)', () {
    test('a future time is rejected and nothing is saved', () async {
      controller(create).setAmountText('250');
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(9, 0));
      expect(await controller(create).submit(), isA<WaterRejected>());
      expect(
        formState(create).fieldErrors[WaterFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
      expect(await stored(), isEmpty);
    });

    test('one minute after now is the future, now itself is fine', () async {
      controller(create).setAmountText('250');
      controller(create).setDate(LocalDate(2026, 10, 3));
      controller(create).setTime(const LocalTime(10, 1));
      expect(await controller(create).submit(), isA<WaterRejected>());
      controller(create).setTime(const LocalTime(10, 0));
      expect(await controller(create).submit(), isA<WaterSaved>());
    });

    test('a date before 2000-01-01 is rejected', () async {
      controller(create).setAmountText('250');
      controller(create).setDate(LocalDate(1999, 12, 31));
      controller(create).setTime(const LocalTime(23, 59));
      expect(await controller(create).submit(), isA<WaterRejected>());
      expect(
        formState(create).fieldErrors[WaterFields.occurredAt],
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
      controller(create).setDate(LocalDate(2000, 1, 1));
      controller(create).setTime(const LocalTime(0, 0));
      expect(await controller(create).submit(), isA<WaterSaved>());
    });

    test(
      'a time in the spring DST gap is explained and offers a valid time',
      () async {
        kit.harness.clock.setNow(DateTime.utc(2026, 4, 1, 12));
        container.invalidate(waterFormProvider(create));
        controller(create).setAmountText('250');
        controller(create).setDate(LocalDate(2026, 3, 29));
        controller(create).setTime(const LocalTime(2, 30));
        expect(await controller(create).submit(), isA<WaterRejected>());
        final message = formState(create).fieldErrors[WaterFields.occurredAt]!;
        expect(message, contains('Zeitumstellung'));
        expect(message, contains('03:00'));
        expect(await stored(), isEmpty);
      },
    );

    test('the repeated autumn hour uses the earlier offset', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 26, 12));
      container.invalidate(waterFormProvider(create));
      controller(create).setAmountText('250');
      controller(create).setDate(LocalDate(2026, 10, 25));
      controller(create).setTime(const LocalTime(2, 30));
      expect(await controller(create).submit(), isA<WaterSaved>());
      final entry =
          (await container
                  .read(waterRepositoryProvider)
                  .loadHistory(today: LocalDate(2026, 10, 26), days: 7))
              .daysNewestFirst
              .single
              .entriesNewestFirst
              .single;
      // 02:30 happens twice; the first one is still summer time (UTC+2).
      expect(entry.occurredAtUtc, DateTime.utc(2026, 10, 25, 0, 30));
      expect(entry.localDate, LocalDate(2026, 10, 25));
    });

    test(
      'a back-dated entry is stored with the chosen wall clock time',
      () async {
        controller(create).setAmountText('300');
        controller(create).setDate(LocalDate(2026, 9, 20));
        controller(create).setTime(const LocalTime(7, 30));
        expect(await controller(create).submit(), isA<WaterSaved>());
        final history = await container
            .read(waterRepositoryProvider)
            .loadHistory(today: kitToday, days: 30);
        final entry = history.daysNewestFirst.single.entriesNewestFirst.single;
        expect(entry.occurredAtUtc, DateTime.utc(2026, 9, 20, 5, 30));
        expect(entry.localDate, LocalDate(2026, 9, 20));
      },
    );

    test('23:30 Berlin and 00:30 Berlin land on different days', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 10, 4, 8));
      container.invalidate(waterFormProvider(create));
      controller(create).setAmountText('100');
      controller(create).setDate(LocalDate(2026, 10, 3));
      controller(create).setTime(const LocalTime(23, 30));
      await controller(create).submit();
      container.invalidate(waterFormProvider(create));
      controller(create).setAmountText('200');
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(0, 30));
      await controller(create).submit();
      final history = await container
          .read(waterRepositoryProvider)
          .loadHistory(today: LocalDate(2026, 10, 4), days: 7);
      expect(history.daysNewestFirst.map((d) => (d.date, d.totalMl)), [
        (LocalDate(2026, 10, 4), 200),
        (LocalDate(2026, 10, 3), 100),
      ]);
    });
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one entry', () async {
      controller(create).setAmountText('250');
      final first = controller(create).submit();
      final second = controller(create).submit();
      final results = await Future.wait([first, second]);
      expect(results.whereType<WaterSaved>(), hasLength(1));
      expect(results.whereType<WaterRejected>(), hasLength(1));
      expect(await stored(), hasLength(1));
      expect(await kit.receipts(), hasLength(1));
    });

    test('while saving, the form reports submitting', () async {
      controller(create).setAmountText('250');
      final future = controller(create).submit();
      expect(formState(create).submitting, isTrue);
      await future;
      expect(formState(create).submitting, isFalse);
    });

    test(
      'a storage failure keeps all input, retrying works and saves once',
      () async {
        controller(create).setAmountText('250');
        controller(create).setNote('Notiz bleibt');
        projection.failure = StateError('disk full');
        final failed = await controller(create).submit();
        expect(failed, isA<WaterRejected>());
        var s = formState(create);
        expect(s.submitFailure, isA<StorageFailure>());
        expect(s.submitting, isFalse);
        expect(s.amountText, '250');
        expect(s.note, 'Notiz bleibt');
        expect(s.fieldErrors, isEmpty);
        expect(await stored(), isEmpty, reason: 'no amount, no record');

        projection.failure = null;
        final saved = await controller(create).submit();
        expect(saved, isA<WaterSaved>());
        s = formState(create);
        expect(s.submitFailure, isNull);
        expect(await stored(), hasLength(1));
        expect((await stored()).single.note, 'Notiz bleibt');
      },
    );

    test('the retry reuses the SAME command id and the same instant', () async {
      controller(create).setAmountText('250');
      projection.failure = StateError('disk full');
      await controller(create).submit();
      // Issued: the command id, then the entry id of the rolled back attempt.
      expect(ids.issued, hasLength(2));
      final commandId = ids.issued.first;
      final firstInstant = kit.harness.clock.nowUtc();

      // Time passes between the attempts; the retry must not change the content.
      kit.harness.clock.advance(const Duration(minutes: 3));
      projection.failure = null;
      expect(await controller(create).submit(), isA<WaterSaved>());
      expect(ids.issued, hasLength(3), reason: 'no second command id');
      final receipts = await kit.receipts();
      expect(receipts.single.commandId, commandId);
      expect(
        (await stored()).single.occurredAtUtc,
        firstInstant,
        reason: 'the frozen attempt time is kept for the retry',
      );
    });

    test('changed content after a failure is a NEW command id', () async {
      controller(create).setAmountText('250');
      projection.failure = StateError('disk full');
      await controller(create).submit();
      final firstCommandId = ids.issued.first;
      controller(create).setAmountText('300');
      projection.failure = null;
      await controller(create).submit();
      final receipts = await kit.receipts();
      expect(receipts.single.commandId, isNot(firstCommandId));
      expect((await stored()).single.amountMl, 300);
    });

    test(
      'after success a further save is a new entry with a new command id',
      () async {
        controller(create).setAmountText('250');
        await controller(create).submit();
        kit.harness.clock.advance(const Duration(minutes: 5));
        controller(create).setAmountText('250');
        await controller(create).submit();
        expect(await stored(), hasLength(2));
        final receipts = await kit.receipts();
        expect(receipts.map((r) => r.commandId).toSet(), hasLength(2));
      },
    );

    test('a clock that jumps back between form check and command gives hints, not a crash', () async {
      final stepping = SteppingClock(kit.harness.clock);
      final scripted = containerFor(
        kit,
        ids: ids,
        projection: projection,
        clock: stepping,
      );
      const args = WaterFormArgs.create();
      scripted.listen(waterFormProvider(args), (_, _) {});
      final form = scripted.read(waterFormProvider(args).notifier);
      form.setAmountText('250');

      // The form reads "now" once; the command reads it right after and sees
      // a clock that is one hour earlier.
      stepping
        ..jumpAfterCall = stepping.calls + 1
        ..jump = const Duration(hours: -1);
      expect(await form.submit(), isA<WaterRejected>());
      expect(
        scripted
            .read(waterFormProvider(args))
            .fieldErrors[WaterFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
      expect(scripted.read(waterFormProvider(args)).submitting, isFalse);
      expect(await kit.waterRows(), isEmpty);

      // With the clock right again the same form saves.
      stepping.jumpAfterCall = null;
      expect(await form.submit(), isA<WaterSaved>());
      expect(await kit.waterRows(), hasLength(1));
    });
  });

  group('edit', () {
    test(
      'is prefilled from the entry and saving keeps the exact instant',
      () async {
        final entry = await seedEntry(
          ml: 250,
          when: DateTime.utc(2026, 10, 3, 6, 15, 42, 321),
        );
        final args = WaterFormArgs.edit(entry);
        final s = formState(args);
        expect(s.amountText, '250');
        expect(s.note, isEmpty);
        expect(s.date, LocalDate(2026, 10, 3));
        expect(s.time, const LocalTime(8, 15));
        expect(s.dirty, isFalse);

        controller(args).setAmountText('300');
        final result = await controller(args).submit();
        expect(result, isA<WaterSaved>());
        final saved = result as WaterSaved;
        expect(saved.message, 'Eintrag aktualisiert');
        expect(saved.wasEdit, isTrue);
        expect(saved.outcome.undo, isNotNull);
        final after = (await container
            .read(waterRepositoryProvider)
            .findById(entry.id))!;
        expect(after.amountMl, 300);
        expect(after.occurredAtUtc, DateTime.utc(2026, 10, 3, 6, 15, 42, 321));
        expect(after.rowVersion, 2);
      },
    );

    test('the note of an entry is prefilled and can be cleared', () async {
      final repository = container.read(waterRepositoryProvider);
      final created = await repository.create(
        commandId: kit.newId(),
        draft: WaterDraft(amountMl: 250, occurredAtUtc: at(6), note: 'alt'),
      );
      final entry = (await repository.findById(created.entityId!))!;
      final args = WaterFormArgs.edit(entry);
      expect(formState(args).note, 'alt');
      controller(args).setNote('');
      await controller(args).submit();
      expect((await repository.findById(entry.id))!.note, isNull);
    });

    test('moving the entry past midnight moves it to the other day', () async {
      final entry = await seedEntry(ml: 300, when: at(6));
      final args = WaterFormArgs.edit(entry);
      controller(args).setDate(LocalDate(2026, 10, 2));
      controller(args).setTime(const LocalTime(23, 30));
      expect(await controller(args).submit(), isA<WaterSaved>());
      final history = await container
          .read(waterRepositoryProvider)
          .loadHistory(today: kitToday, days: 7);
      expect(history.daysNewestFirst.single.date, LocalDate(2026, 10, 2));
      expect(projection.syncs.last, {
        LocalDate(2026, 10, 3),
        LocalDate(2026, 10, 2),
      });
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final entry = await seedEntry(ml: 250);
      final args = WaterFormArgs.edit(entry);
      // Another edit happens while the form is open.
      await container
          .read(waterRepositoryProvider)
          .update(
            commandId: 'other',
            id: entry.id,
            draft: WaterDraft(
              amountMl: 400,
              occurredAtUtc: entry.occurredAtUtc,
            ),
            expectedRowVersion: entry.rowVersion,
          );
      controller(args).setAmountText('300');
      expect(await controller(args).submit(), isA<WaterRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(
        s.submitFailure!.userMessage,
        'Der Eintrag wurde inzwischen geändert.',
      );
      expect(s.amountText, '300');
      expect(
        (await container.read(waterRepositoryProvider).findById(entry.id))!
            .amountMl,
        400,
      );
    });

    test(
      'an entry that was deleted meanwhile is reported, input kept',
      () async {
        final entry = await seedEntry(ml: 250);
        final args = WaterFormArgs.edit(entry);
        await container
            .read(waterRepositoryProvider)
            .delete(commandId: kit.newId(), id: entry.id);
        controller(args).setAmountText('300');
        expect(await controller(args).submit(), isA<WaterRejected>());
        final s = formState(args);
        expect(s.submitFailure, isA<NotFoundFailure>());
        expect(
          s.submitFailure!.userMessage,
          'Dieser Eintrag ist nicht mehr vorhanden.',
        );
        expect(s.amountText, '300');
      },
    );

    test(
      'a storage failure on edit keeps input and retries with the same id',
      () async {
        final entry = await seedEntry(ml: 250);
        final args = WaterFormArgs.edit(entry);
        ids.issued.clear();
        controller(args).setAmountText('300');
        projection.failure = StateError('disk full');
        expect(await controller(args).submit(), isA<WaterRejected>());
        expect(formState(args).submitFailure, isA<StorageFailure>());
        final commandId = ids.issued.first;
        projection.failure = null;
        expect(await controller(args).submit(), isA<WaterSaved>());
        final receipts = await kit.receipts();
        expect(receipts.map((r) => r.commandId), contains(commandId));
        expect(
          (await container.read(waterRepositoryProvider).findById(entry.id))!
              .amountMl,
          300,
        );
      },
    );

    test('forms of different entries are independent', () async {
      final a = await seedEntry(ml: 250, when: at(5));
      final b = await seedEntry(ml: 400, when: at(6));
      controller(WaterFormArgs.edit(a)).setAmountText('111');
      expect(formState(WaterFormArgs.edit(b)).amountText, '400');
      expect(formState(WaterFormArgs.edit(b)).dirty, isFalse);
    });
  });
}
