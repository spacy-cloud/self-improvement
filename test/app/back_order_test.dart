import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/app_harness.dart';
import 'support/fake_modules.dart';

final AppTabBuilders _tabs = AppTabBuilders(
  home: (context, state) => const CounterTab('Tab-Home'),
  analysis: (context, state) => const CounterTab('Tab-Analyse'),
  habits: (context, state) => const CounterTab('Tab-Habits'),
  profile: (context, state) => const CounterTab('Tab-Profil'),
);

Future<void> _openPlus(AppFixture app) async {
  await app.tester.tap(plusButton());
  await app.tester.pump();
  await app.settle();
}

Future<void> _pickEntry(AppFixture app, String label) async {
  await app.tester.tap(find.text(label));
  await app.tester.pump();
  await app.settle();
}

void main() {
  group('Android back order (C02)', () {
    testWidgets('an open plus menu is closed first and nothing else changes', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await tester.tap(navTab('Analyse'));
      await app.settle();
      await _openPlus(app);
      expect(await app.systemBack(), isTrue);
      expect(plusSheet(), findsNothing);
      expect(app.location, '/analysis');
      expect(find.text('Tab-Analyse:0'), findsOneWidget);
      expect(app.exitRequests, 0);
    });

    testWidgets('a sub page is closed next and returns to the starting tab', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await tester.tap(navTab('Analyse'));
      await app.settle();
      await _openPlus(app);
      await _pickEntry(app, 'Wasser');
      expect(app.location, '/water');
      expect(await app.systemBack(), isTrue);
      expect(app.location, '/analysis');
      expect(find.text('Tab-Analyse:0'), findsOneWidget);
    });

    testWidgets(
      'a tab other than Home goes to Home, only Home hands over to the system',
      (tester) async {
        final app = await pumpFullApp(tester, tabs: _tabs);
        await tester.tap(navTab('Profil'));
        await app.settle();
        expect(app.location, '/profile');
        expect(await app.systemBack(), isTrue);
        expect(app.location, '/');
        expect(find.text('Tab-Home:0'), findsOneWidget);
        expect(app.exitRequests, 0);
        expect(await app.systemBack(), isFalse);
        expect(app.exitRequests, 1);
      },
    );

    testWidgets('the whole order: modal, sub page, Home tab, system', (
      tester,
    ) async {
      final app = await pumpFullApp(
        tester,
        tabs: _tabs,
        modules: fullFakeModules(),
      );
      await tester.tap(navTab('Habits'));
      await app.settle();
      await _openPlus(app);
      await _pickEntry(app, 'Wasser');
      // Reopen the menu on the sub page's tab after returning once.
      expect(await app.systemBack(), isTrue); // sub page -> Habits tab
      expect(app.location, '/habits');
      await _openPlus(app);
      expect(plusSheet(), findsOneWidget);
      expect(await app.systemBack(), isTrue); // modal closes
      expect(plusSheet(), findsNothing);
      expect(app.location, '/habits');
      expect(await app.systemBack(), isTrue); // Habits tab -> Home tab
      expect(app.location, '/');
      expect(app.exitRequests, 0);
      expect(await app.systemBack(), isFalse); // Home -> system
      expect(app.exitRequests, 1);
    });

    testWidgets(
      'a screen opened without history goes to Home, not out of the app',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          tabs: _tabs,
          modules: fullFakeModules(),
        );
        app.router.go('/weight/new');
        await tester.pump();
        await app.settle();
        expect(app.location, '/weight/new');
        expect(await app.systemBack(), isTrue);
        expect(app.location, '/');
        expect(app.exitRequests, 0);
      },
    );

    testWidgets(
      'during the onboarding back leaves the app (its first step is the start)',
      (tester) async {
        final app = await pumpFullApp(tester, onboarded: false);
        expect(await app.systemBack(), isFalse);
        expect(app.exitRequests, 1);
      },
    );
  });

  group('discard behaviour of a changed form (C02)', () {
    Future<AppFixture> openWeightForm(WidgetTester tester) async {
      final app = await pumpFullApp(tester, tabs: _tabs);
      await _openPlus(app);
      await _pickEntry(app, 'Gewicht');
      expect(find.text('Gewicht eintragen'), findsWidgets);
      return app;
    }

    testWidgets('an unchanged form leaves without asking', (tester) async {
      final app = await openWeightForm(tester);
      expect(await app.systemBack(), isTrue);
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(app.location, '/');
      expect(find.text('Tab-Home:0'), findsOneWidget);
    });

    testWidgets('a changed form asks, keeps the input on "Weiter bearbeiten"', (
      tester,
    ) async {
      final app = await openWeightForm(tester);
      await tester.enterText(find.byType(TextField).first, '71,5');
      await tester.pump();
      expect(await app.systemBack(), isTrue);
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await tester.tap(find.text('Weiter bearbeiten'));
      await tester.pump();
      await app.settle();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Gewicht eintragen'), findsWidgets);
      expect(find.text('71,5'), findsWidgets);
      expect(app.location, '/weight/new');
    });

    testWidgets(
      '"Verwerfen" returns to where the flow started and saves nothing',
      (tester) async {
        final app = await openWeightForm(tester);
        await tester.enterText(find.byType(TextField).first, '71,5');
        await tester.pump();
        await app.systemBack();
        await tester.tap(find.text('Verwerfen'));
        await tester.pump();
        await app.settle();
        expect(app.location, '/');
        expect(find.text('Tab-Home:0'), findsOneWidget);
        final rows = await tester.runAsync(
          () => app.harness.database
              .select(app.harness.database.weightEntries)
              .get(),
        );
        expect(rows, isEmpty);
      },
    );

    testWidgets('back closes the discard question like "Weiter bearbeiten"', (
      tester,
    ) async {
      final app = await openWeightForm(tester);
      await tester.enterText(find.byType(TextField).first, '71,5');
      await tester.pump();
      await app.systemBack();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
      await app.systemBack();
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Gewicht eintragen'), findsWidgets);
    });

    testWidgets('the header back button asks too', (tester) async {
      final app = await openWeightForm(tester);
      await tester.enterText(find.byType(TextField).first, '71,5');
      await tester.pump();
      await tester.tap(find.byIcon(AppIcon.back.data));
      await tester.pump();
      await app.settle();
      expect(find.text('Änderungen verwerfen?'), findsOneWidget);
    });
  });
}
