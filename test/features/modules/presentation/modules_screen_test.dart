import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/projection_synchronizer.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';

import '../../../app/support/app_harness.dart';
import '../../../app/support/fake_modules.dart';
import '../../../support/db_fixtures.dart';
import '../../../support/pump_app.dart';

Future<AppFixture> _openManager(
  WidgetTester tester, {
  Set<String>? enabledModules,
  Size size = const Size(393, 852),
  double textScale = 1.0,
  bool fakeModules = false,
  RecordingProjectionSynchronizer? projection,
}) async {
  final app = await pumpFullApp(
    tester,
    enabledModules: enabledModules,
    size: size,
    textScale: textScale,
    modules: fakeModules ? fullFakeModules() : null,
    overrides: [
      if (projection != null)
        projectionSynchronizerProvider.overrideWithValue(
          projection as ProjectionSynchronizer,
        ),
    ],
  );
  unawaited(app.router.push<void>('/settings/modules'));
  await tester.pump();
  await app.settle();
  return app;
}

Finder _toggle(ModuleId module) =>
    find.byKey(ValueKey<String>('module-toggle-${module.key}'));

Finder _cardButton(String label) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.semanticLabel == label,
);

Future<List<String>> _cardOrder(AppFixture app) async {
  final cards = await app.tester.runAsync(
    () => app.container.read(dashboardCardRepositoryProvider).cards(),
  );
  return [for (final card in cards!) card.cardId];
}

Future<Map<ModuleId, bool>> _statuses(AppFixture app) async =>
    (await app.tester.runAsync(app.harness.moduleStatus.statuses))!;

void main() {
  group('module list (BS-58)', () {
    testWidgets('shows the five modules with their copy, all on (AT02)', (
      tester,
    ) async {
      await _openManager(tester);
      expect(find.text('Module'), findsOneWidget);
      expect(
        find.text(
          'Blende Bereiche aus, die du gerade nicht brauchst. '
          'Deine Daten bleiben dabei erhalten.',
        ),
        findsOneWidget,
      );
      for (final copy in <(String, String)>[
        ('Gewicht & Körper', 'Gewicht, Zielgewicht, Schritte'),
        ('Wasser & Ernährung', 'Trinkmenge und Mahlzeiten'),
        ('Fokus & Workouts', 'Fokus-Timer und Trainings'),
        ('Aufgaben & Gewohnheiten', 'To-dos und tägliche Habits'),
        ('Gamification', 'XP, Level und Badges'),
      ]) {
        expect(find.text(copy.$1), findsOneWidget);
        expect(find.text(copy.$2), findsOneWidget);
      }
      for (final module in ModuleId.values) {
        expect(_toggle(module), findsOneWidget);
      }
    });

    testWidgets(
      'switching a module off is stored, says the data is kept and marks the row (AT03)',
      (tester) async {
        final app = await _openManager(tester);
        await tester.tap(_toggle(ModuleId.body));
        await tester.pump();
        await app.settle();
        expect((await _statuses(app))[ModuleId.body], isFalse);
        expect(
          find.text(
            'Gewicht & Körper ausgeschaltet. Deine Daten bleiben erhalten.',
          ),
          findsOneWidget,
        );
        expect(find.text('Aus. Deine Daten bleiben erhalten.'), findsOneWidget);
        expect(find.text('Gewicht, Zielgewicht, Schritte'), findsNothing);
      },
    );

    testWidgets('switching it on again restores the row (AT03)', (
      tester,
    ) async {
      final app = await _openManager(
        tester,
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      expect(find.text('Aus. Deine Daten bleiben erhalten.'), findsOneWidget);
      await tester.tap(_toggle(ModuleId.body));
      await tester.pump();
      await app.settle();
      expect((await _statuses(app))[ModuleId.body], isTrue);
      expect(find.text('Gewicht & Körper eingeschaltet.'), findsOneWidget);
      expect(find.text('Gewicht, Zielgewicht, Schritte'), findsOneWidget);
    });

    testWidgets('the state survives a restart of the app (AT02)', (
      tester,
    ) async {
      final app = await _openManager(tester);
      await tester.tap(_toggle(ModuleId.nutrition));
      await tester.pump();
      await app.settle();
      await tester.pumpWidget(const SizedBox());
      final restarted = await pumpFullApp(tester, reuse: app.harness);
      unawaited(restarted.router.push<void>('/settings/modules'));
      await tester.pump();
      await restarted.settle();
      expect(find.text('Aus. Deine Daten bleiben erhalten.'), findsOneWidget);
      expect((await _statuses(restarted))[ModuleId.nutrition], isFalse);
      expect((await _statuses(restarted))[ModuleId.body], isTrue);
    });

    testWidgets(
      'an open focus session blocks switching focus off and leads to it (AT19)',
      (tester) async {
        final app = await _openManager(tester, fakeModules: true);
        await app.run(
          () => app.harness.database
              .into(app.harness.database.focusSessions)
              .insert(focusRow()),
        );
        await tester.tap(_toggle(ModuleId.focus));
        await tester.pump();
        await app.settle();
        expect(find.text('Ausschalten nicht möglich'), findsOneWidget);
        expect(find.textContaining('Fokus-Sitzung'), findsWidgets);
        expect((await _statuses(app))[ModuleId.focus], isTrue);
        // Abbrechen: nothing changes.
        await tester.tap(find.text('Abbrechen'));
        await tester.pump();
        await app.settle();
        expect((await _statuses(app))[ModuleId.focus], isTrue);
        expect(app.location, '/settings/modules');
        // The resolution action leads to the session.
        await tester.tap(_toggle(ModuleId.focus));
        await tester.pump();
        await app.settle();
        await tester.tap(find.text('Zur Sitzung'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/focus/session');
        final sessions = await tester.runAsync(
          () => app.harness.database
              .select(app.harness.database.focusSessions)
              .get(),
        );
        expect(sessions, hasLength(1));
      },
    );

    testWidgets(
      'a failed save keeps the toggle and the retry saves it (AT27)',
      (tester) async {
        final projection = RecordingProjectionSynchronizer();
        final app = await _openManager(tester, projection: projection);
        projection.failure = StateError('disk full');
        await tester.tap(_toggle(ModuleId.tasks));
        await tester.pump();
        await app.settle();
        expect((await _statuses(app))[ModuleId.tasks], isTrue);
        expect(find.textContaining('Speichern fehlgeschlagen'), findsOneWidget);
        projection.failure = null;
        await tester.tap(find.text('Erneut'));
        await tester.pump();
        await app.settle();
        expect((await _statuses(app))[ModuleId.tasks], isFalse);
        expect(
          find.text(
            'Aufgaben & Gewohnheiten ausgeschaltet. Deine Daten bleiben erhalten.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('every module off (AT04)', () {
    testWidgets('explains the state and offers to switch the modules on', (
      tester,
    ) async {
      final app = await _openManager(tester, enabledModules: <String>{});
      expect(find.text('Alle Module sind ausgeschaltet'), findsOneWidget);
      expect(find.text('Alle Module einschalten'), findsOneWidget);
      expect(
        find.textContaining(
          'Ohne aktive Module gibt es keine Dashboard-Karten',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Alle Module einschalten'));
      await tester.pump();
      await app.settle();
      expect((await _statuses(app)).values.every((on) => on), isTrue);
      expect(find.text('Alle Module sind ausgeschaltet'), findsNothing);
      expect(find.text('Alle Module eingeschaltet.'), findsOneWidget);
    });

    testWidgets('switching off the last module leads into this state', (
      tester,
    ) async {
      final app = await _openManager(
        tester,
        enabledModules: <String>{'gamification'},
      );
      expect(find.text('Alle Module sind ausgeschaltet'), findsNothing);
      await tester.tap(_toggle(ModuleId.gamification));
      await tester.pump();
      await app.settle();
      expect(find.text('Alle Module sind ausgeschaltet'), findsOneWidget);
    });
  });

  group('dashboard card order (BS-58)', () {
    testWidgets(
      'moves cards up and down with buttons and stores the order (AT02)',
      (tester) async {
        final app = await _openManager(tester);
        expect((await _cardOrder(app)).take(3), ['steps', 'water', 'weight']);
        await tester.ensureVisible(_cardButton('Wasser nach oben'));
        await tester.tap(_cardButton('Wasser nach oben'));
        await tester.pump();
        await app.settle();
        expect((await _cardOrder(app)).take(3), ['water', 'steps', 'weight']);
        await tester.ensureVisible(_cardButton('Wasser nach unten'));
        await tester.tap(_cardButton('Wasser nach unten'));
        await tester.pump();
        await app.settle();
        expect((await _cardOrder(app)).take(3), ['steps', 'water', 'weight']);
      },
    );

    testWidgets('the first card cannot move up, the last cannot move down', (
      tester,
    ) async {
      await _openManager(tester);
      expect(
        tester
            .widget<AppIconButton>(_cardButton('Schritte nach oben'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<AppIconButton>(_cardButton('XP und Level nach unten'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<AppIconButton>(_cardButton('Wasser nach oben')).onPressed,
        isNotNull,
      );
    });

    testWidgets('hiding and showing a card is stored (AT02)', (tester) async {
      final app = await _openManager(tester);
      await tester.ensureVisible(_cardButton('Fokus ausblenden'));
      await tester.tap(_cardButton('Fokus ausblenden'));
      await tester.pump();
      await app.settle();
      final cards = await tester.runAsync(
        () => app.container.read(dashboardCardRepositoryProvider).cards(),
      );
      expect(cards!.singleWhere((c) => c.cardId == 'focus').visible, isFalse);
      expect(find.text('Ausgeblendet'), findsOneWidget);
      await tester.ensureVisible(_cardButton('Fokus einblenden'));
      await tester.tap(_cardButton('Fokus einblenden'));
      await tester.pump();
      await app.settle();
      expect(find.text('Ausgeblendet'), findsNothing);
    });

    testWidgets(
      'cards of a switched-off module stay, marked, and return with the module (AT03)',
      (tester) async {
        final app = await _openManager(tester);
        await tester.tap(_toggle(ModuleId.body));
        await tester.pump();
        await app.settle();
        expect(find.text('Modul ausgeschaltet'), findsNWidgets(2));
        // The configuration is still editable (it is kept for the reactivation).
        expect(
          tester
              .widget<AppIconButton>(_cardButton('Gewicht nach oben'))
              .onPressed,
          isNotNull,
        );
        await tester.tap(_toggle(ModuleId.body));
        await tester.pump();
        await app.settle();
        expect(find.text('Modul ausgeschaltet'), findsNothing);
      },
    );

    testWidgets(
      'without a visible card the screen explains it and shows them all again',
      (tester) async {
        final app = await _openManager(tester);
        final repository = app.container.read(dashboardCardRepositoryProvider);
        for (final id in <String>[
          'steps',
          'water',
          'weight',
          'workout',
          'focus',
          'tasks',
          'nutrition',
          'xp',
        ]) {
          await app.run(
            () => repository.setVisible(
              commandId: app.harness.ids.newId(),
              cardId: id,
              visible: false,
            ),
          );
        }
        await app.settle();
        expect(find.text('Alle Karten sind ausgeblendet'), findsOneWidget);
        await tester.tap(find.text('Alle Karten einblenden'));
        await tester.pump();
        await app.settle();
        expect(find.text('Alle Karten sind ausgeblendet'), findsNothing);
        final cards = await tester.runAsync(repository.cards);
        expect(cards!.every((card) => card.visible), isTrue);
      },
    );
  });

  group('accessibility and layout (AT33, AT34, Q02)', () {
    testSemantics('toggles announce their state, every control has a label', (
      tester,
    ) async {
      final app = await _openManager(
        tester,
        enabledModules: <String>{'nutrition', 'focus', 'tasks', 'gamification'},
      );
      final on = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Wasser & Ernährung')),
      );
      final off = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Gewicht & Körper')),
      );
      expect(on.flagsCollection.isToggled, Tristate.isTrue);
      expect(off.flagsCollection.isToggled, Tristate.isFalse);
      expect(off.label, contains('Aus. Deine Daten bleiben erhalten.'));
      expect(find.bySemanticsLabel('Wasser nach oben'), findsOneWidget);
      expect(find.bySemanticsLabel('Wasser ausblenden'), findsOneWidget);
      final firstRow = tester.getSemantics(
        find.descendant(
          of: find.byKey(const ValueKey<String>('card-order-steps')),
          matching: find.text('Schritte'),
        ),
      );
      expect(firstRow.label, 'Schritte, Position 1 von 8, Modul ausgeschaltet');
      expect(app.location, '/settings/modules');
    });

    testWidgets('tap targets and labels meet the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await _openManager(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final size in responsiveSizes) {
      testWidgets(
        '${size.width.toInt()} px at 200 % text: no overflow, every control reachable',
        (tester) async {
          await _openManager(tester, size: size, textScale: 2.0);
          expect(tester.takeException(), isNull);
          for (final label in <String>[
            'Schritte nach unten',
            'XP und Level nach oben',
            'XP und Level ausblenden',
          ]) {
            await tester.ensureVisible(_cardButton(label));
            await tester.pump();
            final box = tester.getSize(_cardButton(label));
            expect(box.height, greaterThanOrEqualTo(48), reason: label);
            expect(box.width, greaterThanOrEqualTo(48), reason: label);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('the back button leaves the screen', (tester) async {
      final app = await _openManager(tester);
      await tester.tap(find.byIcon(AppIcon.back.data));
      await app.settle();
      expect(app.location, '/');
    });
  });
}
