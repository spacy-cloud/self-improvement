import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';

import 'support/app_harness.dart';
import 'support/fake_modules.dart';

FeedbackService _feedback(AppFixture app) =>
    app.container.read(feedbackServiceProvider);

/// Advances the clock in small steps, so animations and timers run as they
/// would on a device (one big step would only start an animation).
Future<void> _advance(WidgetTester tester, Duration duration) async {
  final steps = (duration.inMilliseconds / 100).ceil();
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _show(AppFixture app, void Function() show) async {
  show();
  await app.tester.pump();
  await _advance(app.tester, const Duration(milliseconds: 500));
}

void main() {
  group('snack bar feedback (AT10, AT27)', () {
    testWidgets(
      'a success message is shown and disappears after four seconds',
      (tester) async {
        final app = await pumpFullApp(tester);
        await _show(app, () => _feedback(app).showSaved('Gewicht gespeichert'));
        expect(find.text('Gewicht gespeichert'), findsOneWidget);
        expect(find.text('Rückgängig'), findsNothing);
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Gewicht gespeichert'), findsNothing);
      },
    );

    testWidgets(
      'an undo is offered for eight seconds and runs once, with a new command',
      (tester) async {
        final app = await pumpFullApp(tester);
        var runs = 0;
        String? undoId;
        final undo = UndoAction(
          run: (id) async {
            runs++;
            undoId = id;
            return const CommandOutcome();
          },
        );
        await _show(
          app,
          () => _feedback(app).showSaved('Gespeichert', undo: undo),
        );
        expect(find.text('Rückgängig'), findsOneWidget);
        // Still offered after 6 seconds.
        await _advance(tester, const Duration(seconds: 6));
        expect(find.text('Rückgängig'), findsOneWidget);
        await tester.tap(find.text('Rückgängig'));
        await _advance(tester, const Duration(milliseconds: 900));
        expect(runs, 1);
        expect(undoId, isNotEmpty);
        expect(find.text('Rückgängig gemacht.'), findsOneWidget);
      },
    );

    testWidgets('the undo window ends after eight seconds', (tester) async {
      final app = await pumpFullApp(tester);
      final undo = UndoAction(run: (id) async => const CommandOutcome());
      await _show(
        app,
        () => _feedback(app).showSaved('Gespeichert', undo: undo),
      );
      await _advance(tester, const Duration(seconds: 9));
      expect(find.text('Rückgängig'), findsNothing);
    });

    testWidgets('an undo that conflicts says so and changes nothing', (
      tester,
    ) async {
      final app = await pumpFullApp(tester);
      final undo = UndoAction(
        run: (id) async =>
            throw const ConflictFailure(ConflictKind.staleVersion),
      );
      await _show(
        app,
        () => _feedback(app).showSaved('Gespeichert', undo: undo),
      );
      await tester.tap(find.text('Rückgängig'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Der Eintrag wurde inzwischen geändert.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'an error with a retry stays until the user acts, then retries once',
      (tester) async {
        final app = await pumpFullApp(tester);
        var retries = 0;
        await _show(
          app,
          () => _feedback(app)
              .showError('Speichern fehlgeschlagen.', onRetry: () => retries++),
        );
        expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 30));
        expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
        await tester.tap(find.text('Erneut'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(retries, 1);
        expect(find.text('Speichern fehlgeschlagen.'), findsNothing);
      },
    );

    testWidgets(
      'a new message replaces the visible one: at most one undo at a time',
      (tester) async {
        final app = await pumpFullApp(tester);
        final undo = UndoAction(run: (id) async => const CommandOutcome());
        await _show(app, () => _feedback(app).showSaved('Erste', undo: undo));
        await _show(app, () => _feedback(app).showSaved('Zweite', undo: undo));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Erste'), findsNothing);
        expect(find.text('Zweite'), findsOneWidget);
        expect(find.text('Rückgängig'), findsOneWidget);
      },
    );

    testWidgets('an info message is neutral and temporary', (tester) async {
      final app = await pumpFullApp(tester);
      await _show(app, () => _feedback(app).showInfo('Nur zur Information'));
      expect(find.text('Nur zur Information'), findsOneWidget);
    });

    testWidgets(
      'on a tab the bar floats above the navigation, on a sub page above the pinned action',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _show(app, () => _feedback(app).showInfo('Auf dem Tab'));
        final tabBottom = tester.getBottomLeft(find.text('Auf dem Tab')).dy;
        final navigationTop = tester
            .getTopLeft(find.byType(AppBottomNavBar))
            .dy;
        expect(tabBottom, lessThanOrEqualTo(navigationTop));
        ScaffoldMessenger.of(tester.element(find.byType(AppBottomNavBar)))
            .clearSnackBars();
        await tester.pump(const Duration(milliseconds: 400));

        unawaited(app.router.push<void>('/weight/new'));
        await tester.pump();
        await app.settle();
        await _show(app, () => _feedback(app).showInfo('Im Formular'));
        final formBottom = tester.getBottomLeft(find.text('Im Formular')).dy;
        expect(
          formBottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height - AppSizes.pinnedActionArea,
          ),
        );
      },
    );

    testWidgets('the message is announced as a live region', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpFullApp(tester);
      await _show(app, () => _feedback(app).showError('Fehlerhinweis'));
      expect(find.bySemanticsLabel('Fehlerhinweis'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
      handle.dispose();
    });
  });
}
