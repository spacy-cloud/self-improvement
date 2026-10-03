import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../analysis_test_support.dart';

const Size _tall = Size(393, 4200);

String t(String text) => text.replaceAll('~', ' ');

AnalysisReport _report({
  AnalysisPeriodLength length = AnalysisPeriodLength.days7,
  Set<ModuleId>? modules,
  List<AnalysisDay>? days,
}) => buildAnalysisReport(
  period: refPeriod(length),
  days: days ?? referenceDays(),
  usageStart: refUsageStart,
  activeModules: modules ?? ModuleId.values.toSet(),
);

ProviderContainer _container({
  AnalysisPeriodLength length = AnalysisPeriodLength.days7,
  List<AnalysisDay>? days,
  Set<ModuleId>? modules,
  LocalDate? usageStart,
  ReportStream? stream,
}) {
  final container = analysisContainer(
    days: days,
    modules: modules,
    usageStart: usageStart,
    stream: stream ?? (call, report) => Stream<AnalysisReport>.value(report),
  );
  container.read(analysisPeriodProvider.notifier).select(length);
  addTearDown(container.dispose);
  return container;
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = _tall,
  double textScale = 1.0,
}) => pumpApp(
  tester,
  const AnalysisTableScreen(),
  container: container,
  size: size,
  textScale: textScale,
);

void main() {
  group('the period table has the same figures as the cards (A01)', () {
    testWidgets(
      'every figure of the cards is a row with its label and spoken sentence (AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _open(tester, _container());
        final report = _report();

        for (final figure in report.table.periodTable.rows) {
          expect(
            find.text(figure.tableLabel),
            findsOneWidget,
            reason: figure.key,
          );
          // The row is one block for screen readers: the sentence of the engine.
          expect(
            find.bySemanticsLabel(figure.spokenText),
            findsOneWidget,
            reason: figure.key,
          );
        }
        // Every card figure of the report is in the table.
        expect(
          report.table.periodTable.rows.map((figure) => figure.key),
          report.cards.expand((card) => card.figures).map((f) => f.key),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'the columns name the periods and show current, previous and change',
      (tester) async {
        await _open(tester, _container());

        expect(find.text('Letzte 7 Tage'), findsOneWidget);
        expect(find.text('Vorherige 7 Tage'), findsOneWidget);
        // One header row for the periods and one for the workout week.
        expect(find.text('Veränderung'), findsNWidgets(2));
        expect(find.text('7.000'), findsOneWidget);
        expect(find.text('5.000'), findsOneWidget);
        expect(find.text(t('+40~% (+2.000)')), findsOneWidget);
        // Figures that are not compared (totals) show a dash as the change.
        expect(find.text('–'), findsWidgets);
      },
    );

    testWidgets('the caption names both periods with their dates (A01)', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(
        find.text(
          'Kennzahlen der letzten 7 Tage (27.09. bis 03.10.2026, inklusive '
          'heute) im Vergleich mit den vorherigen 7 Tagen (20.09. bis '
          '26.09.2026)',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the coverage of both periods is part of the table (A01)', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(find.text('Erfassung: 5/7 Tage erfasst'), findsWidgets);
      expect(find.text('Vorherige 7 Tage: 3/7 Tage erfasst'), findsWidgets);
      expect(find.text('Erfassung: 3/7 Tage gemessen'), findsWidgets);
    });

    testWidgets(
      '30 and 90 days: the headers and the caption follow the length (A01)',
      (tester) async {
        for (final length in [
          AnalysisPeriodLength.days30,
          AnalysisPeriodLength.days90,
        ]) {
          final container = _container(
            length: length,
            days: syntheticDays(today: refToday),
          );
          await _open(tester, container);

          expect(find.text('Letzte ${length.days} Tage'), findsOneWidget);
          expect(find.text('Vorherige ${length.days} Tage'), findsOneWidget);
          expect(
            find.textContaining(
              'im Vergleich mit den vorherigen ${length.days}',
            ),
            findsOneWidget,
          );
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('a figure without a comparison says why, once per row (A01)', (
      tester,
    ) async {
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), stepsRecorded: 8000),
          ],
          modules: {ModuleId.body},
        ),
      );

      expect(find.text('Noch kein Vergleich'), findsWidgets);
      expect(
        find.text('Im Vergleichszeitraum liegen keine Daten vor.'),
        findsWidgets,
      );
    });

    testWidgets(
      'a new user: the note once above, the rows only say "Noch kein Vergleich" (A01)',
      (tester) async {
        await _open(tester, _container(usageStart: d2026(10, 1)));

        expect(
          find.text(
            'Ein Vergleich mit den vorherigen 7 Tagen ist ab dem 14.10.2026 '
            'möglich.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Nutzungszeit'), findsNothing);
        expect(find.text('Noch kein Vergleich'), findsWidgets);
      },
    );
  });

  group('the workout week table and the values per day (AT20)', () {
    testWidgets(
      'the week table compares week to date with week to date (AT20)',
      (tester) async {
        await _open(tester, _container());

        expect(
          find.text(
            'Workouts diese Woche (28.09. bis 03.10.2026, bis heute) im '
            'Vergleich mit der Vorwoche (Vorwoche: 21.09. bis 26.09.2026)',
          ),
          findsOneWidget,
        );
        expect(find.text('Diese Woche (Mo bis Sa)'), findsOneWidget);
        expect(find.text('Vorwoche (Mo bis Sa)'), findsOneWidget);
        expect(find.text('Workouts diese Woche, Anzahl'), findsOneWidget);
        expect(find.text('Erfassung: Wochenziel erreicht'), findsNothing);
        expect(find.text('Wochenziel: Wochenziel 3 erreicht'), findsOneWidget);
      },
    );

    testWidgets(
      'the days are behind a toggle and list every day with its values (A01)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _open(tester, _container());

        expect(find.text('Werte pro Tag'), findsOneWidget);
        expect(find.text('Di, 29.09.'), findsNothing);
        final toggle = find.bySemanticsLabel('Werte pro Tag anzeigen');
        expect(
          tester.getSemantics(toggle).flagsCollection.isExpanded,
          Tristate.isFalse,
        );

        await tester.tap(find.text('Werte pro Tag anzeigen'));
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Werte pro Tag ausblenden'))
              .flagsCollection
              .isExpanded,
          Tristate.isTrue,
        );
        // Seven days, oldest first, each one block for screen readers.
        final report = _report();
        for (final row in report.table.dayTable.rows) {
          expect(find.text(row.dayText), findsOneWidget, reason: row.dayText);
          expect(
            find.bySemanticsLabel(row.semanticsLabel),
            findsOneWidget,
            reason: row.semanticsLabel,
          );
        }
        // A day without a record reads "Nicht erfasst", not 0.
        expect(find.textContaining('Nicht erfasst'), findsWidgets);
        expect(
          find.bySemanticsLabel(
            RegExp(r'Dienstag, 29\.09\.2026: Schritte nicht erfasst'),
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('only the active modules have columns per day (AT03)', (
      tester,
    ) async {
      await _open(tester, _container(modules: {ModuleId.body}));
      await tester.tap(find.text('Werte pro Tag anzeigen'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Schritte'), findsWidgets);
      expect(find.textContaining('Wasser'), findsNothing);
      expect(find.textContaining('Mahlzeiten'), findsNothing);
      expect(find.textContaining('Fokuszeit'), findsNothing);
      // No workout week without the focus module.
      expect(find.textContaining('Workouts diese Woche'), findsNothing);
    });
  });

  group('large text and narrow phones keep the table readable (Q02)', () {
    testWidgets('at 200 % text every row is a block of labelled lines (Q02)', (
      tester,
    ) async {
      await _open(tester, _container(), textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.text('Letzte 7 Tage: 7.000'), findsOneWidget);
      expect(find.text('Vorherige 7 Tage: 5.000'), findsOneWidget);
      expect(find.text(t('Veränderung: +40~% (+2.000)')), findsOneWidget);
    });

    testWidgets(
      'a 320 px phone switches to blocks before a word would break (Q02)',
      (tester) async {
        await _open(tester, _container(), size: const Size(320, 4200));

        expect(tester.takeException(), isNull);
        expect(find.text('Letzte 7 Tage: 7.000'), findsOneWidget);
      },
    );

    testWidgets('a 360 px phone keeps the columns (Q02)', (tester) async {
      await _open(tester, _container(), size: const Size(360, 4200));

      expect(tester.takeException(), isNull);
      expect(find.text('Letzte 7 Tage'), findsOneWidget);
      expect(find.text('Letzte 7 Tage: 7.000'), findsNothing);
    });
  });

  group('states of the table page', () {
    testWidgets('loading shows a neutral text', (tester) async {
      final never = StreamController<AnalysisReport>();
      addTearDown(() => unawaited(never.close()));
      await _open(tester, _container(stream: (call, report) => never.stream));

      expect(find.text('Wird geladen …'), findsOneWidget);
    });

    testWidgets('an error offers a retry that reads the report again', (
      tester,
    ) async {
      final container = _container(
        stream: (call, report) => call == 1
            ? Stream<AnalysisReport>.error(StateError('db'))
            : Stream<AnalysisReport>.value(report),
      );
      await _open(tester, container);

      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Letzte 7 Tage'), findsOneWidget);
    });

    testWidgets('without cards there is no empty table, only a note', (
      tester,
    ) async {
      await _open(tester, _container(modules: <ModuleId>{}));

      expect(find.text('Noch keine Tabelle'), findsOneWidget);
      expect(find.text('Letzte 7 Tage'), findsNothing);
    });

    testWidgets('the footnote tells that screen readers read it row by row', (
      tester,
    ) async {
      await _open(tester, _container());

      expect(
        find.text(
          'Die Tabelle ist die zugängliche Alternative zu den Diagrammen und '
          'wird vom Screenreader zeilenweise vorgelesen.',
        ),
        findsOneWidget,
      );
    });
  });
}
