import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/nutrition/application/meal_form_controller.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';
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
  MealFormController controller(MealFormArgs args) {
    container.listen(mealFormProvider(args), (_, _) {});
    return container.read(mealFormProvider(args).notifier);
  }

  MealFormState formState(MealFormArgs args) =>
      container.read(mealFormProvider(args));

  const create = MealFormArgs.create();

  Future<List<MealEntry>> stored() async =>
      (await container.read(mealRepositoryProvider).watchDay(kitToday).first)
          .entriesNewestFirst;

  Future<MealEntry> seedMeal({
    String name = 'Haferflocken',
    int? kcal,
    DateTime? when,
    String? note,
  }) async {
    final repository = container.read(mealRepositoryProvider);
    final outcome = await repository.create(
      commandId: kit.newId(),
      draft: MealDraft(
        name: name,
        kcal: kcal,
        occurredAtUtc: when ?? at(6),
        note: note,
      ),
    );
    return (await repository.findById(outcome.entityId!))!;
  }

  group('new meal', () {
    test('starts empty with the current time and no errors', () {
      final s = formState(create);
      expect(s.nameText, isEmpty);
      expect(s.kcalText, isEmpty);
      expect(s.note, isEmpty);
      expect(s.dirty, isFalse);
      expect(s.submitting, isFalse);
      expect(s.fieldErrors, isEmpty);
      expect(s.submitFailure, isNull);
      expect(s.date, LocalDate(2026, 10, 3));
      expect(s.time, const LocalTime(10, 0), reason: 'now in Berlin');
    });

    test(
      'an empty name is rejected with a hint and nothing is saved',
      () async {
        final result = await controller(create).submit();
        expect(result, isA<MealRejected>());
        expect(
          formState(create).fieldErrors[MealFields.name],
          'Bitte gib einen Namen ein.',
        );
        controller(create).setName('   ');
        await controller(create).submit();
        expect(
          formState(create).fieldErrors[MealFields.name],
          'Bitte gib einen Namen ein.',
        );
        expect(await stored(), isEmpty);
        expect(await kit.receipts(), isEmpty);
      },
    );

    test(
      'name length: 1 and 80 characters are saved, 81 is rejected',
      () async {
        controller(create).setName('a' * 81);
        expect(await controller(create).submit(), isA<MealRejected>());
        expect(
          formState(create).fieldErrors[MealFields.name],
          'Der Name darf höchstens 80 Zeichen lang sein.',
        );
        controller(create).setName('a' * 80);
        expect(await controller(create).submit(), isA<MealSaved>());
        kit.harness.clock.advance(const Duration(minutes: 1));
        container.invalidate(mealFormProvider(create));
        controller(create).setName('x');
        expect(await controller(create).submit(), isA<MealSaved>());
        expect((await stored()).map((m) => m.name), ['x', 'a' * 80]);
      },
    );

    test('the name is trimmed before it is saved and measured', () async {
      controller(create).setName('  ${'a' * 80}  ');
      expect(await controller(create).submit(), isA<MealSaved>());
      expect((await stored()).single.name, 'a' * 80);
    });
  });

  group('calories are optional (AT14)', () {
    test('an empty calorie field saves "not given", never 0', () async {
      controller(create).setName('Müsli');
      final result = await controller(create).submit();
      expect(result, isA<MealSaved>());
      final meal = (await stored()).single;
      expect(meal.kcal, isNull);
      expect(meal.hasKcal, isFalse);
      final day = await container
          .read(mealRepositoryProvider)
          .watchDay(kitToday)
          .first;
      expect(day.summary.completeness, KcalCompleteness.incomplete);
      expect(day.summary.knownKcal, isNull, reason: 'no invented value');
    });

    test('a blank calorie field is the same as empty', () async {
      controller(create).setName('Müsli');
      controller(create).setKcalText('   ');
      await controller(create).submit();
      expect((await stored()).single.kcal, isNull);
    });

    test('a deliberate 0 is saved as 0', () async {
      controller(create).setName('Wasser mit Zitrone');
      controller(create).setKcalText('0');
      await controller(create).submit();
      final meal = (await stored()).single;
      expect(meal.kcal, 0);
      expect(meal.hasKcal, isTrue);
    });

    test('450 is saved, whitespace and leading zeros are tolerated', () async {
      controller(create).setName('Müsli');
      controller(create).setKcalText(' 0450 ');
      await controller(create).submit();
      expect((await stored()).single.kcal, 450);
    });

    test('5000 is saved, 5001 gives a hint', () async {
      controller(create).setName('Festessen');
      controller(create).setKcalText('5001');
      expect(await controller(create).submit(), isA<MealRejected>());
      expect(
        formState(create).fieldErrors[MealFields.kcal],
        'Bitte gib Kalorien zwischen 0 und 5.000 kcal ein oder lass das Feld leer.',
      );
      controller(create).setKcalText('5000');
      expect(formState(create).fieldErrors, isEmpty);
      expect(await controller(create).submit(), isA<MealSaved>());
      expect((await stored()).single.kcal, 5000);
    });

    test('not a whole number gives a hint that names the way out', () async {
      for (final text in ['abc', '450,5', '450 kcal', '-1', '1.200']) {
        container.invalidate(mealFormProvider(create));
        controller(create).setName('Müsli');
        controller(create).setKcalText(text);
        expect(await controller(create).submit(), isA<MealRejected>());
        expect(
          formState(create).fieldErrors[MealFields.kcal],
          'Bitte gib die Kalorien als ganze Zahl ein, zum Beispiel 450, '
          'oder lass das Feld leer.',
          reason: text,
        );
      }
      expect(await stored(), isEmpty);
    });

    test('no calorie value is derived from the name', () async {
      controller(create).setName('Pizza 1200 kcal');
      await controller(create).submit();
      expect((await stored()).single.kcal, isNull);
    });
  });

  group('submit', () {
    test(
      'saves with "now", a trimmed note and a snackbar message with undo',
      () async {
        controller(create).setName('Müsli');
        controller(create).setKcalText('420');
        controller(create).setNote('  mit Beeren  ');
        final result = await controller(create).submit();
        expect(result, isA<MealSaved>());
        final saved = result as MealSaved;
        expect(saved.message, 'Mahlzeit gespeichert');
        expect(saved.wasEdit, isFalse);
        expect(saved.outcome.undo, isNotNull);
        final meal = (await stored()).single;
        expect(meal.occurredAtUtc, kit.harness.clock.nowUtc());
        expect(meal.note, 'mit Beeren');
        expect(formState(create).dirty, isFalse);
        expect(formState(create).submitting, isFalse);
      },
    );

    test('a blank note is saved as none, 501 characters give a hint', () async {
      controller(create).setName('Müsli');
      controller(create).setNote('   ');
      await controller(create).submit();
      expect((await stored()).single.note, isNull);

      container.invalidate(mealFormProvider(create));
      controller(create).setName('Suppe');
      controller(create).setNote('x' * 501);
      expect(await controller(create).submit(), isA<MealRejected>());
      expect(
        formState(create).fieldErrors[MealFields.note],
        'Die Notiz darf höchstens 500 Zeichen lang sein.',
      );
      controller(create).setNote('x' * 500);
      kit.harness.clock.advance(const Duration(minutes: 1));
      expect(await controller(create).submit(), isA<MealSaved>());
    });

    test('all hints appear at once', () async {
      controller(create).setName('');
      controller(create).setKcalText('abc');
      controller(create).setNote('x' * 501);
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(9, 0));
      expect(await controller(create).submit(), isA<MealRejected>());
      expect(
        formState(create).fieldErrors.keys,
        unorderedEquals([
          MealFields.name,
          MealFields.kcal,
          MealFields.note,
          MealFields.occurredAt,
        ]),
      );
      expect(await stored(), isEmpty);
    });

    test('editing a field clears only its own error', () async {
      controller(create).setName('');
      controller(create).setKcalText('abc');
      await controller(create).submit();
      expect(formState(create).fieldErrors.keys, hasLength(2));
      controller(create).setName('Müsli');
      expect(formState(create).fieldErrors.keys, [MealFields.kcal]);
      controller(create).setKcalText('');
      expect(formState(create).fieldErrors, isEmpty);
    });

    test('the dirty flag follows every kind of user edit', () {
      expect(formState(create).dirty, isFalse);
      controller(create).setName('x');
      expect(formState(create).dirty, isTrue);
      container.invalidate(mealFormProvider(create));
      expect(formState(create).dirty, isFalse);
      controller(create).setKcalText('1');
      expect(formState(create).dirty, isTrue);
      container.invalidate(mealFormProvider(create));
      controller(create).setNote('x');
      expect(formState(create).dirty, isTrue);
      container.invalidate(mealFormProvider(create));
      controller(create).setDate(LocalDate(2026, 10, 2));
      expect(formState(create).dirty, isTrue);
      container.invalidate(mealFormProvider(create));
      controller(create).setTime(const LocalTime(8, 0));
      expect(formState(create).dirty, isTrue);
    });
  });

  group('time of the meal (device zone)', () {
    test('a future time is rejected and nothing is saved', () async {
      controller(create).setName('Müsli');
      controller(create).setDate(LocalDate(2026, 10, 4));
      controller(create).setTime(const LocalTime(9, 0));
      expect(await controller(create).submit(), isA<MealRejected>());
      expect(
        formState(create).fieldErrors[MealFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
      expect(await stored(), isEmpty);
    });

    test('a date before 2000-01-01 is rejected', () async {
      controller(create).setName('Müsli');
      controller(create).setDate(LocalDate(1999, 12, 31));
      controller(create).setTime(const LocalTime(23, 59));
      expect(await controller(create).submit(), isA<MealRejected>());
      expect(
        formState(create).fieldErrors[MealFields.occurredAt],
        'Das Datum darf nicht vor dem 01.01.2000 liegen.',
      );
    });

    test('a time in the spring DST gap is explained', () async {
      kit.harness.clock.setNow(DateTime.utc(2026, 4, 1, 12));
      container.invalidate(mealFormProvider(create));
      controller(create).setName('Nachtmahl');
      controller(create).setDate(LocalDate(2026, 3, 29));
      controller(create).setTime(const LocalTime(2, 30));
      expect(await controller(create).submit(), isA<MealRejected>());
      final message = formState(create).fieldErrors[MealFields.occurredAt]!;
      expect(message, contains('Zeitumstellung'));
      expect(message, contains('03:00'));
    });

    test(
      'a back-dated meal is stored with the chosen wall clock time',
      () async {
        controller(create).setName('Frühstück');
        controller(create).setDate(LocalDate(2026, 9, 20));
        controller(create).setTime(const LocalTime(7, 30));
        expect(await controller(create).submit(), isA<MealSaved>());
        final day = await container
            .read(mealRepositoryProvider)
            .watchDay(LocalDate(2026, 9, 20))
            .first;
        expect(
          day.entriesNewestFirst.single.occurredAtUtc,
          DateTime.utc(2026, 9, 20, 5, 30),
        );
      },
    );
  });

  group('submit safety (AT12, AT27)', () {
    test('a double tap saves exactly one meal', () async {
      controller(create).setName('Müsli');
      final results = await Future.wait([
        controller(create).submit(),
        controller(create).submit(),
      ]);
      expect(results.whereType<MealSaved>(), hasLength(1));
      expect(results.whereType<MealRejected>(), hasLength(1));
      expect(await stored(), hasLength(1));
      expect(await kit.receipts(), hasLength(1));
    });

    test('a storage failure keeps all input, retrying saves once with the SAME command id', () async {
      controller(create).setName('Müsli');
      controller(create).setKcalText('0');
      controller(create).setNote('Notiz bleibt');
      projection.failure = StateError('disk full');
      expect(await controller(create).submit(), isA<MealRejected>());
      var s = formState(create);
      expect(s.submitFailure, isA<StorageFailure>());
      expect(s.submitting, isFalse);
      expect(s.nameText, 'Müsli');
      expect(s.kcalText, '0');
      expect(s.note, 'Notiz bleibt');
      expect(await stored(), isEmpty);
      expect(
        ids.issued,
        hasLength(2),
        reason: 'command id + rolled back meal id',
      );
      final commandId = ids.issued.first;

      // Time passes; the retry keeps the frozen instant and the command id.
      final firstInstant = kit.harness.clock.nowUtc();
      kit.harness.clock.advance(const Duration(minutes: 3));
      projection.failure = null;
      expect(await controller(create).submit(), isA<MealSaved>());
      s = formState(create);
      expect(s.submitFailure, isNull);
      expect(ids.issued, hasLength(3), reason: 'no second command id');
      expect((await kit.receipts()).single.commandId, commandId);
      final meal = (await stored()).single;
      expect(meal.occurredAtUtc, firstInstant);
      expect(meal.kcal, 0);
    });

    test('changed content after a failure is a NEW command id', () async {
      controller(create).setName('Müsli');
      projection.failure = StateError('disk full');
      await controller(create).submit();
      final firstCommandId = ids.issued.first;
      controller(create).setName('Porridge');
      projection.failure = null;
      await controller(create).submit();
      expect((await kit.receipts()).single.commandId, isNot(firstCommandId));
      expect((await stored()).single.name, 'Porridge');
    });

    test('a calorie change from empty to 0 is a different content', () async {
      controller(create).setName('Müsli');
      projection.failure = StateError('disk full');
      await controller(create).submit();
      final firstCommandId = ids.issued.first;
      controller(create).setKcalText('0');
      projection.failure = null;
      await controller(create).submit();
      expect((await kit.receipts()).single.commandId, isNot(firstCommandId));
      expect((await stored()).single.kcal, 0);
    });

    test(
      'after success a further save is a new meal with a new command id',
      () async {
        controller(create).setName('Müsli');
        await controller(create).submit();
        kit.harness.clock.advance(const Duration(minutes: 5));
        controller(create).setName('Müsli');
        await controller(create).submit();
        expect(await stored(), hasLength(2));
        expect(
          (await kit.receipts()).map((r) => r.commandId).toSet(),
          hasLength(2),
        );
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
      const args = MealFormArgs.create();
      scripted.listen(mealFormProvider(args), (_, _) {});
      final form = scripted.read(mealFormProvider(args).notifier);
      form.setName('Müsli');
      stepping
        ..jumpAfterCall = stepping.calls + 1
        ..jump = const Duration(hours: -1);
      expect(await form.submit(), isA<MealRejected>());
      expect(
        scripted
            .read(mealFormProvider(args))
            .fieldErrors[MealFields.occurredAt],
        'Der Zeitpunkt darf nicht in der Zukunft liegen.',
      );
      expect(await kit.mealRows(), isEmpty);
      stepping.jumpAfterCall = null;
      expect(await form.submit(), isA<MealSaved>());
      expect(await kit.mealRows(), hasLength(1));
    });
  });

  group('edit', () {
    test('is prefilled; saving keeps the exact instant', () async {
      final meal = await seedMeal(
        kcal: 400,
        note: 'alt',
        when: DateTime.utc(2026, 10, 3, 6, 15, 42, 321),
      );
      final args = MealFormArgs.edit(meal);
      final s = formState(args);
      expect(s.nameText, 'Haferflocken');
      expect(s.kcalText, '400');
      expect(s.note, 'alt');
      expect(s.date, LocalDate(2026, 10, 3));
      expect(s.time, const LocalTime(8, 15));
      expect(s.dirty, isFalse);

      controller(args).setName('Porridge');
      final result = await controller(args).submit();
      expect(result, isA<MealSaved>());
      final saved = result as MealSaved;
      expect(saved.message, 'Mahlzeit aktualisiert');
      expect(saved.wasEdit, isTrue);
      expect(saved.outcome.undo, isNotNull);
      final after = (await container
          .read(mealRepositoryProvider)
          .findById(meal.id))!;
      expect(after.name, 'Porridge');
      expect(after.kcal, 400);
      expect(after.occurredAtUtc, DateTime.utc(2026, 10, 3, 6, 15, 42, 321));
      expect(after.rowVersion, 2);
    });

    test('a meal without calories is prefilled with an EMPTY field, a deliberate 0 with 0', () async {
      final missing = await seedMeal(when: at(5));
      final zero = await seedMeal(kcal: 0, when: at(6));
      expect(formState(MealFormArgs.edit(missing)).kcalText, isEmpty);
      expect(formState(MealFormArgs.edit(zero)).kcalText, '0');
    });

    test('calories can be removed (empty) or set to 0 on edit', () async {
      final meal = await seedMeal(kcal: 400);
      final args = MealFormArgs.edit(meal);
      controller(args).setKcalText('');
      await controller(args).submit();
      final repository = container.read(mealRepositoryProvider);
      final cleared = (await repository.findById(meal.id))!;
      expect(cleared.kcal, isNull);

      final args2 = MealFormArgs.edit(cleared);
      controller(args2).setKcalText('0');
      await controller(args2).submit();
      expect((await repository.findById(meal.id))!.kcal, 0);
    });

    test('moving the meal past midnight moves it to the other day', () async {
      final meal = await seedMeal(kcal: 300, when: at(6));
      final args = MealFormArgs.edit(meal);
      controller(args).setDate(LocalDate(2026, 10, 2));
      controller(args).setTime(const LocalTime(23, 30));
      expect(await controller(args).submit(), isA<MealSaved>());
      expect(await stored(), isEmpty);
      expect(projection.syncs.last, {
        LocalDate(2026, 10, 3),
        LocalDate(2026, 10, 2),
      });
      final other = await container
          .read(mealRepositoryProvider)
          .watchDay(LocalDate(2026, 10, 2))
          .first;
      expect(other.entriesNewestFirst.single.id, meal.id);
    });

    test('a stale version is a conflict: nothing saved, input kept', () async {
      final meal = await seedMeal();
      final args = MealFormArgs.edit(meal);
      await container
          .read(mealRepositoryProvider)
          .update(
            commandId: 'other',
            id: meal.id,
            draft: MealDraft(name: 'Anders', occurredAtUtc: meal.occurredAtUtc),
            expectedRowVersion: meal.rowVersion,
          );
      controller(args).setName('Porridge');
      expect(await controller(args).submit(), isA<MealRejected>());
      final s = formState(args);
      expect(s.submitFailure, isA<ConflictFailure>());
      expect(
        s.submitFailure!.userMessage,
        'Der Eintrag wurde inzwischen geändert.',
      );
      expect(s.nameText, 'Porridge');
      expect(
        (await container.read(mealRepositoryProvider).findById(meal.id))!.name,
        'Anders',
      );
    });

    test('a meal that was deleted meanwhile is reported, input kept', () async {
      final meal = await seedMeal();
      final args = MealFormArgs.edit(meal);
      await container
          .read(mealRepositoryProvider)
          .delete(commandId: kit.newId(), id: meal.id);
      controller(args).setName('Porridge');
      expect(await controller(args).submit(), isA<MealRejected>());
      expect(formState(args).submitFailure, isA<NotFoundFailure>());
      expect(formState(args).nameText, 'Porridge');
    });
  });
}
