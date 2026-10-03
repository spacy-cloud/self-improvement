import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_screen.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';

/// End-to-end acceptance of the analysis tab: real in-memory database, real
/// commands (steps, weight, meals, workouts, water, modules), the real
/// analysis provider and the real screen. The clock is 2026-10-03 10:00
/// Europe/Berlin, the profile starts on 2026-09-01 so that every compared
/// period lies inside the usage window.

class _Env {
  _Env(this.harness, this.container);

  final DataHarness harness;
  final ProviderContainer container;

  String get id => harness.ids.newId();
}

Future<_Env> _env(
  WidgetTester tester, {
  Set<String>? modules,
  LocalDate? startedOn,
}) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final harness = (await tester.runAsync(
    () => DataHarness.create(realProjection: true),
  ))!;
  addTearDown(() async {
    await tester.runAsync(harness.dispose);
  });
  await tester.runAsync(
    () => harness.seedOnboarded(
      enabledModules: modules,
      startedOn: startedOn ?? LocalDate(2026, 9, 1),
    ),
  );
  return _Env(harness, harness.createContainer());
}

Future<void> _open(WidgetTester tester, _Env env) => pumpApp(
  tester,
  const AnalysisScreen(),
  container: env.container,
  size: const Size(393, 4800),
);

String t(String text) => text.replaceAll('~', ' ');

Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(AppCard)).first;

Finder _inCard(String title, Finder inner) =>
    find.descendant(of: _card(title), matching: inner);

Future<void> _setSteps(
  WidgetTester tester,
  _Env env,
  LocalDate date,
  int steps,
) => tester.runCommand(
  () => env.container
      .read(stepsRepositoryProvider)
      .setSteps(commandId: env.id, date: date, steps: steps),
);

Future<void> _weigh(WidgetTester tester, _Env env, String atUtc, int grams) =>
    tester.runCommand(
      () => env.container
          .read(weightRepositoryProvider)
          .create(
            commandId: env.id,
            draft: WeightDraft(
              weightGrams: grams,
              occurredAtUtc: DateTime.parse(atUtc).toUtc(),
            ),
          ),
    );

Future<void> _eat(WidgetTester tester, _Env env, String atUtc, {int? kcal}) =>
    tester.runCommand(
      () => env.container
          .read(mealRepositoryProvider)
          .create(
            commandId: env.id,
            draft: MealDraft(
              name: 'Mahlzeit',
              occurredAtUtc: DateTime.parse(atUtc).toUtc(),
              kcal: kcal,
            ),
          ),
    );

void main() {
  group('acceptance on real data (A01)', () {
    testWidgets(
      'steps 7.450, then 8.000: the day is 8.000, not 15.450 (AT15)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env);
        // A fresh start: honestly empty, no number.
        expect(find.text('Noch keine Daten'), findsOneWidget);
        expect(find.text('Schritte'), findsNothing);

        await _setSteps(tester, env, LocalDate(2026, 10, 3), 7450);
        expect(_inCard('Schritte', find.text('7.450')), findsNWidgets(2));

        await _setSteps(tester, env, LocalDate(2026, 10, 3), 8000);
        expect(_inCard('Schritte', find.text('8.000')), findsNWidgets(2));
        expect(find.text('15.450'), findsNothing);
        expect(find.text('7.450'), findsNothing);
        expect(
          _inCard('Schritte', find.text('1/7 Tage erfasst')),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'weight with none, one and several points: empty, marker, real change (AT08)',
      (tester) async {
        final env = await _env(tester);
        await _setSteps(tester, env, LocalDate(2026, 10, 3), 5000);
        await _open(tester, env);

        // Nothing measured: honest empty card, no chart for the weight.
        expect(
          _inCard('Gewicht', find.text('Noch keine Daten')),
          findsOneWidget,
        );
        expect(find.text('Gewicht, letzter Wert des Tages'), findsNothing);

        // One point: the value and no change yet.
        await _weigh(tester, env, '2026-10-03T06:00:00Z', 71500);
        expect(_inCard('Gewicht', find.text(t('71,5~kg'))), findsOneWidget);
        expect(
          _inCard(
            'Gewicht',
            find.text('Eine Messung: ${t('71,5~kg')} (03.10.)'),
          ),
          findsOneWidget,
        );
        expect(find.text('Gewicht, letzter Wert des Tages'), findsOneWidget);

        // Several points: first to last day value.
        await _weigh(tester, env, '2026-10-01T06:00:00Z', 71800);
        expect(_inCard('Gewicht', find.text(t('−0,3~kg'))), findsOneWidget);
        expect(
          _inCard(
            'Gewicht',
            find.text(
              'Von ${t('71,8~kg')} (01.10.) auf ${t('71,5~kg')} (03.10.)',
            ),
          ),
          findsOneWidget,
        );
        expect(
          _inCard('Gewicht', find.text('2/7 Tage gemessen')),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'a meal without calories: "Kalorien unvollständig", no invented zero (AT14)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env);

        await _eat(tester, env, '2026-10-03T07:00:00Z');
        expect(
          _inCard('Mahlzeiten', find.text('Kalorien unvollständig')),
          findsOneWidget,
        );
        expect(_inCard('Mahlzeiten', find.text('1')), findsOneWidget);
        expect(find.textContaining('kcal'), findsNothing);

        await _eat(tester, env, '2026-10-03T08:00:00Z', kcal: 500);
        expect(_inCard('Mahlzeiten', find.text(t('500~kcal'))), findsOneWidget);
        expect(
          _inCard('Mahlzeiten', find.text('Kalorien unvollständig')),
          findsOneWidget,
        );
        expect(
          _inCard(
            'Mahlzeiten',
            find.textContaining('1 von 2 Mahlzeiten ohne Kalorienangabe'),
          ),
          findsOneWidget,
        );
        expect(find.text(t('0~kcal')), findsNothing);
      },
    );

    testWidgets(
      'a workout: week count and minutes, and no focus time that was never focused (AT20)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env);
        expect(find.text('Workouts diese Woche'), findsNothing);

        await tester.runCommand(
          () => env.container
              .read(workoutRepositoryProvider)
              .create(
                commandId: env.id,
                draft: WorkoutDraft(
                  category: TrainingCategory.cardio,
                  durationMinutes: 30,
                  occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
                ),
              ),
        );

        expect(
          _inCard('Workouts diese Woche', find.text('1 von 3 Workouts')),
          findsOneWidget,
        );
        expect(
          _inCard('Workouts diese Woche', find.text(t('30~min'))),
          findsOneWidget,
        );
        expect(_inCard('Workouts', find.text('1')), findsOneWidget);
        expect(_inCard('Workouts', find.text(t('30~min'))), findsOneWidget);
        // A workout is no focus time: the card stays empty.
        expect(
          _inCard('Fokuszeit', find.text('Noch keine Daten')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'correcting the past changes the complete days and the strip consistently (AT23)',
      (tester) async {
        // Only the water goal applies (2.500 ml), so a complete day is a day
        // with 2.500 ml.
        final env = await _env(tester, modules: {'nutrition'});
        await _open(tester, env);

        Future<String> drink(int ml, String atUtc) async {
          final outcome = await tester.runCommand(
            () => env.container
                .read(waterRepositoryProvider)
                .create(
                  commandId: env.id,
                  draft: WaterDraft(
                    amountMl: ml,
                    occurredAtUtc: DateTime.parse(atUtc).toUtc(),
                  ),
                ),
          );
          return outcome.entityId!;
        }

        await drink(2000, '2026-10-01T08:00:00Z');
        final second = await drink(500, '2026-10-01T09:00:00Z');
        expect(find.text('1 von 7 Tagen', findRichText: true), findsOneWidget);

        // The past entry is corrected from 500 to 100 ml: 2.100 < 2.500.
        await tester.runCommand(
          () => env.container
              .read(waterRepositoryProvider)
              .update(
                commandId: env.id,
                id: second,
                draft: WaterDraft(
                  amountMl: 100,
                  occurredAtUtc: DateTime.utc(2026, 10, 1, 9),
                ),
                expectedRowVersion: 1,
              ),
        );
        expect(find.text('0 von 7 Tagen', findRichText: true), findsOneWidget);
        expect(find.text('1 von 7 Tagen', findRichText: true), findsNothing);
      },
    );

    testWidgets('the strip names the corrected day in words (AT23, AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await _env(tester, modules: {'nutrition'});
      await _open(tester, env);

      await tester.runCommand(
        () => env.container
            .read(waterRepositoryProvider)
            .create(
              commandId: env.id,
              draft: WaterDraft(
                amountMl: 2000,
                occurredAtUtc: DateTime.utc(2026, 10, 1, 8),
              ),
            ),
      );
      await tester.runCommand(
        () => env.container
            .read(waterRepositoryProvider)
            .create(
              commandId: env.id,
              draft: WaterDraft(
                amountMl: 500,
                occurredAtUtc: DateTime.utc(2026, 10, 1, 9),
              ),
            ),
      );

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Donnerstag, 01\.10\.2026: 1 von 1 Tagesziel erfüllt, Tag '
            r'komplett',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
      'boundary days belong to the right period: first and last day of both periods (A01)',
      (tester) async {
        final env = await _env(tester);
        await _open(tester, env);

        await _setSteps(tester, env, LocalDate(2026, 9, 19), 9999); // outside
        await _setSteps(
          tester,
          env,
          LocalDate(2026, 9, 20),
          3000,
        ); // prev first
        await _setSteps(tester, env, LocalDate(2026, 9, 26), 5000); // prev last
        await _setSteps(
          tester,
          env,
          LocalDate(2026, 9, 27),
          7000,
        ); // curr first

        // Current: 27.09. only; previous: 20.09. and 26.09.
        expect(_inCard('Schritte', find.text('7.000')), findsNWidgets(2));
        expect(
          _inCard(
            'Schritte',
            find.text(t('↑~+75~% (+3.000) gegenüber den vorherigen 7 Tagen')),
          ),
          findsOneWidget,
        );
        expect(find.text('9.999'), findsNothing);

        // 30 days: all four days are in the current period (09-04 .. 10-03).
        env.container
            .read(analysisPeriodProvider.notifier)
            .select(AnalysisPeriodLength.days30);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        // (9999 + 3000 + 5000 + 7000) / 4 recorded days = 6.249,75
        expect(_inCard('Schritte', find.text('6.250')), findsOneWidget);
        expect(
          _inCard('Schritte', find.text('4/30 Tage erfasst')),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'a module that is switched off disappears, switched on again its data is back (AT03)',
      (tester) async {
        final env = await _env(tester);
        await _setSteps(tester, env, LocalDate(2026, 10, 3), 8000);
        await tester.runCommand(
          () => env.container
              .read(waterRepositoryProvider)
              .quickAdd(commandId: env.id, amountMl: 250),
        );
        await _open(tester, env);
        expect(find.text('Schritte'), findsOneWidget);
        expect(find.text('Wasser'), findsOneWidget);

        await tester.runCommand(
          () => env.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: env.id,
                module: ModuleId.body,
                enabled: false,
              ),
        );
        expect(find.text('Schritte'), findsNothing);
        expect(find.text('Gewicht'), findsNothing);
        expect(find.text('Schritte pro Tag'), findsNothing);
        expect(find.text('Wasser'), findsOneWidget);

        await tester.runCommand(
          () => env.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: env.id,
                module: ModuleId.body,
                enabled: true,
              ),
        );
        expect(find.text('Schritte'), findsOneWidget);
        expect(_inCard('Schritte', find.text('8.000')), findsNWidgets(2));
      },
    );

    testWidgets(
      'all modules off: the empty state, one module on again: the analysis is back (AT04)',
      (tester) async {
        final env = await _env(tester);
        await _setSteps(tester, env, LocalDate(2026, 10, 3), 8000);
        await _open(tester, env);

        for (final module in ModuleId.values) {
          await tester.runCommand(
            () => env.container
                .read(moduleManagerProvider)
                .setEnabled(commandId: env.id, module: module, enabled: false),
          );
        }
        expect(find.text('Kein Modul für die Analyse aktiv'), findsOneWidget);
        expect(find.text('Schritte'), findsNothing);

        await tester.runCommand(
          () => env.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: env.id,
                module: ModuleId.body,
                enabled: true,
              ),
        );
        expect(find.text('Kein Modul für die Analyse aktiv'), findsNothing);
        expect(_inCard('Schritte', find.text('8.000')), findsNWidgets(2));
      },
    );

    testWidgets('a new day moves the period and keeps the selection (A01)', (
      tester,
    ) async {
      final env = await _env(tester);
      await _setSteps(tester, env, LocalDate(2026, 10, 3), 8000);
      await _open(tester, env);
      expect(find.text('27.09. bis 03.10.2026, inklusive heute'), findsWidgets);

      env.harness.clock.advance(const Duration(days: 1));
      env.container.read(todayProvider.notifier).refresh();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('28.09. bis 04.10.2026, inklusive heute'), findsWidgets);
      // 8.000 steps of yesterday are still in the period.
      expect(_inCard('Schritte', find.text('8.000')), findsNWidgets(2));
    });
  });
}
