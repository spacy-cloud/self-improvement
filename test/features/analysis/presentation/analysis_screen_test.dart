import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/fake_clock.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_screen.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../analysis_test_support.dart';

/// Tall enough to show the whole page without scrolling.
const Size _tall = Size(393, 4600);

/// Text with `~` standing for the no-break space between a number and its unit.
String t(String text) => text.replaceAll('~', ' ');

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = _tall,
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  bool reducedMotion = false,
}) => pumpApp(
  tester,
  const AnalysisScreen(),
  container: container,
  size: size,
  textScale: textScale,
  theme: theme,
  reducedMotion: reducedMotion,
);

ProviderContainer _container({
  List<AnalysisDay>? days,
  Set<ModuleId>? modules,
  bool noUsageStart = false,
  LocalDate? usageStart,
  int? weeklyTarget = 3,
  FakeClock? clock,
  ReportStream? stream,
}) {
  final container = analysisContainer(
    days: days,
    modules: modules,
    noUsageStart: noUsageStart,
    usageStart: usageStart,
    weeklyTarget: weeklyTarget,
    clock: clock,
    stream: stream ?? (call, report) => Stream<AnalysisReport>.value(report),
  );
  addTearDown(container.dispose);
  return container;
}

/// The card with [title] in the metric grid (the title is in its header).
Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(AppCard)).first;

Finder _inCard(String title, Finder inner) =>
    find.descendant(of: _card(title), matching: inner);

Future<void> _selectPeriod(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('periods and the comparison base (A01)', () {
    testWidgets('7 days: the dates, "inklusive heute" and the previous period '
        '(A01)', (tester) async {
      await _open(tester, _container());

      expect(find.text('27.09. bis 03.10.2026, inklusive heute'), findsWidgets);
      expect(
        find.text('Vorherige 7 Tage: 20.09. bis 26.09.2026'),
        findsOneWidget,
      );
      expect(find.text('7 Tage'), findsOneWidget);
      expect(find.text('Als Tabelle'), findsOneWidget);
    });

    testWidgets('30 days: dates, previous period and comparison labels match '
        'the length, never "Vorwoche" (A01)', (tester) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      await _selectPeriod(tester, '30 Tage');

      expect(find.text('04.09. bis 03.10.2026, inklusive heute'), findsWidgets);
      expect(
        find.text('Vorherige 30 Tage: 05.08. bis 03.09.2026'),
        findsOneWidget,
      );
      expect(find.textContaining('vorherigen 30 Tagen'), findsWidgets);
      expect(find.textContaining('vorherigen 7 Tagen'), findsNothing);
      // The comparison of the period cards never calls the base a week.
      expect(
        find.descendant(
          of: find.byType(AdaptiveGrid),
          matching: find.textContaining('Vorwoche'),
        ),
        findsNothing,
      );
    });

    testWidgets('90 days: dates and previous period (A01)', (tester) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      await _selectPeriod(tester, '90 Tage');

      expect(find.text('06.07. bis 03.10.2026, inklusive heute'), findsWidgets);
      expect(
        find.text('Vorherige 90 Tage: 07.04. bis 05.07.2026'),
        findsOneWidget,
      );
      expect(find.textContaining('vorherigen 90 Tagen'), findsWidgets);
    });

    testWidgets('the selector announces the selected period (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container());

      final selected = tester.getSemantics(
        find.bySemanticsLabel('Zeitraum 7 Tage'),
      );
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      final other = tester.getSemantics(
        find.bySemanticsLabel('Zeitraum 30 Tage'),
      );
      expect(other.flagsCollection.isSelected, Tristate.isFalse);

      await _selectPeriod(tester, '30 Tage');
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Zeitraum 30 Tage'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('the period survives a rebuilt widget tree and a rotation '
        '(Q02)', (tester) async {
      final container = _container();
      await _open(tester, container);
      await _selectPeriod(tester, '90 Tage');

      // The widget tree is thrown away and built again (the container lives
      // on, as the provider scope does in the app).
      await tester.pumpWidget(const SizedBox());
      await _open(tester, container);
      expect(find.text('06.07. bis 03.10.2026, inklusive heute'), findsWidgets);

      // Rotation: the same tree at another size.
      await _open(tester, container, size: const Size(852, 393));
      expect(find.text('06.07. bis 03.10.2026, inklusive heute'), findsWidgets);
      expect(
        container.read(analysisPeriodProvider),
        AnalysisPeriodLength.days90,
      );
    });

    testWidgets('a new day moves the period (the provider follows today)', (
      tester,
    ) async {
      final clock = FakeClock.at(analysisNowIso);
      final container = _container(clock: clock);
      await _open(tester, container);
      expect(find.text('27.09. bis 03.10.2026, inklusive heute'), findsWidgets);

      clock.advance(const Duration(days: 1));
      container.read(todayProvider.notifier).refresh();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('28.09. bis 04.10.2026, inklusive heute'), findsWidgets);
    });
  });

  group('the cards show the figures of the engine (A01)', () {
    testWidgets('the hero counts complete days of the days with goals', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(find.text('Tagesziele komplett'), findsOneWidget);
      expect(
        find.text('3 von 6 Tage', findRichText: true, skipOffstage: false),
        findsNothing,
      );
      expect(find.textContaining('3 von 6', findRichText: true), findsWidgets);
      expect(find.text('5 von 6 Tagen aktiv'), findsOneWidget);
      expect(
        find.textContaining(
          t('+21~Prozentpunkte gegenüber den vorherigen 7 Tagen'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('steps: average over the recorded days with the coverage, '
        'a recorded zero counts, the comparison and the total (AT15)', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(_inCard('Schritte', find.text('7.000')), findsOneWidget);
      expect(_inCard('Schritte', find.text('Ø pro Tag')), findsOneWidget);
      // 5 of 7 days recorded, one of them an explicit 0 (Monday).
      expect(
        _inCard('Schritte', find.text('5/7 Tage erfasst')),
        findsNWidgets(2),
      );
      expect(
        _inCard(
          'Schritte',
          find.text(t('↑~+40~% (+2.000) gegenüber den vorherigen 7 Tagen')),
        ),
        findsOneWidget,
      );
      expect(_inCard('Schritte', find.text('35.000')), findsOneWidget);
    });

    testWidgets('water: average over the recorded days with the coverage', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(_inCard('Wasser', find.text(t('1,69~l'))), findsOneWidget);
      expect(
        _inCard('Wasser', find.text('4/7 Tage erfasst')),
        findsNWidgets(2),
      );
      expect(
        _inCard(
          'Wasser',
          find.text(t('↑~+13~% (+0,19~l) gegenüber den vorherigen 7 Tagen')),
        ),
        findsOneWidget,
      );
      expect(_inCard('Wasser', find.text(t('6,75~l'))), findsOneWidget);
    });

    testWidgets('weight: the change from the first to the last measured day '
        '(AT08)', (tester) async {
      await _open(tester, _container());

      expect(_inCard('Gewicht', find.text(t('−0,3~kg'))), findsOneWidget);
      expect(
        _inCard('Gewicht', find.text('3/7 Tage gemessen')),
        findsNWidgets(2),
      );
      expect(
        _inCard(
          'Gewicht',
          find.text(
            'Von ${t('71,8~kg')} (27.09.) auf ${t('71,5~kg')} (03.10.)',
          ),
        ),
        findsOneWidget,
      );
      expect(_inCard('Gewicht', find.text(t('71,5~kg'))), findsOneWidget);
    });

    testWidgets('workouts, focus time, tasks and habits', (tester) async {
      await _open(tester, _container());

      expect(_inCard('Workouts', find.text('3')), findsOneWidget);
      expect(_inCard('Workouts', find.text(t('2~h 15~min'))), findsOneWidget);
      expect(_inCard('Fokuszeit', find.text(t('1~h 5~min'))), findsOneWidget);
      expect(
        _inCard(
          'Fokuszeit',
          find.text(
            'Es zählen nur abgeschlossene Sitzungen. Workouts sind keine '
            'Fokuszeit.',
          ),
        ),
        findsOneWidget,
      );
      expect(_inCard('Aufgaben', find.text('6')), findsOneWidget);
      expect(_inCard('Gewohnheiten', find.text(t('75~%'))), findsOneWidget);
      expect(
        _inCard('Gewohnheiten', find.text('6 von 8 Habit-Tagen erfüllt')),
        findsOneWidget,
      );
      expect(
        _inCard(
          'Gewohnheiten',
          find.text(t('↑~+46~Prozentpunkte gegenüber den vorherigen 7 Tagen')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('meals: known calories with the completeness state (AT14)', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(_inCard('Mahlzeiten', find.text('5')), findsOneWidget);
      expect(_inCard('Mahlzeiten', find.text(t('1.500~kcal'))), findsOneWidget);
      // The state is visible text with a glyph, not only a colour.
      expect(
        _inCard('Mahlzeiten', find.text('Kalorien unvollständig')),
        findsOneWidget,
      );
      expect(
        _inCard(
          'Mahlzeiten',
          find.textContaining('1 von 5 Mahlzeiten ohne Kalorienangabe'),
        ),
        findsOneWidget,
      );
      // Calories of an incomplete period are not compared with a complete one.
      expect(
        _inCard('Mahlzeiten', find.text('Noch kein Vergleich')),
        findsOneWidget,
      );
    });

    testWidgets('the cards follow the order of the design', (tester) async {
      await _open(tester, _container());

      double top(String title) => tester.getTopLeft(_card(title)).dy;
      expect(top('Schritte'), lessThan(top('Workouts')));
      expect(top('Workouts'), lessThan(top('Aufgaben')));
      expect(top('Aufgaben'), lessThan(top('Gewicht')));
      expect(
        tester.getTopLeft(_card('Schritte')).dx,
        lessThan(tester.getTopLeft(_card('Wasser')).dx),
      );
    });
  });

  group('honest states: no data, no comparison, no invented values (A01)', () {
    testWidgets('a new user sees "Noch kein Vergleich" and the date from which '
        'a comparison is possible (A01)', (tester) async {
      await _open(tester, _container(usageStart: d2026(10, 1)));

      expect(
        find.text(
          'Ein Vergleich mit den vorherigen 7 Tagen ist ab dem 14.10.2026 '
          'möglich.',
        ),
        findsOneWidget,
      );
      expect(find.text('Noch kein Vergleich'), findsWidgets);
      // No card claims a change against a period that is not fully inside
      // the usage window, and none repeats the reason that the note gives.
      expect(find.textContaining('gegenüber den vorherigen'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AdaptiveGrid),
          matching: find.textContaining('Nutzungszeit'),
        ),
        findsNothing,
      );
      // The week has its own comparison base and says why it has none.
      expect(
        _inCard('Workouts diese Woche', find.textContaining('Nutzungszeit')),
        findsOneWidget,
      );
      // The figures of the current period are still shown.
      expect(_inCard('Schritte', find.text('7.000')), findsOneWidget);
    });

    testWidgets('an unknown usage start gives no comparison either (A01)', (
      tester,
    ) async {
      await _open(tester, _container(noUsageStart: true));

      expect(find.textContaining('gegenüber den vorherigen'), findsNothing);
      // Said once in the note, not again on the week card.
      expect(
        find.text('Der Nutzungsstart ist noch nicht bekannt.'),
        findsOneWidget,
      );
    });

    testWidgets('a previous period without data says why there is no '
        'comparison (A01)', (tester) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), stepsRecorded: 8000),
          ],
          modules: {ModuleId.body},
        ),
      );

      // The average and the total of the single recorded day.
      expect(_inCard('Schritte', find.text('8.000')), findsNWidgets(2));
      expect(
        _inCard('Schritte', find.text('1/7 Tage erfasst')),
        findsNWidgets(2),
      );
      expect(
        _inCard('Schritte', find.text('Noch kein Vergleich')),
        findsOneWidget,
      );
      expect(
        _inCard(
          'Schritte',
          find.text('Im Vergleichszeitraum liegen keine Daten vor.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('without any data the screen is honestly empty (A01)', (
      tester,
    ) async {
      await _open(tester, _container(days: const <AnalysisDay>[]));

      expect(find.text('Noch keine Daten'), findsOneWidget);
      expect(
        find.textContaining('In den letzten 7 Tagen wurde noch nichts erfasst'),
        findsOneWidget,
      );
      expect(find.byType(AdaptiveGrid), findsNothing);
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('Als Tabelle'), findsNothing);
      // The selector stays so the user can look at a longer period.
      expect(find.text('30 Tage'), findsOneWidget);
    });

    testWidgets('a metric without data says so and shows no zero (A01)', (
      tester,
    ) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), stepsRecorded: 8000),
          ],
        ),
      );

      for (final title in ['Wasser', 'Gewicht', 'Workouts', 'Aufgaben']) {
        expect(
          _inCard(title, find.text('Noch keine Daten')),
          findsOneWidget,
          reason: title,
        );
      }
      expect(find.text(t('0~l')), findsNothing);
      expect(find.text(t('0~kg')), findsNothing);
    });

    testWidgets('a recorded zero is data, a missing day is no zero: the '
        'average counts only the recorded days (AT15)', (tester) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(9, 28), stepsRecorded: 0),
            AnalysisDay(date: d2026(9, 30), stepsRecorded: 6000),
          ],
          modules: {ModuleId.body},
        ),
      );

      // (0 + 6000) / 2 recorded days, not / 7 days.
      expect(_inCard('Schritte', find.text('3.000')), findsOneWidget);
      expect(
        _inCard('Schritte', find.text('2/7 Tage erfasst')),
        findsNWidgets(2),
      );
      expect(_inCard('Schritte', find.text('6.000')), findsOneWidget);
    });

    testWidgets('a meal without calories is no zero: "Kalorien '
        'unvollständig" and no invented value (AT14)', (tester) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), mealEntries: 1, mealsWithKcal: 0),
          ],
          modules: {ModuleId.nutrition},
        ),
      );

      expect(
        _inCard('Mahlzeiten', find.text('Kalorien unvollständig')),
        findsOneWidget,
      );
      expect(
        _inCard('Mahlzeiten', find.text('Bekannte Kalorien')),
        findsOneWidget,
      );
      expect(find.textContaining('kcal'), findsNothing);
      expect(
        _inCard(
          'Mahlzeiten',
          find.textContaining('1 von 1 Mahlzeit ohne Kalorienangabe'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('only complete calories show no warning (AT14)', (
      tester,
    ) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(
              date: d2026(10, 3),
              mealEntries: 2,
              mealsWithKcal: 2,
              knownKcal: 900,
            ),
          ],
          modules: {ModuleId.nutrition},
        ),
      );

      expect(_inCard('Mahlzeiten', find.text(t('900~kcal'))), findsOneWidget);
      expect(find.text('Kalorien unvollständig'), findsNothing);
    });

    testWidgets('there is no sleep, no distance and no invented number '
        'anywhere (A01)', (tester) async {
      await _open(tester, _container());

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .join(' ')
          .toLowerCase();
      for (final forbidden in [
        'schlaf',
        'kilometer',
        ' km',
        'distanz',
        'aktivminuten',
      ]) {
        expect(texts.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    testWidgets('a weight of one single day has no change yet (AT08)', (
      tester,
    ) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), weightGrams: 71500),
          ],
          modules: {ModuleId.body},
        ),
      );

      // The last value leads, the change says there is none yet.
      expect(_inCard('Gewicht', find.text(t('71,5~kg'))), findsOneWidget);
      expect(
        _inCard('Gewicht', find.text('Noch kein Vergleich')),
        findsWidgets,
      );
      expect(
        _inCard('Gewicht', find.text('Eine Messung: ${t('71,5~kg')} (03.10.)')),
        findsOneWidget,
      );
    });
  });

  group('the workout week card (AT20)', () {
    testWidgets('week to date against the same weekdays of the previous week '
        '(AT20)', (tester) async {
      await _open(tester, _container());

      const title = 'Workouts diese Woche';
      expect(find.text(title), findsOneWidget);
      expect(
        _inCard(title, find.text('28.09. bis 03.10.2026, bis heute')),
        findsOneWidget,
      );
      expect(
        _inCard(title, find.text('Vorwoche: 21.09. bis 26.09.2026')),
        findsOneWidget,
      );
      expect(
        _inCard(title, find.text('3 von 3 Workouts, Wochenziel erreicht')),
        findsOneWidget,
      );
      expect(_inCard(title, find.text(t('2~h 15~min'))), findsOneWidget);
      // A week to date is compared with a week to date, and says so.
      expect(
        _inCard(
          title,
          find.text(t('↑~+50~% (+1) gegenüber der Vorwoche (Mo bis Sa)')),
        ),
        findsOneWidget,
      );
      expect(
        _inCard(
          title,
          find.text(t('↑~+50~% (+45~min) gegenüber der Vorwoche (Mo bis Sa)')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('on a Monday the week card compares Monday with Monday, never '
        'a partial week with a whole one (AT20)', (tester) async {
      final container = _container(
        clock: FakeClock.at('2026-10-05T08:00:00Z'),
        days: <AnalysisDay>[
          // Monday of the previous week had a workout, today has none yet.
          AnalysisDay(
            date: d2026(9, 28),
            workoutEntries: 1,
            workoutMinutes: 40,
          ),
          // A later day of the previous week must not count against today.
          AnalysisDay(
            date: d2026(10, 1),
            workoutEntries: 2,
            workoutMinutes: 90,
          ),
        ],
      );
      await _open(tester, container);

      const title = 'Workouts diese Woche';
      expect(
        _inCard(title, find.text('05.10.2026, bis heute')),
        findsOneWidget,
      );
      expect(_inCard(title, find.text('Vorwoche: 28.09.2026')), findsOneWidget);
      expect(_inCard(title, find.text('0 von 3 Workouts')), findsOneWidget);
      // Only the Monday of the previous week is the base (1 workout), so the
      // week to date has nothing to compare and says so.
      expect(_inCard(title, find.text('Noch kein Vergleich')), findsWidgets);
    });

    testWidgets('the week card does not depend on the selected period', (
      tester,
    ) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      List<String> weekTexts() => tester
          .widgetList<Text>(
            find.descendant(
              of: _card('Workouts diese Woche'),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .toList();

      final before = weekTexts();
      await _selectPeriod(tester, '90 Tage');
      expect(weekTexts(), before);
    });

    testWidgets('without a weekly target there is no ring, the real number '
        'stays (AT20)', (tester) async {
      await _open(tester, _container(weeklyTarget: null));

      const title = 'Workouts diese Woche';
      expect(_inCard(title, find.text('3 Workouts')), findsOneWidget);
      expect(_inCard(title, find.byType(ProgressRing)), findsNothing);
    });

    testWidgets('more workouts than the target: the ring is full, the number '
        'is real (AT20)', (tester) async {
      await _open(tester, _container(weeklyTarget: 2));

      const title = 'Workouts diese Woche';
      expect(
        _inCard(title, find.text('3 Workouts, Wochenziel 2 erreicht')),
        findsOneWidget,
      );
      final ring = tester.widget<ProgressRing>(
        _inCard(title, find.byType(ProgressRing)),
      );
      expect(ring.value, 1.0);
    });
  });

  group('module filter: only active modules are analysed (AT03)', () {
    const cardsOf = <ModuleId, List<String>>{
      ModuleId.body: ['Schritte', 'Gewicht'],
      ModuleId.nutrition: ['Wasser', 'Mahlzeiten'],
      ModuleId.focus: ['Workouts', 'Fokuszeit'],
      ModuleId.tasks: ['Aufgaben', 'Gewohnheiten'],
    };

    for (final entry in cardsOf.entries) {
      testWidgets('only the ${entry.key.name} module: its cards and nothing '
          'of the others (AT03)', (tester) async {
        await _open(tester, _container(modules: {entry.key}));

        for (final other in cardsOf.entries) {
          for (final title in other.value) {
            expect(
              find.text(title),
              other.key == entry.key ? findsOneWidget : findsNothing,
              reason: '$title with only ${entry.key.name}',
            );
          }
        }
        // The week card and the workout chart belong to the focus module.
        expect(
          find.text('Workouts diese Woche'),
          entry.key == ModuleId.focus ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('the charts follow the active modules (AT03)', (tester) async {
      await _open(tester, _container(modules: {ModuleId.body}));

      expect(find.text('Schritte pro Tag'), findsOneWidget);
      expect(find.text('Gewicht, letzter Wert des Tages'), findsOneWidget);
      expect(find.text('Wasser pro Tag'), findsNothing);
      expect(find.text('Workouts pro Tag'), findsNothing);
      expect(find.text('Erledigte Aufgaben pro Tag'), findsNothing);
    });

    testWidgets('all modules off: a clear empty state with the way to the '
        'module manager (AT04)', (tester) async {
      final container = _container(modules: <ModuleId>{});
      await pumpRouterApp(
        tester,
        routes: <RouteBase>[
          GoRoute(
            path: '/analysis',
            builder: (context, state) => const AnalysisScreen(),
          ),
          GoRoute(
            path: '/settings/modules',
            builder: (context, state) =>
                const Scaffold(body: Center(child: Text('Modulverwaltung'))),
          ),
        ],
        initialLocation: '/analysis',
        container: container,
      );

      expect(find.text('Kein Modul für die Analyse aktiv'), findsOneWidget);
      expect(find.text('Schritte'), findsNothing);
      expect(find.text('7 Tage'), findsNothing);

      await tester.tap(find.text('Module verwalten'));
      await tester.pumpAndSettle();
      expect(find.text('Modulverwaltung'), findsOneWidget);
    });

    testWidgets('only the progress module is on: nothing to analyse, the same '
        'way out (AT04)', (tester) async {
      await _open(tester, _container(modules: {ModuleId.gamification}));

      expect(find.text('Kein Modul für die Analyse aktiv'), findsOneWidget);
      expect(find.text('Module verwalten'), findsOneWidget);
    });
  });

  group('loading, error with retry and a changing period', () {
    testWidgets('while the report loads a neutral text shows, no numbers', (
      tester,
    ) async {
      final never = StreamController<AnalysisReport>();
      addTearDown(() => unawaited(never.close()));
      await _open(tester, _container(stream: (call, report) => never.stream));

      expect(find.text('Wird geladen …'), findsOneWidget);
      expect(find.text('7 Tage'), findsOneWidget);
      expect(find.text('Schritte'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an error shows the error state, retry reads again and the '
        'data appears (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      final container = _container(
        stream: (call, report) => call == 1
            ? Stream<AnalysisReport>.error(StateError('database failed'))
            : Stream<AnalysisReport>.value(report),
      );
      await _open(tester, container);

      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      expect(find.textContaining('database failed'), findsNothing);
      expect(find.text('Schritte'), findsNothing);
      // The error is announced as soon as it appears.
      expect(
        tester
            .getSemantics(find.text('Daten konnten nicht geladen werden'))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      // The selector stays usable.
      expect(find.text('30 Tage'), findsOneWidget);

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
      expect(_inCard('Schritte', find.text('7.000')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('while another period loads the previous report stays, marked '
        'as updating (Q02)', (tester) async {
      late StreamController<AnalysisReport> pending;
      AnalysisReport? next;
      final container = _container(
        stream: (call, report) {
          if (call == 1) {
            return Stream<AnalysisReport>.value(report);
          }
          next = report;
          pending = StreamController<AnalysisReport>();
          addTearDown(() => unawaited(pending.close()));
          return pending.stream;
        },
      );
      await _open(tester, container);
      await _selectPeriod(tester, '30 Tage');

      // The selector already shows 30 days, the content is still the old one,
      // honestly labelled.
      expect(find.text('Wird aktualisiert …'), findsOneWidget);
      expect(find.text('27.09. bis 03.10.2026, inklusive heute'), findsWidgets);
      expect(_inCard('Schritte', find.text('7.000')), findsOneWidget);

      pending.add(next!);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Wird aktualisiert …'), findsNothing);
      expect(find.text('04.09. bis 03.10.2026, inklusive heute'), findsWidgets);
    });
  });

  group('charts with a text summary and a table alternative (AT34)', () {
    testWidgets('every chart has its summary and a table of the same days '
        '(AT34)', (tester) async {
      await _open(tester, _container());

      const summary =
          'Schritte pro Tag, 27.09. bis 03.10.2026, inklusive heute. An 5 '
          'von 7 Tagen erfasst.';
      expect(find.textContaining(summary), findsOneWidget);
      // Each of the seven series has a summary and a toggle for its table.
      expect(find.text('Als Tabelle anzeigen'), findsNWidgets(7));

      final steps = find
          .ancestor(
            of: find.text('Schritte pro Tag'),
            matching: find.byType(ChartSummary),
          )
          .first;
      await tester.tap(
        find.descendant(of: steps, matching: find.text('Als Tabelle anzeigen')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // One row per day, oldest first; a day without a record reads "Nicht
      // erfasst", a recorded zero reads 0.
      expect(
        find.descendant(of: steps, matching: find.text('So, 27.09.')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: steps, matching: find.text('Sa, 03.10.')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: steps, matching: find.text('Nicht erfasst')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: steps, matching: find.text('8.000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: steps, matching: find.text('0')),
        findsOneWidget,
      );
    });

    testWidgets('a chart is hidden from screen readers, summary and table '
        'carry the meaning (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container());

      for (final chart in tester.widgetList(find.byType(BarChart))) {
        expect(chart, isA<BarChart>());
      }
      expect(
        find.ancestor(
          of: find.byType(BarChart).first,
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      expect(
        find.ancestor(
          of: find.byType(LineChart),
          matching: find.byType(ExcludeSemantics),
        ),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('steps and water: not recorded is an empty slot, a recorded '
        'zero a thin stub (A01)', (tester) async {
      await _open(tester, _container());

      final steps = tester.widget<BarChart>(find.byType(BarChart).first).data;
      double heightOf(int day) => steps.barGroups[day].barRods.first.toY;
      expect(steps.barGroups, hasLength(7));
      expect(heightOf(0), 8000); // Sunday 27.09.
      expect(heightOf(1), greaterThan(0)); // Monday: a recorded 0
      expect(heightOf(1), lessThan(steps.maxY * 0.05));
      expect(heightOf(2), 0); // Tuesday: not recorded, no bar
      expect(heightOf(3), 12000);
      // The dashed line is the average per recorded day.
      expect(steps.extraLinesData.horizontalLines.single.y, 7000);
    });

    testWidgets('weight: only measured days are points, no zero fill (AT08)', (
      tester,
    ) async {
      await _open(tester, _container());

      final line = tester.widget<LineChart>(find.byType(LineChart)).data;
      final spots = line.lineBarsData.single.spots;
      expect(
        [for (final spot in spots) (spot.x, spot.y)],
        [(0.0, 71.8), (3.0, 71.6), (6.0, 71.5)],
      );
    });

    testWidgets('a 90 day period draws 90 days and keeps its tables '
        '(Q03)', (tester) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      await _selectPeriod(tester, '90 Tage');

      final steps = tester.widget<BarChart>(find.byType(BarChart).first).data;
      expect(steps.barGroups, hasLength(90));
      expect(find.text('Als Tabelle anzeigen'), findsNWidgets(7));
    });

    testWidgets('the expanded table of a chart survives a period change', (
      tester,
    ) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      final steps = find
          .ancestor(
            of: find.text('Schritte pro Tag'),
            matching: find.byType(ChartSummary),
          )
          .first;
      await tester.tap(
        find.descendant(of: steps, matching: find.text('Als Tabelle anzeigen')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Tabelle ausblenden'), findsOneWidget);

      await _selectPeriod(tester, '30 Tage');
      expect(find.text('Tabelle ausblenden'), findsOneWidget);
    });
  });

  group('the table alternative opens and closes', () {
    testWidgets('"Als Tabelle" opens the table page, back returns', (
      tester,
    ) async {
      await _open(tester, _container());

      await tester.tap(find.text('Als Tabelle'));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisTableScreen), findsOneWidget);
      expect(find.text('Analyse als Tabelle'), findsOneWidget);

      await tester.tap(find.byIcon(AppIcon.back.data));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisTableScreen), findsNothing);
      expect(find.text('Als Tabelle'), findsOneWidget);
    });

    testWidgets('Android back closes the table page', (tester) async {
      await _open(tester, _container());
      await tester.tap(find.text('Als Tabelle'));
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisTableScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AnalysisTableScreen), findsNothing);
    });

    testWidgets('the table shows the period that is selected', (tester) async {
      await _open(tester, _container(days: syntheticDays(today: refToday)));
      await _selectPeriod(tester, '30 Tage');

      await tester.tap(find.text('Als Tabelle'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Kennzahlen der letzten 30 Tage'),
        findsOneWidget,
      );
    });
  });
}
