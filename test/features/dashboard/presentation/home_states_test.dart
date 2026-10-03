import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/home_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// A day after the profile start: no welcome, the real dashboard.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

Finder _streakPill() => find.bySemanticsLabel(RegExp('^Streak: '));

void main() {
  group('loading and error', () {
    testWidgets(
      'loading shows nothing at first and a neutral line only when slow (Q03)',
      (tester) async {
        await pumpApp(
          tester,
          const HomeScreen(),
          overrides: [
            dashboardViewProvider.overrideWithValue(
              const AsyncLoading<DashboardView>(),
            ),
          ],
        );
        expect(find.text('Daten werden geladen …'), findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Daten werden geladen …'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Mein Dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'a failed read shows the error state and "Erneut versuchen" loads the '
      'dashboard (AT27)',
      (tester) async {
        final harness = await createHarness(tester, startedOn: _secondDay);
        var reads = 0;
        await pumpHome(
          tester,
          harness,
          overrides: [
            dashboardCardsProvider.overrideWith((ref) {
              reads++;
              if (reads == 1) {
                return Stream<List<DashboardCardConfig>>.error(
                  StateError('read failed'),
                );
              }
              return ref.watch(dashboardCardRepositoryProvider).watchCards();
            }),
          ],
        );
        expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
        expect(find.text('Dein Tag im Überblick'), findsNothing);

        await tester.tap(find.text('Erneut versuchen'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runCommand(() async {});
        expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
        expect(find.text('Dein Tag im Überblick'), findsOneWidget);
        expect(reads, 2);
      },
    );
  });

  group('first day', () {
    testWidgets(
      'a fresh installation shows the welcome and no invented values (AT01, '
      'C01)',
      (tester) async {
        final harness = await createHarness(tester, displayName: 'Max');
        await pumpHome(tester, harness, realWeightCard: true);
        final semantics = tester.ensureSemantics();

        expect(find.text('Mein Dashboard'), findsOneWidget);
        expect(find.text('Willkommen, Max!'), findsOneWidget);
        expect(find.text('Ersten Eintrag hinzufügen'), findsOneWidget);
        expect(find.text('Schnell starten'), findsOneWidget);
        expect(find.text('Gewicht eintragen'), findsOneWidget);
        expect(find.text('Wasser eintragen'), findsOneWidget);
        expect(find.text('Erstes Habit anlegen'), findsOneWidget);
        // No ring, no cards, no XP, no streak: nothing was recorded yet.
        expect(find.text('Dein Tag im Überblick'), findsNothing);
        expect(find.textContaining(' kg'), findsNothing);
        expect(find.textContaining('Level'), findsNothing);
        expect(find.textContaining('XP'), findsNothing);
        expect(_streakPill(), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('the welcome greets without a name too', (tester) async {
      final harness = await createHarness(tester);
      await pumpHome(tester, harness);
      expect(find.text('Willkommen!'), findsOneWidget);
    });

    testWidgets('"Ersten Eintrag hinzufügen" opens the first entry (C02)', (
      tester,
    ) async {
      final harness = await createHarness(tester);
      await pumpHome(tester, harness);
      await tester.tap(find.text('Ersten Eintrag hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('Seite /weight/new'), findsOneWidget);
    });

    testWidgets('the starting points open their entry screens (C02)', (
      tester,
    ) async {
      final harness = await createHarness(tester);
      final fixture = await pumpHome(tester, harness);
      await tester.tap(find.text('Wasser eintragen'));
      await tester.pumpAndSettle();
      expect(find.text('Seite /water'), findsOneWidget);
      fixture.router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erstes Habit anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Seite /habits/new'), findsOneWidget);
    });

    testWidgets('only the entries of active modules are offered (C03)', (
      tester,
    ) async {
      final harness = await createHarness(
        tester,
        enabledModules: {'nutrition', 'gamification'},
      );
      await pumpHome(tester, harness);
      expect(find.text('Wasser eintragen'), findsOneWidget);
      expect(find.text('Gewicht eintragen'), findsNothing);
      expect(find.text('Erstes Habit anlegen'), findsNothing);
      await tester.tap(find.text('Ersten Eintrag hinzufügen'));
      await tester.pumpAndSettle();
      expect(find.text('Seite /water'), findsOneWidget);
    });

    testWidgets(
      'without any entry module the welcome leads to the module choice',
      (tester) async {
        final harness = await createHarness(
          tester,
          enabledModules: {'gamification'},
        );
        await pumpHome(tester, harness);
        expect(find.text('Willkommen!'), findsOneWidget);
        expect(find.text('Schnell starten'), findsNothing);
        await tester.tap(find.text('Module auswählen'));
        await tester.pumpAndSettle();
        expect(find.text('Seite /settings/modules'), findsOneWidget);
      },
    );

    testWidgets('the welcome disappears with the first record', (tester) async {
      final harness = await createHarness(tester);
      final fixture = await pumpHome(tester, harness);
      expect(find.text('Willkommen!'), findsOneWidget);
      await tester.runCommand(
        () => fixture.container
            .read(weightRepositoryProvider)
            .create(
              commandId: 'first',
              draft: WeightDraft(
                weightGrams: 71500,
                occurredAtUtc: harness.clock.nowUtc(),
              ),
            ),
      );
      expect(find.text('Willkommen!'), findsNothing);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);
    });
  });

  group('empty day', () {
    testWidgets(
      'a day without records shows honest empty cards, the ring at 0 and the '
      'streak at 0 (AT01, C04)',
      (tester) async {
        final harness = await createHarness(tester, startedOn: _secondDay);
        await pumpHome(tester, harness, realWeightCard: true);
        final semantics = tester.ensureSemantics();

        expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
        expect(find.text('Dein Tag im Überblick'), findsOneWidget);
        expect(find.text('0 von 5'), findsOneWidget);
        expect(
          find.text('Du hast heute noch kein Ziel erreicht.'),
          findsOneWidget,
        );
        expect(find.text('Noch keine Messung'), findsOneWidget);
        expect(find.textContaining(' kg'), findsNothing);
        expect(find.text('Level 1'), findsOneWidget);
        expect(find.text('0 / 100 XP'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Streak: 0 Tage in Folge, öffnen'),
          findsOneWidget,
        );
        expect(find.text('Willkommen!'), findsNothing);
        semantics.dispose();
      },
    );

    testWidgets('the motivation text is one of the five fixed texts', (
      tester,
    ) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(tester, harness);
      // 3 October is day 276 of the year, 276 % 5 == 1.
      expect(find.text('Ein Eintrag nach dem anderen.'), findsOneWidget);
    });
  });

  group('modules', () {
    testWidgets(
      'all modules off shows an understandable empty state (AT04, C03)',
      (tester) async {
        final harness = await createHarness(tester, enabledModules: <String>{});
        await pumpHome(tester, harness);
        final semantics = tester.ensureSemantics();

        expect(find.text('Alle Module sind ausgeschaltet'), findsOneWidget);
        expect(find.text('Module auswählen'), findsOneWidget);
        expect(find.text('Dein Tag im Überblick'), findsNothing);
        expect(find.text('Karten anpassen'), findsNothing);
        expect(_streakPill(), findsNothing);

        await tester.tap(find.text('Module auswählen'));
        await tester.pumpAndSettle();
        expect(find.text('Seite /settings/modules'), findsOneWidget);
        semantics.dispose();
      },
    );

    testWidgets('switching a module off hides its cards and the ring follows, '
        'switching it on restores them with the entries (AT03, C03)', (
      tester,
    ) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness, realWeightCard: true);
      final manager = fixture.container.read(moduleManagerProvider);
      await tester.runCommand(
        () => fixture.container
            .read(weightRepositoryProvider)
            .create(
              commandId: 'w1',
              draft: WeightDraft(
                weightGrams: 71500,
                occurredAtUtc: harness.clock.nowUtc(),
              ),
            ),
      );
      expect(find.text('Schritte'), findsOneWidget);
      expect(find.textContaining('71,5'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);

      await tester.runCommand(
        () => manager.setEnabled(
          commandId: 'off',
          module: ModuleId.body,
          enabled: false,
        ),
      );
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('Gewicht'), findsNothing);
      expect(find.text('Wasser'), findsOneWidget);
      expect(find.text('0 von 3'), findsOneWidget);

      await tester.runCommand(
        () => manager.setEnabled(
          commandId: 'on',
          module: ModuleId.body,
          enabled: true,
        ),
      );
      expect(find.text('Schritte'), findsOneWidget);
      expect(find.textContaining('71,5'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);
    });

    testWidgets('with only one module on only its cards are shown (C03)', (
      tester,
    ) async {
      final harness = await createHarness(
        tester,
        startedOn: _secondDay,
        enabledModules: {'focus'},
      );
      await pumpHome(tester, harness);
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Fokus'), findsOneWidget);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('Aufgaben'), findsNothing);
      expect(find.text('Level 1'), findsNothing);
      expect(find.text('0 von 1'), findsOneWidget);
    });

    testWidgets(
      'without an applicable goal the ring gives way to "Ziele festlegen" '
      '(never a 0 of 0 ring)',
      (tester) async {
        final harness = await createHarness(
          tester,
          startedOn: _secondDay,
          enabledModules: {'gamification'},
        );
        await pumpHome(tester, harness);
        expect(find.text('Noch keine Tagesziele'), findsOneWidget);
        expect(find.textContaining('0 von 0'), findsNothing);
        await tester.tap(find.text('Ziele festlegen'));
        await tester.pumpAndSettle();
        expect(find.text('Seite /goals'), findsOneWidget);
      },
    );

    testWidgets(
      'with the gamification module off the ring and the streak keep working '
      'and nothing of XP is shown; switching it on does not back-credit '
      '(AT26, C03)',
      (tester) async {
        final harness = await createHarness(
          tester,
          startedOn: _secondDay,
          enabledModules: {'body', 'nutrition', 'focus', 'tasks'},
        );
        final fixture = await pumpHome(tester, harness);
        final semantics = tester.ensureSemantics();
        // Nobody on screen reads the streak while the module is off.
        fixture.container.listen(streakProvider, (_, _) {});
        await tester.runCommand(
          () => fixture.container
              .read(weightRepositoryProvider)
              .create(
                commandId: 'w1',
                draft: WeightDraft(
                  weightGrams: 71500,
                  occurredAtUtc: harness.clock.nowUtc(),
                ),
              ),
        );

        expect(find.text('1 von 5'), findsOneWidget);
        expect(find.textContaining('XP'), findsNothing);
        expect(_streakPill(), findsNothing);
        expect(fixture.container.read(streakProvider).value?.current, 1);
        expect(await tester.runAsync(harness.totalXp), 0);

        await tester.runCommand(
          () => fixture.container
              .read(moduleManagerProvider)
              .setEnabled(
                commandId: 'on',
                module: ModuleId.gamification,
                enabled: true,
              ),
        );
        await settle(tester);
        expect(find.text('0 / 100 XP'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Streak: 1 Tag in Folge, öffnen'),
          findsOneWidget,
        );
        expect(await tester.runAsync(harness.totalXp), 0);
        semantics.dispose();
      },
    );
  });

  group('cards', () {
    testWidgets(
      'hiding every card shows the way to the card configuration (C03)',
      (tester) async {
        final harness = await createHarness(tester, startedOn: _secondDay);
        final fixture = await pumpHome(tester, harness);
        final repository = fixture.container.read(
          dashboardCardRepositoryProvider,
        );
        var count = 0;
        for (final card
            in await tester.runAsync(repository.cards) ??
                const <DashboardCardConfig>[]) {
          await tester.runCommand(
            () => repository.setVisible(
              commandId: 'hide-${count++}',
              cardId: card.cardId,
              visible: false,
            ),
          );
        }
        expect(find.text('Alle Karten sind ausgeblendet'), findsOneWidget);
        expect(find.text('Wasser'), findsNothing);
        // The ring does not depend on the cards.
        expect(find.text('0 von 5'), findsOneWidget);

        await tester.tap(find.text('Karten anpassen'));
        await tester.pumpAndSettle();
        expect(find.text('Ausgeblendet'), findsNWidgets(8));
      },
    );

    testWidgets('the cards follow the stored order and visibility (C04)', (
      tester,
    ) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness);
      final repository = fixture.container.read(
        dashboardCardRepositoryProvider,
      );
      await tester.runCommand(
        () => repository.move(commandId: 'm1', cardId: 'tasks', toIndex: 0),
      );
      await tester.runCommand(
        () => repository.setVisible(
          commandId: 'v1',
          cardId: 'focus',
          visible: false,
        ),
      );
      Offset at(String title) => tester.getTopLeft(find.text(title));
      bool before(String a, String b) =>
          at(a).dy < at(b).dy || (at(a).dy == at(b).dy && at(a).dx < at(b).dx);
      expect(find.text('Fokus'), findsNothing);
      expect(before('Aufgaben', 'Schritte'), isTrue);
      expect(before('Schritte', 'Wasser'), isTrue);
      expect(before('Wasser', 'Workout'), isTrue);
      expect(before('Workout', 'Ernährung'), isTrue);
    });

    testWidgets(
      'small cards share a row and a full width card keeps the order (C04)',
      (tester) async {
        final harness = await createHarness(tester, startedOn: _secondDay);
        await pumpHome(tester, harness);
        Offset at(String title) => tester.getTopLeft(find.text(title));
        // Schritte and Wasser share a row, Aufgaben (full width) comes after
        // Fokus in its own row, Ernährung follows below.
        expect(at('Schritte').dy, at('Wasser').dy);
        expect(at('Schritte').dx, lessThan(at('Wasser').dx));
        expect(at('Aufgaben').dy, greaterThan(at('Fokus').dy));
        expect(at('Ernährung').dy, greaterThan(at('Aufgaben').dy));
      },
    );

    testWidgets('the quick action of a card does not open its detail (AT10)', (
      tester,
    ) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness);
      await tester.tap(find.text('+250 ml'));
      await tester.pump();
      expect(fixture.log.entries, ['quick:water']);
      await tester.tap(find.text('Wasser'));
      await tester.pump();
      expect(fixture.log.entries, ['quick:water', 'open:water']);
    });
  });

  group('navigation', () {
    testWidgets('the streak pill and the XP card open their pages (C02)', (
      tester,
    ) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await tester.tap(
        find.bySemanticsLabel('Streak: 0 Tage in Folge, öffnen'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Deine Streak'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Zurück'));
      await tester.pumpAndSettle();
      expect(find.text('Mein Dashboard'), findsOneWidget);

      await tester.ensureVisible(find.text('XP und Level'));
      await tester.pump();
      await tester.tap(find.text('XP und Level'));
      await tester.pumpAndSettle();
      expect(find.text('Dein Fortschritt'), findsOneWidget);
      semantics.dispose();
    });
  });
}
