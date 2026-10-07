import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/dashboard_card_grid.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/no_goals_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/not_today_banner.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

// BS-93: the parts of Home that change for a day that is not today, one by one:
// the sentence of the ring card, the card without a goal, the note "Nicht
// heute" and the grid of cards.

void main() {
  group('the day card of a day before today (BS-93, BS-121)', () {
    Future<void> pump(
      WidgetTester tester, {
      required int fulfilled,
      required int applicable,
      bool isToday = false,
      VoidCallback? onTap,
    }) => pumpApp(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: DayOverviewCard(
          fulfilled: fulfilled,
          applicable: applicable,
          isToday: isToday,
          onTap: onTap,
        ),
      ),
      wrapInScaffold: true,
    );

    for (final (fulfilled, applicable, sentence) in <(int, int, String)>[
      (0, 4, 'An diesem Tag hast du kein Ziel erreicht.'),
      (3, 5, 'An diesem Tag hast du 3 von 5 Zielen erreicht.'),
      (1, 5, 'An diesem Tag hast du 1 von 5 Zielen erreicht.'),
      (4, 4, 'An diesem Tag hast du alle Tagesziele erreicht.'),
      (1, 1, 'An diesem Tag hast du dein Tagesziel erreicht.'),
    ]) {
      testWidgets('(BS-93, BS-121) $fulfilled of $applicable: "$sentence"', (
        tester,
      ) async {
        await pump(tester, fulfilled: fulfilled, applicable: applicable);
        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining('heute'), findsNothing);
      });
    }

    testWidgets('(BS-93, BS-121) no title: the sentence is the first text '
        'next to the ring', (tester) async {
      await pump(tester, fulfilled: 3, applicable: 5);
      expect(find.byType(DayOverviewCard), findsOneWidget);
      final texts = <String>[
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data ?? '',
      ];
      expect(texts, <String>[
        '3 von 5',
        'Zielen',
        'An diesem Tag hast du 3 von 5 Zielen erreicht.',
      ]);
    });

    testWidgets('(BS-93, AT34) the button of the card says it is a day of its '
        'own, not "heute"', (tester) async {
      await pump(tester, fulfilled: 2, applicable: 4, onTap: () {});
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          'Ziele dieses Tages, 2 von 4 erreicht, Details öffnen',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Ziele heute')), findsNothing);
      semantics.dispose();
    });

    testWidgets('(BS-93) today keeps its words', (tester) async {
      await pump(
        tester,
        fulfilled: 3,
        applicable: 5,
        isToday: true,
        onTap: () {},
      );
      final semantics = tester.ensureSemantics();
      expect(
        find.text('Du hast heute 3 von 5 Zielen erreicht.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Ziele heute, 3 von 5 erreicht, Details öffnen'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('the card without a goal (BS-93)', () {
    testWidgets('(BS-93) a day before today says that no goal counted, and '
        'there is no button to set one', (tester) async {
      await pumpApp(
        tester,
        const Padding(
          padding: EdgeInsets.all(16),
          child: NoGoalsCard(pastDay: true),
        ),
        wrapInScaffold: true,
      );
      expect(find.text('Keine Tagesziele an diesem Tag'), findsOneWidget);
      expect(
        find.text(
          'An diesem Tag galt kein Tagesziel. Ziele, die du festlegst, gelten '
          'ab morgen.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ziele festlegen'), findsNothing);
      expect(find.byType(SecondaryButton), findsNothing);
    });

    testWidgets('(BS-93) even with a way to set goals a past day offers none', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: NoGoalsCard(pastDay: true, onSetGoals: () {}),
        ),
        wrapInScaffold: true,
      );
      expect(find.text('Ziele festlegen'), findsNothing);
    });

    testWidgets('(BS-93) today keeps its card and its button', (tester) async {
      var set = 0;
      await pumpApp(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: NoGoalsCard(onSetGoals: () => set++),
        ),
        wrapInScaffold: true,
      );
      expect(find.text('Noch keine Tagesziele'), findsOneWidget);
      await tester.tap(find.text('Ziele festlegen'));
      expect(set, 1);
    });
  });

  group('the note "Nicht heute" (BS-93)', () {
    Future<void> pump(
      WidgetTester tester, {
      LocalDate? date,
      VoidCallback? onBack,
      double textScale = 1.0,
      Size size = const Size(393, 852),
    }) => pumpApp(
      tester,
      Padding(
        padding: const EdgeInsets.all(16),
        child: NotTodayBanner(date: date, onBackToToday: onBack),
      ),
      wrapInScaffold: true,
      textScale: textScale,
      size: size,
    );

    testWidgets('(BS-93) on Home it is one line and the way back (the date is '
        'in the navigator above it)', (tester) async {
      var back = 0;
      await pump(tester, onBack: () => back++);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.textContaining('nur ansehen'), findsNothing);
      await tester.tap(find.text('Zurück zu heute'));
      expect(back, 1);
    });

    testWidgets('(BS-93) on "Ziele heute" it names the date as well', (
      tester,
    ) async {
      await pump(tester, date: LocalDate(2026, 10, 1), onBack: () {});
      expect(find.text('1. Oktober · nur ansehen'), findsOneWidget);
    });

    testWidgets('(BS-93, AT34) the way back is a button of at least 48 x 48 '
        'with its label', (tester) async {
      await pump(tester, onBack: () {});
      final semantics = tester.ensureSemantics();
      final size = tester.getSize(find.text('Zurück zu heute'));
      expect(size.height, greaterThan(10));
      final button = tester.getSemantics(find.text('Zurück zu heute'));
      expect(button.label, 'Zurück zu heute');
      expect(button.flagsCollection.isButton, isTrue);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('(BS-93, AT33) with large text on a narrow screen the way back '
        'goes below the text', (tester) async {
      await pump(
        tester,
        onBack: () {},
        textScale: 2.0,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Zurück zu heute')).dy,
        greaterThan(tester.getTopLeft(find.text('Nicht heute')).dy),
      );
    });

    testWidgets('(BS-93) without a way back it is a plain note', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('Zurück zu heute'), findsNothing);
    });
  });

  group('the grid of cards for another day (BS-93)', () {
    final modules = <SelfImprovementModule>[
      FakeModule(
        id: ModuleId.body,
        title: 'Körper',
        cards: <DashboardCardDescriptor>[
          DashboardCardDescriptor(
            cardId: 'steps',
            title: 'Schritte',
            defaultRank: 0,
            builder: (context, ref) => const Text('Schritte heute'),
            dayBuilder: (context, ref, day) =>
                Text('Schritte am ${day.toIso()}'),
          ),
          DashboardCardDescriptor(
            cardId: 'weight',
            title: 'Gewicht',
            defaultRank: 2,
            builder: (context, ref) => const Text('Gewicht heute'),
          ),
        ],
      ),
      FakeModule(
        id: ModuleId.tasks,
        title: 'Aufgaben',
        cards: <DashboardCardDescriptor>[
          DashboardCardDescriptor(
            cardId: 'tasks',
            title: 'Aufgaben',
            defaultRank: 5,
            fullWidth: true,
            builder: (context, ref) => const Text('Aufgaben heute'),
            dayBuilder: (context, ref, day) =>
                Text('Aufgaben am ${day.toIso()}'),
          ),
        ],
      ),
    ];
    final entries = visibleDashboardEntries(
      configs: <DashboardCardConfig>[
        const DashboardCardConfig(
          cardId: 'steps',
          module: ModuleId.body,
          visible: true,
          sortIndex: 0,
        ),
        const DashboardCardConfig(
          cardId: 'weight',
          module: ModuleId.body,
          visible: true,
          sortIndex: 1,
        ),
        const DashboardCardConfig(
          cardId: 'tasks',
          module: ModuleId.tasks,
          visible: true,
          sortIndex: 2,
        ),
      ],
      moduleStatuses: <ModuleId, bool>{
        for (final module in ModuleId.values) module: true,
      },
      modules: modules,
    );

    testWidgets('(BS-93) without a day the grid builds the live cards', (
      tester,
    ) async {
      await pumpApp(
        tester,
        SingleChildScrollView(child: DashboardCardGrid(entries: entries)),
        wrapInScaffold: true,
      );
      expect(find.text('Schritte heute'), findsOneWidget);
      expect(find.text('Gewicht heute'), findsOneWidget);
      expect(find.text('Aufgaben heute'), findsOneWidget);
    });

    testWidgets('(BS-93) with a day every card is the one its module builds '
        'for that day', (tester) async {
      await pumpApp(
        tester,
        SingleChildScrollView(
          child: DashboardCardGrid(
            entries: entries,
            day: LocalDate(2026, 10, 1),
          ),
        ),
        wrapInScaffold: true,
      );
      expect(find.text('Schritte am 2026-10-01'), findsOneWidget);
      expect(find.text('Aufgaben am 2026-10-01'), findsOneWidget);
      expect(find.text('Schritte heute'), findsNothing);
    });

    testWidgets('(BS-93) a module without a card for a day has none there: the '
        'card is left out, never shown with the numbers of today', (
      tester,
    ) async {
      await pumpApp(
        tester,
        SingleChildScrollView(
          child: DashboardCardGrid(
            entries: entries,
            day: LocalDate(2026, 10, 1),
          ),
        ),
        wrapInScaffold: true,
      );
      expect(find.text('Gewicht heute'), findsNothing);
      expect(find.textContaining('Gewicht'), findsNothing);
    });

    testWidgets('(BS-93) the order of the others is kept and they close the '
        'gap', (tester) async {
      await pumpApp(
        tester,
        SingleChildScrollView(
          child: DashboardCardGrid(
            entries: entries,
            day: LocalDate(2026, 10, 1),
          ),
        ),
        wrapInScaffold: true,
      );
      expect(
        tester.getTopLeft(find.text('Schritte am 2026-10-01')).dy,
        lessThan(tester.getTopLeft(find.text('Aufgaben am 2026-10-01')).dy),
      );
    });

    test('(BS-93) the descriptor of a module may leave the day card out', () {
      final descriptor = DashboardCardDescriptor(
        cardId: 'steps',
        title: 'Schritte',
        defaultRank: 0,
        builder: (context, ref) => const SizedBox(),
      );
      expect(descriptor.dayBuilder, isNull);
    });
  });
}
