import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart';

import '../../../core/design/support/contrast.dart';
import '../../../support/pump_app.dart';

/// The sheet "Wie war dein Tag?" (BS-99, Figma `4117:473` Hell, `4117:770`
/// Dunkel, `4117:1067` OLED): content, the three answers, closing, labels, tap
/// targets, large text and the three themes.
void main() {
  WorkoutDayChoice? result;
  var closed = false;

  /// A page with one button that opens the sheet and remembers the answer.
  Future<void> pumpHost(
    WidgetTester tester, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
    AppThemeVariant theme = AppThemeVariant.light,
  }) async {
    result = null;
    closed = false;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              result = await showWorkoutDaySheet(context);
              closed = true;
            },
            child: const Text('Öffnen'),
          ),
        ),
      ),
      size: size,
      textScale: textScale,
      theme: theme,
      wrapInScaffold: true,
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Öffnen'));
    await tester.pumpAndSettle();
  }

  group('content', () {
    testWidgets(
      '(BS-99) asks "Wie war dein Tag?" with the three answers and the note about the week',
      (tester) async {
        await pumpHost(tester);
        await open(tester);

        expect(find.text('WORKOUT HEUTE'), findsOneWidget);
        expect(find.text('Wie war dein Tag?'), findsOneWidget);
        expect(find.text('Training eintragen'), findsOneWidget);
        expect(find.text('Workout erfassen'), findsOneWidget);
        expect(find.text('Ruhetag'), findsOneWidget);
        expect(find.text('Heute überspringen'), findsOneWidget);
        expect(
          find.text('Zählt als erreicht, keine XP'),
          findsNWidgets(2),
          reason: 'a rest day and a skipped day, both without XP',
        );
        expect(
          find.text(
            'Das Wochenziel bleibt getrennt und zählt nur echte Workouts.',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.fitness_center_rounded), findsOneWidget);
        expect(find.byIcon(workoutRestIcon), findsOneWidget);
        expect(find.byIcon(workoutSkipIcon), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-99) the first answer carries the tint and the border of the main action',
      (tester) async {
        await pumpHost(tester);
        await open(tester);
        final colors = tester
            .element(find.byType(WorkoutDaySheet))
            .tokens
            .colors;

        Material materialOfAnswer(String key) => tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(ValueKey<String>(key)),
                matching: find.byType(Material),
              )
              .first,
        );

        final training = materialOfAnswer('workout-day-training');
        expect(training.color, colors.primaryTint);
        expect(
          (training.shape! as RoundedRectangleBorder).side.color,
          colors.primary,
        );
        final rest = materialOfAnswer('workout-day-rest');
        expect(rest.color, colors.surface);
        expect(
          (rest.shape! as RoundedRectangleBorder).side.color,
          colors.borderDecorative,
        );
      },
    );
  });

  group('answering', () {
    for (final (key, choice) in [
      ('workout-day-training', WorkoutDayChoice.training),
      ('workout-day-rest', WorkoutDayChoice.rest),
      ('workout-day-skipped', WorkoutDayChoice.skipped),
    ]) {
      testWidgets('(BS-99) tapping $key closes the sheet with ${choice.name}', (
        tester,
      ) async {
        await pumpHost(tester);
        await open(tester);
        await tester.tap(find.byKey(ValueKey<String>(key)));
        await tester.pumpAndSettle();
        expect(result, choice);
        expect(closed, isTrue);
        expect(find.byType(WorkoutDaySheet), findsNothing);
      });
    }

    testWidgets('(BS-99) the close button closes without an answer', (
      tester,
    ) async {
      await pumpHost(tester);
      await open(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(find.byType(WorkoutDaySheet), findsNothing);
    });

    testWidgets('(BS-99) the barrier closes without an answer', (tester) async {
      await pumpHost(tester);
      await open(tester);
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('(BS-99) the system back closes without an answer', (
      tester,
    ) async {
      await pumpHost(tester);
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, isNull);
      expect(find.byType(WorkoutDaySheet), findsNothing);
    });
  });

  group('labels and semantics (AT34)', () {
    testWidgets(
      '(BS-99, AT34) the sheet is a named scope, the question a header, every answer a button with its explanation',
      (tester) => withSemantics(tester, () async {
        await pumpHost(tester);
        await open(tester);

        // The barrier is labelled "Schließen" too: look inside the sheet.
        Finder inSheet(String label) => find.descendant(
          of: find.byType(WorkoutDaySheet),
          matching: find.bySemanticsLabel(label),
        );

        for (final label in [
          'Training eintragen, Workout erfassen',
          'Ruhetag, Zählt als erreicht, keine XP',
          'Heute überspringen, Zählt als erreicht, keine XP',
          'Schließen',
        ]) {
          final node = tester.getSemantics(inSheet(label));
          expect(node.flagsCollection.isButton, isTrue, reason: label);
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: label,
          );
        }
        final header = tester.getSemantics(inSheet('Wie war dein Tag?').last);
        expect(header.flagsCollection.isHeader, isTrue);
        expect(
          find.bySemanticsLabel('WORKOUT HEUTE'),
          findsNothing,
          reason: 'the kicker is decoration, the header says it all',
        );
      }),
    );

    testWidgets(
      '(BS-99, AT34) the tap action of an answer answers',
      (tester) => withSemantics(tester, () async {
        await pumpHost(tester);
        await open(tester);
        tester.semantics.tap(
          find.semantics.byLabel('Ruhetag, Zählt als erreicht, keine XP'),
        );
        await tester.pumpAndSettle();
        expect(result, WorkoutDayChoice.rest);
      }),
    );
  });

  group('layout (AT33, AT34)', () {
    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '(BS-99, AT33) fits ${size.width.toInt()} px at text scale $scale, every answer is reachable with at least 48 x 48',
          (tester) => withSemantics(tester, () async {
            await pumpHost(tester, size: size, textScale: scale);
            await open(tester);
            expect(tester.takeException(), isNull, reason: 'no overflow');
            for (final key in [
              'workout-day-training',
              'workout-day-rest',
              'workout-day-skipped',
            ]) {
              final finder = find.byKey(ValueKey<String>(key));
              await tester.ensureVisible(finder);
              await tester.pump();
              final rect = tester.getRect(finder);
              expect(rect.height, greaterThanOrEqualTo(64), reason: key);
              expect(rect.width, greaterThanOrEqualTo(48), reason: key);
              expect(rect.left, greaterThanOrEqualTo(0), reason: key);
              expect(rect.right, lessThanOrEqualTo(size.width), reason: key);
            }
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
          }),
        );
      }
    }

    testWidgets(
      '(BS-99, AT33) with large text the close button gets its own row above the title',
      (tester) async {
        await pumpHost(tester, size: const Size(320, 640), textScale: 2.0);
        await open(tester);
        final closeBottom = tester.getBottomLeft(
          find.byIcon(Icons.close_rounded),
        );
        final titleTop = tester.getTopLeft(find.text('Wie war dein Tag?'));
        expect(closeBottom.dy, lessThanOrEqualTo(titleTop.dy));
      },
    );

    testWidgets(
      '(BS-99) with normal text the close button sits beside the title',
      (tester) async {
        await pumpHost(tester);
        await open(tester);
        final close = tester.getCenter(find.byIcon(Icons.close_rounded));
        final title = tester.getCenter(find.text('Wie war dein Tag?'));
        expect(
          (close.dy - title.dy).abs(),
          lessThan(40),
          reason: 'the same header block',
        );
        expect(close.dx, greaterThan(title.dx));
      },
    );
  });

  group('themes (AT35)', () {
    for (final theme in AppThemeVariant.values) {
      testWidgets(
        '(BS-99, AT35) renders in ${theme.name} with readable text, no overflow and every colour pair above its limit',
        (tester) async {
          await pumpHost(tester, theme: theme);
          await open(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Wie war dein Tag?'), findsOneWidget);

          final colors = tester
              .element(find.byType(WorkoutDaySheet))
              .tokens
              .colors;
          Color textColorOf(String text) =>
              tester.widget<Text>(find.text(text).first).style!.color!;

          // The framework guideline samples pixels behind the scrim of a
          // modal sheet, so the pairs are measured from the colours in use.
          void text(String label, Color background) {
            expect(
              contrastRatio(textColorOf(label), background),
              greaterThanOrEqualTo(4.5),
              reason: '${theme.name}: "$label"',
            );
          }

          text('Wie war dein Tag?', colors.surface);
          text('WORKOUT HEUTE', colors.surface);
          text(
            'Das Wochenziel bleibt getrennt und zählt nur echte Workouts.',
            colors.surface,
          );
          text('Training eintragen', colors.primaryTint);
          text('Workout erfassen', colors.primaryTint);
          text('Ruhetag', colors.surface);
          text('Heute überspringen', colors.surface);
          expect(
            contrastRatio(
              tester
                  .widget<Text>(find.text('Zählt als erreicht, keine XP').first)
                  .style!
                  .color!,
              colors.surface,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.name}: the explanation of a rest day',
          );

          // The glyphs are graphics: 3:1 on their tile.
          expect(
            contrastRatio(
              colors.moduleWorkout,
              Color.alphaBlend(colors.tintWorkout, colors.primaryTint),
            ),
            greaterThanOrEqualTo(3),
            reason: '${theme.name}: the dumbbell on its tile',
          );
          final neutralTile = Color.alphaBlend(
            colors.textSecondary.withValues(alpha: 0.14),
            colors.surface,
          );
          expect(
            contrastRatio(colors.textSecondary, neutralTile),
            greaterThanOrEqualTo(3),
            reason: '${theme.name}: the moon and the skip glyph on their tile',
          );
        },
      );
    }
  });
}

/// Runs [body] with the semantics tree enabled and releases the handle.
Future<void> withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}
