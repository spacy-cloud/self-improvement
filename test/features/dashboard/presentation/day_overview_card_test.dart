import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/no_goals_card.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/design/support/ring_arcs.dart';
import '../../../support/pump_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int fulfilled,
  required int applicable,
  String? motivation = 'Bleib in deinem Tempo.',
  double scale = 1.0,
  Size size = const Size(393, 852),
  AppThemeVariant theme = AppThemeVariant.light,
}) async {
  await pumpApp(
    tester,
    SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DayOverviewCard(
        fulfilled: fulfilled,
        applicable: applicable,
        motivation: motivation,
      ),
    ),
    size: size,
    textScale: scale,
    theme: theme,
    wrapInScaffold: true,
  );
  // A ring that changes its value animates; the tests look at the final state.
  await tester.pumpAndSettle();
}

typedef _State = ({
  int fulfilled,
  int applicable,
  GoalsStanding standing,
  String title,
});

/// The four states of the ticket BS-121 with the title of 3 October 2026 (day
/// 276, the first text of each list).
const List<_State> _states = <_State>[
  (
    fulfilled: 0,
    applicable: 4,
    standing: GoalsStanding.none,
    title: 'Heute ist ein guter Tag, um anzufangen.',
  ),
  (
    fulfilled: 2,
    applicable: 4,
    standing: GoalsStanding.partial,
    title: 'Stark unterwegs!',
  ),
  (
    fulfilled: 4,
    applicable: 4,
    standing: GoalsStanding.all,
    title: 'Geschafft!',
  ),
  (
    fulfilled: 1,
    applicable: 1,
    standing: GoalsStanding.all,
    title: 'Geschafft!',
  ),
];

/// The arcs the ring has to paint in [colors] for [standing] and [fraction].
List<PaintedArc> _expectedArcs(
  AppColors colors,
  GoalsStanding standing,
  double fraction,
) {
  return <PaintedArc>[
    (color: colors.track, sweep: 2 * math.pi),
    if (standing == GoalsStanding.partial)
      (color: colors.dayRing, sweep: 2 * math.pi * fraction),
    if (standing == GoalsStanding.all)
      (color: colors.dayRingComplete, sweep: 2 * math.pi),
  ];
}

void main() {
  group('texts follow the numbers (C04)', () {
    testWidgets('some goals reached', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      expect(find.text('3 von 4'), findsOneWidget);
      expect(find.text('Zielen'), findsOneWidget);
      expect(find.text('Bleib in deinem Tempo.'), findsOneWidget);
      expect(
        find.text('Du hast heute 3 von 4 Zielen erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('no goal reached yet', (tester) async {
      await _pump(tester, fulfilled: 0, applicable: 4);
      expect(find.text('0 von 4'), findsOneWidget);
      expect(
        find.text('Du hast heute noch kein Ziel erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('all goals reached', (tester) async {
      await _pump(tester, fulfilled: 4, applicable: 4);
      expect(
        find.text('Du hast heute alle Tagesziele erreicht.'),
        findsOneWidget,
      );
    });

    testWidgets('a single goal uses the singular', (tester) async {
      await _pump(tester, fulfilled: 1, applicable: 1);
      expect(find.text('1 von 1'), findsOneWidget);
      expect(find.text('Ziel'), findsOneWidget);
      expect(
        find.text('Du hast heute dein Tagesziel erreicht.'),
        findsOneWidget,
      );
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('1 von 1 Ziel erreicht'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the ring has its own spoken text', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('3 von 4 Zielen erreicht'), findsOneWidget);
      semantics.dispose();
    });

    test('a ring without an applicable goal is not allowed', () {
      expect(
        () => DayOverviewCard(fulfilled: 0, applicable: 0, motivation: 'x'),
        throwsAssertionError,
      );
    });
  });

  group('the ring colour follows the stand, in every theme (BS-121)', () {
    test('(C04) the ring and the title tell the same stand for every pair of '
        'numbers', () {
      // The ring (design layer) and the title (dashboard domain) each decide
      // from the two counts; they must never disagree.
      for (var applicable = -2; applicable <= 6; applicable++) {
        for (var fulfilled = -2; fulfilled <= 8; fulfilled++) {
          final standing = GoalsStanding.of(
            fulfilled: fulfilled,
            applicable: applicable,
          );
          final reason = '$fulfilled of $applicable';
          expect(
            ProgressRing.isComplete(fulfilled, applicable),
            standing == GoalsStanding.all,
            reason: reason,
          );
          expect(
            ProgressRing.fraction(fulfilled, applicable) > 0,
            standing != GoalsStanding.none,
            reason: '$reason: an arc exists exactly when something is reached',
          );
        }
      }
    });

    for (final theme in AppThemeVariant.values) {
      final colors = theme.colors;
      for (final state in _states) {
        testWidgets(
          '(C06, AT35, Q03) ${theme.name}: ${state.fulfilled} of ${state.applicable} '
          'paints ${state.standing.name}: grey track, yellow arc or full green '
          'ring',
          (tester) async {
            await _pump(
              tester,
              fulfilled: state.fulfilled,
              applicable: state.applicable,
              motivation: state.title,
              theme: theme,
            );
            expect(
              paintedArcs(tester),
              _expectedArcs(
                colors,
                state.standing,
                state.fulfilled / state.applicable,
              ),
            );
          },
        );
      }
    }

    testWidgets('(C06) 0 of 4 has no arc at all, only the grey track', (
      tester,
    ) async {
      await _pump(tester, fulfilled: 0, applicable: 4);
      final arcs = paintedArcs(tester);
      expect(arcs, hasLength(1));
      expect(arcs.single.color, AppColors.light.track);
    });

    testWidgets(
      '(C06) 2 of 4 is a half arc in yellow, 4 of 4 and 1 of 1 a full green '
      'ring: the colour comes from the tokens, not from the card',
      (tester) async {
        await _pump(tester, fulfilled: 2, applicable: 4);
        expect(paintedArcs(tester).last.sweep, math.pi);
        expect(paintedArcs(tester).last.color, AppColors.light.dayRing);
        for (final (fulfilled, applicable) in const <(int, int)>[
          (4, 4),
          (1, 1),
        ]) {
          await _pump(tester, fulfilled: fulfilled, applicable: applicable);
          expect(paintedArcs(tester).last.sweep, 2 * math.pi);
          expect(
            paintedArcs(tester).last.color,
            AppColors.light.dayRingComplete,
          );
        }
      },
    );

    for (final theme in AppThemeVariant.values) {
      testWidgets(
        '(C04, Q03) ${theme.name}: the card and a bare ProgressRing.goals (the '
        'goals overview of BS-103) paint the same ring in every state',
        (tester) async {
          for (final state in _states) {
            await _pump(
              tester,
              fulfilled: state.fulfilled,
              applicable: state.applicable,
              theme: theme,
            );
            final inCard = paintedArcs(tester);
            // The card does not choose a colour itself.
            expect(
              tester.widget<ProgressRing>(find.byType(ProgressRing)).color,
              isNull,
            );
            await pumpApp(
              tester,
              Center(
                child: ProgressRing.goals(
                  fulfilled: state.fulfilled,
                  applicable: state.applicable,
                ),
              ),
              theme: theme,
              wrapInScaffold: true,
            );
            expect(
              paintedArcs(tester),
              inCard,
              reason: '${state.fulfilled} of ${state.applicable}',
            );
          }
        },
      );
    }

    testWidgets('the ring moves from grey to yellow to green while goals are '
        'reached', (tester) async {
      Future<void> showCard(int fulfilled) => pumpApp(
        tester,
        DayOverviewCard(fulfilled: fulfilled, applicable: 3),
        wrapInScaffold: true,
      );
      const colors = AppColors.light;
      await showCard(0);
      expect(paintedArcs(tester).map((arc) => arc.color), [colors.track]);
      await showCard(1);
      await tester.pumpAndSettle();
      expect(paintedArcs(tester).map((arc) => arc.color), [
        colors.track,
        colors.dayRing,
      ]);
      await showCard(2);
      await tester.pumpAndSettle();
      expect(paintedArcs(tester).last.color, colors.dayRing);
      await showCard(3);
      await tester.pumpAndSettle();
      expect(paintedArcs(tester).map((arc) => arc.color), [
        colors.track,
        colors.dayRingComplete,
      ]);
    });
  });

  group('the title is shown as given and may be missing (BS-121)', () {
    for (final state in _states) {
      testWidgets(
        '(C04) ${state.fulfilled} of ${state.applicable}: the title of the '
        'stand and the factual sentence',
        (tester) async {
          await _pump(
            tester,
            fulfilled: state.fulfilled,
            applicable: state.applicable,
            motivation: state.title,
          );
          expect(find.text(state.title), findsOneWidget);
          expect(
            find.text('${state.fulfilled} von ${state.applicable}'),
            findsOneWidget,
          );
          // The title is above the sentence.
          final title = tester.getTopLeft(find.text(state.title)).dy;
          final sentence = tester
              .getTopLeft(find.textContaining('Du hast heute'))
              .dy;
          expect(title, lessThan(sentence));
        },
      );
    }

    testWidgets(
      '(C04) without a title only the factual sentence is shown (a past day '
      'asks for no "heute" title, BS-93)',
      (tester) async {
        await _pump(tester, fulfilled: 3, applicable: 5, motivation: null);
        expect(find.text('3 von 5'), findsOneWidget);
        expect(
          find.text('Du hast heute 3 von 5 Zielen erreicht.'),
          findsOneWidget,
        );
        for (final standing in GoalsStanding.values) {
          for (final text in motivationTextsOf(standing)) {
            expect(find.text(text), findsNothing, reason: text);
          }
        }
        expect(tester.takeException(), isNull);
        // The ring still follows the stand.
        expect(paintedArcs(tester).last.color, AppColors.light.dayRing);
      },
    );

    testWidgets(
      '(C04) the home screen chooses the title with motivationTextFor for the '
      'stand of the day',
      (tester) async {
        final day = LocalDate(2026, 10, 4);
        for (final state in _states) {
          await _pump(
            tester,
            fulfilled: state.fulfilled,
            applicable: state.applicable,
            motivation: motivationTextFor(
              day,
              fulfilled: state.fulfilled,
              applicable: state.applicable,
            ),
          );
          // 4 October 2026 is day 277, 277 % 3 == 1: the second text.
          expect(
            find.text(motivationTextsOf(state.standing)[1]),
            findsOneWidget,
            reason: '${state.fulfilled} of ${state.applicable}',
          );
        }
      },
    );
  });

  group('the stand is read aloud and never only shown by colour (BS-121)', () {
    for (final state in _states) {
      testWidgets(
        '(AT34, Q02) ${state.fulfilled} of ${state.applicable}: the ring '
        'speaks the numbers, the card reads title and sentence',
        (tester) async {
          await _pump(
            tester,
            fulfilled: state.fulfilled,
            applicable: state.applicable,
            motivation: state.title,
          );
          final semantics = tester.ensureSemantics();
          final spoken = state.applicable == 1
              ? '${state.fulfilled} von 1 Ziel erreicht'
              : '${state.fulfilled} von ${state.applicable} Zielen erreicht';
          expect(find.bySemanticsLabel(spoken), findsOneWidget);
          expect(
            find.bySemanticsLabel(RegExp(RegExp.escape(state.title))),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(RegExp('Du hast heute')),
            findsOneWidget,
          );
          // The ring is a picture: its centre text is not read a second time.
          expect(
            find.bySemanticsLabel('${state.fulfilled} von ${state.applicable}'),
            findsNothing,
          );
          semantics.dispose();
        },
      );
    }
  });

  group('layout', () {
    testWidgets('ring and text share a row on a normal phone', (tester) async {
      await _pump(tester, fulfilled: 3, applicable: 4);
      final ring = tester.getCenter(find.text('3 von 4'));
      final text = tester.getTopLeft(find.text('Bleib in deinem Tempo.'));
      expect(text.dx, greaterThan(ring.dx));
    });

    testWidgets('at large text the text goes below the ring (AT33)', (
      tester,
    ) async {
      await _pump(
        tester,
        fulfilled: 3,
        applicable: 4,
        scale: 2.0,
        size: const Size(320, 640),
      );
      final ring = tester.getCenter(find.text('3 von 4'));
      final text = tester.getTopLeft(find.text('Bleib in deinem Tempo.'));
      expect(text.dy, greaterThan(ring.dy));
      expect(tester.takeException(), isNull);
    });
  });

  group('every stand fits and stays accessible (BS-121)', () {
    for (final size in responsiveSizes) {
      for (final scale in const <double>[1.0, 2.0]) {
        testWidgets(
          '(Q02, AT33) ${size.width.toInt()} px at text scale $scale: no '
          'overflow, tap targets and labels in all four states',
          (tester) async {
            for (final state in _states) {
              await _pump(
                tester,
                fulfilled: state.fulfilled,
                applicable: state.applicable,
                motivation: state.title,
                scale: scale,
                size: size,
              );
              final semantics = tester.ensureSemantics();
              expect(tester.takeException(), isNull);
              await expectLater(
                tester,
                meetsGuideline(androidTapTargetGuideline),
              );
              await expectLater(
                tester,
                meetsGuideline(labeledTapTargetGuideline),
              );
              semantics.dispose();
            }
          },
        );
      }
    }

    for (final theme in AppThemeVariant.values) {
      testWidgets(
        '(Q02, C06, AT35) ${theme.name}: the text of every state is readable',
        (tester) async {
          for (final state in _states) {
            await _pump(
              tester,
              fulfilled: state.fulfilled,
              applicable: state.applicable,
              motivation: state.title,
              theme: theme,
            );
            final semantics = tester.ensureSemantics();
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantics.dispose();
          }
        },
      );
    }
  });

  testWidgets('the card without goals asks to set them (never a 0 of 0 ring)', (
    tester,
  ) async {
    var opened = 0;
    await pumpApp(
      tester,
      NoGoalsCard(onSetGoals: () => opened++),
      wrapInScaffold: true,
    );
    expect(find.text('Noch keine Tagesziele'), findsOneWidget);
    expect(find.textContaining('von 0'), findsNothing);
    await tester.tap(find.text('Ziele festlegen'));
    expect(opened, 1);
  });
}
