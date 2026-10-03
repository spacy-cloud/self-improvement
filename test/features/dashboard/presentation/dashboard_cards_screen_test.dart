import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/dashboard/application/dashboard_providers.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_cards_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// A day after the profile start: no welcome, the real dashboard.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

const List<String> _defaultOrder = <String>[
  'Schritte',
  'Wasser',
  'Gewicht',
  'Workout',
  'Fokus',
  'Aufgaben',
  'Ernährung',
  'XP und Level',
];

/// The card names on the page, top to bottom (only those that are listed).
List<String> _listed(WidgetTester tester) {
  final found = <(String, double)>[
    for (final title in _defaultOrder)
      if (find.text(title).evaluate().isNotEmpty)
        (title, tester.getTopLeft(find.text(title)).dy),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return [for (final entry in found) entry.$1];
}

Future<void> _open(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Karten anpassen'));
  await tester.pump();
  await tester.tap(find.text('Karten anpassen'));
  await tester.pumpAndSettle();
  await settle(tester);
}

Future<void> _tapSemantic(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(label));
  await settle(tester);
}

void main() {
  testWidgets('lists every card in the stored order, all visible (C04)', (
    tester,
  ) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    await pumpHome(tester, harness);
    await _open(tester);
    expect(find.byType(DashboardCardsScreen), findsOneWidget);
    expect(_listed(tester), _defaultOrder);
    expect(find.text('Sichtbar'), findsNWidgets(8));
    expect(find.text('Ausgeblendet'), findsNothing);
  });

  testWidgets(
    'the switch hides a card: the row says so and the dashboard follows '
    '(C04)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await _open(tester);

      await _tapSemantic(tester, 'Wasser auf dem Dashboard anzeigen');
      expect(find.text('Ausgeblendet'), findsOneWidget);
      expect(find.text('Sichtbar'), findsNWidgets(7));

      await tester.tap(find.byIcon(AppIcon.back.data));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Schritte'), findsOneWidget);

      await _open(tester);
      await _tapSemantic(tester, 'Wasser auf dem Dashboard anzeigen');
      expect(find.text('Ausgeblendet'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'the buttons "nach oben" and "nach unten" move a card (no drag needed, '
    'AT34)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await _open(tester);

      await _tapSemantic(tester, 'Wasser nach oben verschieben');
      expect(_listed(tester).take(3), ['Wasser', 'Schritte', 'Gewicht']);

      await _tapSemantic(tester, 'Schritte nach unten verschieben');
      expect(_listed(tester).take(3), ['Wasser', 'Gewicht', 'Schritte']);
      semantics.dispose();
    },
  );

  testWidgets('the first card cannot move up, the last cannot move down', (
    tester,
  ) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    await pumpHome(tester, harness);
    await _open(tester);
    AppIconButton button(IconData icon, {required bool first}) =>
        tester.widget<AppIconButton>(
          find.widgetWithIcon(AppIconButton, icon).at(first ? 0 : 7),
        );
    expect(button(Icons.arrow_upward_rounded, first: true).onPressed, isNull);
    expect(
      button(Icons.arrow_upward_rounded, first: false).onPressed,
      isNotNull,
    );
    expect(
      button(Icons.arrow_downward_rounded, first: true).onPressed,
      isNotNull,
    );
    expect(
      button(Icons.arrow_downward_rounded, first: false).onPressed,
      isNull,
    );
  });

  testWidgets('dragging the handle moves a card (C04)', (tester) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    await pumpHome(tester, harness);
    await _open(tester);

    final pitch =
        tester.getTopLeft(find.text('Wasser')).dy -
        tester.getTopLeft(find.text('Schritte')).dy;
    final handle = find.byIcon(Icons.drag_indicator_rounded).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump(const Duration(milliseconds: 50));
    // Move in small steps so the list can follow the dragged card.
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(Offset(0, (pitch * 2 - 24 + 8) / 12));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    await settle(tester);

    expect(_listed(tester).take(3), ['Wasser', 'Gewicht', 'Schritte']);
  });

  testWidgets(
    'order and visibility survive a restart and show on the dashboard '
    '(AT02, C04)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await _open(tester);
      await _tapSemantic(tester, 'Aufgaben nach oben verschieben');
      await _tapSemantic(tester, 'Aufgaben nach oben verschieben');
      await _tapSemantic(tester, 'Fokus auf dem Dashboard anzeigen');
      final before = _listed(tester);

      // The process ends; a new one opens the same database.
      await pumpHome(tester, harness);
      Offset at(String title) => tester.getTopLeft(find.text(title));
      expect(find.text('Fokus'), findsNothing);
      // Aufgaben moved from the sixth to the fourth place: after Gewicht,
      // before Workout.
      expect(at('Aufgaben').dy, greaterThan(at('Gewicht').dy));
      expect(at('Aufgaben').dy, lessThan(at('Workout').dy));
      await _open(tester);
      expect(_listed(tester), before);
      expect(find.text('Ausgeblendet'), findsOneWidget);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    'a failed change keeps the order, offers a retry and the retry applies '
    'it (AT27)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await _open(tester);

      await tester.runAsync(
        () => harness.database.customStatement(
          'CREATE TRIGGER fail_move BEFORE UPDATE ON dashboard_cards '
          "BEGIN SELECT RAISE(ABORT, 'simulated write error'); END",
        ),
      );
      await _tapSemantic(tester, 'Wasser nach oben verschieben');
      expect(_listed(tester).take(2), ['Schritte', 'Wasser']);
      final error = fixture.feedback.last!;
      expect(error.kind, 'error');
      expect(error.message, contains('nicht gespeichert'));
      expect(error.onRetry, isNotNull);

      await tester.runAsync(
        () => harness.database.customStatement('DROP TRIGGER fail_move'),
      );
      error.onRetry!();
      await settle(tester);
      expect(_listed(tester).take(2), ['Wasser', 'Schritte']);
      semantics.dispose();
    },
  );

  testWidgets(
    'cards of a switched-off module are not listed, say where they are and '
    'come back with the module (AT03, C03)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness);
      await _open(tester);
      expect(find.textContaining('weitere Karte'), findsNothing);

      await tester.runCommand(
        () => fixture.container
            .read(moduleManagerProvider)
            .setEnabled(
              commandId: 'off',
              module: ModuleId.body,
              enabled: false,
            ),
      );
      await settle(tester);
      expect(_listed(tester), isNot(contains('Schritte')));
      expect(_listed(tester), isNot(contains('Gewicht')));
      await tester.ensureVisible(find.text('Module verwalten'));
      expect(
        find.text(
          '2 weitere Karten gehören zu ausgeschalteten Modulen. Sie '
          'erscheinen wieder, sobald du die Module einschaltest.',
        ),
        findsOneWidget,
      );

      await tester.runCommand(
        () => fixture.container
            .read(moduleManagerProvider)
            .setEnabled(commandId: 'on', module: ModuleId.body, enabled: true),
      );
      await settle(tester);
      expect(_listed(tester), _defaultOrder);
      expect(find.textContaining('weitere Karte'), findsNothing);
    },
  );

  testWidgets('"Module verwalten" leads to the module selection', (
    tester,
  ) async {
    final harness = await createHarness(
      tester,
      startedOn: _secondDay,
      enabledModules: {'focus'},
    );
    await pumpHome(tester, harness);
    await _open(tester);
    await tester.ensureVisible(find.text('Module verwalten'));
    await tester.pump();
    await tester.tap(find.text('Module verwalten'));
    await tester.pumpAndSettle();
    expect(find.text('Seite /settings/modules'), findsOneWidget);
  });

  testWidgets(
    'with every module off the page explains it and leads to the modules',
    (tester) async {
      final harness = await createHarness(tester, enabledModules: <String>{});
      final container = harness.createContainer(
        overrides: [
          dashboardModulesProvider.overrideWithValue(testModules(TapLog())),
        ],
      );
      await pumpRouterApp(
        tester,
        container: container,
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardCardsScreen(),
          ),
          GoRoute(
            path: '/settings/modules',
            builder: (context, state) =>
                const Scaffold(body: Text('Seite /settings/modules')),
          ),
        ],
      );
      await settle(tester);
      expect(find.text('Keine Karten verfügbar'), findsOneWidget);
      await tester.tap(find.text('Module auswählen'));
      await tester.pumpAndSettle();
      expect(find.text('Seite /settings/modules'), findsOneWidget);
    },
  );
}
