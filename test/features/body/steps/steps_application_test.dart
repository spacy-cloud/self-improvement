import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/steps/application/steps_form_controller.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ProviderContainer container;
  final today = LocalDate(2026, 10, 3);
  const args = StepsFormArgs();

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    container = harness.createContainer();
    // The form provider is auto-disposed; a screen keeps it alive by watching.
    container.listen(stepsFormProvider(args), (_, _) {});
  });
  tearDown(() => harness.dispose());

  StepsFormController controller() =>
      container.read(stepsFormProvider(args).notifier);
  StepsFormState form() => container.read(stepsFormProvider(args));

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  group('today card and history', () {
    test('today without a record: not recorded, target applies', () async {
      container.listen(stepsTodayProvider, (_, _) {});
      await settle();
      final state = container.read(stepsTodayProvider).requireValue;
      expect(state.recorded, isFalse);
      expect(state.progress.steps, 0);
      expect(state.progress.target, 10000);
      expect(state.progress.fraction, 0);
    });

    test('recording changes the card live; 7.450 of 10.000 is 75 %', () async {
      container.listen(stepsTodayProvider, (_, _) {});
      await settle();
      controller().setStepsText('7450');
      expect(form().stepsText, '7450');
      final saved = await controller().submit();
      expect(saved, isA<StepsSaved>());
      await settle();
      final state = container.read(stepsTodayProvider).requireValue;
      expect(state.recorded, isTrue);
      expect(state.progress.steps, 7450);
      expect(state.progress.percent, 75);
    });

    test(
      'history marks missing days as not recorded and keeps frozen targets',
      () async {
        final repo = container.read(stepsRepositoryProvider);
        await repo.setSteps(commandId: 'a', date: today.addDays(-1), steps: 0);
        await repo.setSteps(
          commandId: 'b',
          date: today.addDays(-3),
          steps: 10000,
        );
        container.listen(stepsHistoryProvider(7), (_, _) {});
        await settle();
        final days = container.read(stepsHistoryProvider(7)).requireValue;
        expect(days, hasLength(7));
        expect(days.first.date, today);
        expect(days.first.recorded, isFalse);
        expect(days.first.steps, isNull);
        expect(days[1].recorded, isTrue, reason: 'a recorded zero is recorded');
        expect(days[1].steps, 0);
        expect(days[3].steps, 10000);
        expect(days[3].progress.reached, isTrue);
        expect(days.every((d) => d.progress.target == 10000), isTrue);
      },
    );
  });

  group('form controller', () {
    test('invalid input shows German hints and saves nothing', () async {
      const cases = {
        '': 'Bitte gib deine Schritte ein.',
        '74,5': 'Bitte gib eine ganze Zahl ein, zum Beispiel 7450.',
        '100001': 'Bitte gib höchstens 100.000 Schritte ein.',
      };
      for (final entry in cases.entries) {
        controller().setStepsText(entry.key);
        expect(await controller().submit(), isA<StepsRejected>());
        expect(form().fieldErrors[StepsFields.steps], entry.value);
      }
      expect(
        await container.read(stepsRepositoryProvider).watchAll().first,
        isEmpty,
      );
    });

    test(
      'the form says it replaces an existing total and saving replaces it',
      () async {
        await container
            .read(stepsRepositoryProvider)
            .setSteps(commandId: 'a', date: today, steps: 7450);
        container.invalidate(stepsFormProvider(args));
        await settle();
        expect(form().existingSteps, 7450);
        expect(form().replacesExisting, isTrue);
        controller().setStepsText('8.000');
        final result = await controller().submit() as StepsSaved;
        expect(result.replaced, isTrue);
        expect(result.message, 'Schritte aktualisiert');
        expect(
          (await container.read(stepsRepositoryProvider).findDay(today))!.steps,
          8000,
        );
      },
    );

    test('changing the date looks up the total of that date', () async {
      await container
          .read(stepsRepositoryProvider)
          .setSteps(commandId: 'a', date: LocalDate(2026, 10, 1), steps: 4000);
      controller().setDate(LocalDate(2026, 10, 1));
      await settle();
      expect(form().existingSteps, 4000);
      controller().setDate(LocalDate(2026, 10, 2));
      await settle();
      expect(form().existingSteps, isNull);
    });

    test('a future date is a field error', () async {
      controller().setStepsText('1000');
      controller().setDate(today.addDays(1));
      expect(await controller().submit(), isA<StepsRejected>());
      expect(form().fieldErrors[StepsFields.date], contains('Zukunft'));
    });

    test(
      'a double tap saves once and a new save after success is a new action',
      () async {
        controller().setStepsText('5000');
        final results = await Future.wait([
          controller().submit(),
          controller().submit(),
        ]);
        expect(results.whereType<StepsSaved>(), hasLength(1));
        controller().setStepsText('6000');
        expect(await controller().submit(), isA<StepsSaved>());
        expect(
          (await container.read(stepsRepositoryProvider).findDay(today))!.steps,
          6000,
        );
      },
    );

    test('dirty follows edits', () {
      expect(form().dirty, isFalse);
      controller().setStepsText('1');
      expect(form().dirty, isTrue);
    });
  });
}
