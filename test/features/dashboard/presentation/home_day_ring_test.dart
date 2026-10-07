import 'dart:math' as math;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../core/design/support/ring_arcs.dart';
import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

// BS-121: the day ring and the title of the day card follow the stand of
// today's goals (none, some or all reached) on the real Home screen.

/// A day after the profile start: no welcome, the real dashboard.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

/// A day with [applicable] applicable goals, the first [fulfilled] of them
/// reached, and one goal that does not apply and so counts for nothing.
DayStatus _status({
  required int fulfilled,
  required int applicable,
  LocalDate? date,
}) {
  return DayStatus(
    date: date ?? LocalDate(2026, 10, 3),
    goals: <GoalProgress>[
      for (var i = 0; i < applicable; i++)
        GoalProgress(
          goalKey: 'goal_$i',
          module: ModuleId.body,
          target: 1,
          applicable: true,
          fulfilled: i < fulfilled,
          current: i < fulfilled ? 1 : 0,
        ),
      const GoalProgress(
        goalKey: 'goal_off',
        module: ModuleId.body,
        target: 1,
        applicable: false,
        fulfilled: false,
        current: 0,
      ),
    ],
  );
}

/// Replaces the live status of today by [status] (the numbers are what the
/// test is about, not how they arise).
Override _today(DayStatus status) =>
    todayStatusProvider.overrideWith((ref) => Stream<DayStatus?>.value(status));

/// Every title of the app: exactly one of them is on screen.
List<String> _titlesOnScreen() => <String>[
  for (final standing in GoalsStanding.values)
    for (final text in motivationTextsOf(standing))
      if (find.text(text).evaluate().isNotEmpty) text,
];

/// The arcs of the ring for [standing] (a stand "partial" with [fraction]).
List<PaintedArc> _arcs(
  AppColors colors,
  GoalsStanding standing, [
  double fraction = 0,
]) {
  return <PaintedArc>[
    (color: colors.track, sweep: 2 * math.pi),
    if (standing == GoalsStanding.partial)
      (color: colors.dayRing, sweep: 2 * math.pi * fraction),
    if (standing == GoalsStanding.all)
      (color: colors.dayRingComplete, sweep: 2 * math.pi),
  ];
}

void main() {
  group('the colour of the ring follows the stand, in every theme', () {
    for (final theme in AppThemeVariant.values) {
      final colors = theme.colors;
      for (final (fulfilled, applicable, standing, fraction)
          in const <(int, int, GoalsStanding, double)>[
            (0, 4, GoalsStanding.none, 0.0),
            (2, 4, GoalsStanding.partial, 0.5),
            (4, 4, GoalsStanding.all, 1.0),
            (1, 1, GoalsStanding.all, 1.0),
          ]) {
        testWidgets(
          '(C04, C06, AT35, Q03) ${theme.name}: $fulfilled of $applicable goals '
          'paint the ring for "${standing.name}"',
          (tester) async {
            final harness = await createHarness(tester, startedOn: _secondDay);
            await pumpHome(
              tester,
              harness,
              theme: theme,
              overrides: <Override>[
                _today(_status(fulfilled: fulfilled, applicable: applicable)),
              ],
            );
            expect(find.text('Dein Tag im Überblick'), findsOneWidget);
            expect(find.text('$fulfilled von $applicable'), findsOneWidget);
            expect(paintedArcs(tester), _arcs(colors, standing, fraction));
          },
        );
      }
    }
  });

  group('the title comes from the list of the stand, day after day', () {
    // 3, 4 and 5 October 2026 are the days 276, 277 and 278 of the year
    // (% 3 == 0, 1, 2). Per day: the title of "none", "some" and "all".
    const days = <(String, List<String>)>[
      (
        '2026-10-03T08:00:00Z',
        <String>[
          'Heute ist ein guter Tag, um anzufangen.',
          'Stark unterwegs!',
          'Geschafft!',
        ],
      ),
      (
        '2026-10-04T08:00:00Z',
        <String>[
          'Jeder Tag ist ein neuer Anfang.',
          'Kleine Schritte zählen.',
          'Das war ein runder Tag.',
        ],
      ),
      (
        '2026-10-05T08:00:00Z',
        <String>[
          'Ein Eintrag nach dem anderen.',
          'Bleib in deinem Tempo.',
          'Heute hat alles geklappt.',
        ],
      ),
    ];
    const states = <(int, int, int)>[
      // reached, applicable, index into the titles of the day
      (0, 4, 0),
      (2, 4, 1),
      (4, 4, 2),
      (1, 1, 2),
    ];

    for (final (nowIso, titles) in days) {
      for (final (fulfilled, applicable, index) in states) {
        testWidgets(
          '(C04, Q03) $nowIso: $fulfilled of $applicable shows "${titles[index]}" '
          'and no title of another stand',
          (tester) async {
            final harness = await createHarness(
              tester,
              startedOn: LocalDate(2026, 10, 1),
              nowIso: nowIso,
            );
            await pumpHome(
              tester,
              harness,
              overrides: <Override>[
                _today(_status(fulfilled: fulfilled, applicable: applicable)),
              ],
            );
            expect(_titlesOnScreen(), <String>[titles[index]]);
          },
        );
      }
    }
  });

  testWidgets(
    '(C04) the title and the factual sentence say the same thing: all goals '
    'reached no longer shows "Heute ist ein guter Tag, um anzufangen."',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(
        tester,
        harness,
        overrides: <Override>[_today(_status(fulfilled: 4, applicable: 4))],
      );
      expect(find.text('Geschafft!'), findsOneWidget);
      expect(
        find.text('Du hast heute alle Tagesziele erreicht.'),
        findsOneWidget,
      );
      expect(
        find.text('Heute ist ein guter Tag, um anzufangen.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    '(C04) without an applicable goal the card gives way to "Noch keine '
    'Tagesziele": no ring and no title',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      await pumpHome(
        tester,
        harness,
        overrides: <Override>[_today(_status(fulfilled: 0, applicable: 0))],
      );
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      expect(find.byType(ProgressRing), findsNothing);
      expect(_titlesOnScreen(), isEmpty);
    },
  );

  testWidgets(
    '(C04) with real data one completed task turns the only goal green '
    'and its title to "Geschafft!"; reopening takes both back',
    (tester) async {
      final harness = await createHarness(
        tester,
        startedOn: _secondDay,
        enabledModules: <String>{'tasks'},
      );
      final fixture = await pumpHome(tester, harness);
      const colors = AppColors.light;
      expect(find.text('0 von 1'), findsOneWidget);
      expect(paintedArcs(tester), _arcs(colors, GoalsStanding.none));
      expect(_titlesOnScreen(), <String>[
        'Heute ist ein guter Tag, um anzufangen.',
      ]);

      final tasks = fixture.container.read(taskRepositoryProvider);
      final created = await tester.runCommand(
        () => tasks.create(
          commandId: 't1',
          draft: const TaskDraft(title: 'Steuer machen'),
        ),
      );
      await tester.runCommand(
        () => tasks.setCompleted(
          commandId: 'c1',
          id: created.entityId!,
          completed: true,
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('1 von 1'), findsOneWidget);
      expect(
        find.text('Du hast heute dein Tagesziel erreicht.'),
        findsOneWidget,
      );
      expect(paintedArcs(tester), _arcs(colors, GoalsStanding.all));
      expect(_titlesOnScreen(), <String>['Geschafft!']);

      await tester.runCommand(
        () => tasks.setCompleted(
          commandId: 'c2',
          id: created.entityId!,
          completed: false,
        ),
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.text('0 von 1'), findsOneWidget);
      expect(paintedArcs(tester), _arcs(colors, GoalsStanding.none));
      expect(_titlesOnScreen(), <String>[
        'Heute ist ein guter Tag, um anzufangen.',
      ]);
    },
  );

  for (final theme in AppThemeVariant.values) {
    testWidgets(
      '(Q02, C06, AT35) ${theme.name}: the home screen with all goals reached '
      'keeps readable text',
      (tester) async {
        final harness = await createHarness(tester, startedOn: _secondDay);
        await pumpHome(
          tester,
          harness,
          theme: theme,
          overrides: <Override>[_today(_status(fulfilled: 4, applicable: 4))],
        );
        final semantics = tester.ensureSemantics();
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      },
    );
  }
}
