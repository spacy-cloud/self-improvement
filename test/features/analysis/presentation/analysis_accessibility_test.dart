import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/analysis/application/analysis_providers.dart';
import 'package:self_improvement/core/analysis/domain/analysis_day.dart';
import 'package:self_improvement/core/analysis/domain/analysis_figures.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_metric_card.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_screen.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_table_screen.dart';
import 'package:self_improvement/features/analysis/presentation/analysis_widgets.dart';

import '../../../support/pump_app.dart';
import '../analysis_test_support.dart';

ProviderContainer _container({
  List<AnalysisDay>? days,
  Set<ModuleId>? modules,
  AnalysisPeriodLength length = AnalysisPeriodLength.days7,
  ReportStream? stream,
}) {
  final container = analysisContainer(
    days: days,
    modules: modules,
    stream: stream ?? (call, report) => Stream<AnalysisReport>.value(report),
  );
  container.read(analysisPeriodProvider.notifier).select(length);
  addTearDown(container.dispose);
  return container;
}

Future<void> _open(
  WidgetTester tester,
  ProviderContainer container, {
  Widget screen = const AnalysisScreen(),
  Size size = const Size(393, 852),
  double textScale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  bool reducedMotion = false,
}) => pumpApp(
  tester,
  screen,
  container: container,
  size: size,
  textScale: textScale,
  theme: theme,
  reducedMotion: reducedMotion,
);

void main() {
  group('responsive layout at 320, 360, 393 and 430 px (Q02, AT33)', () {
    for (final size in responsiveSizes) {
      for (final scale in [1.0, 2.0]) {
        final name = '${size.width.toInt()} px at ${(scale * 100).toInt()} %';

        testWidgets('the analysis tab fits $name for 7, 30 and 90 days (Q02)', (
          tester,
        ) async {
          for (final length in AnalysisPeriodLength.values) {
            final container = _container(
              days: syntheticDays(today: refToday),
              length: length,
            );
            await _open(tester, container, size: size, textScale: scale);
            await tester.pump(const Duration(milliseconds: 300));
            expect(
              tester.takeException(),
              isNull,
              reason: '${length.days} days at $name',
            );
            await tester.pumpWidget(const SizedBox());
          }
        });

        testWidgets('the reference week fits $name (Q02)', (tester) async {
          await _open(tester, _container(), size: size, textScale: scale);
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
        });

        testWidgets('the table page fits $name, also with its days (Q02)', (
          tester,
        ) async {
          await _open(
            tester,
            _container(days: syntheticDays(today: refToday)),
            screen: const AnalysisTableScreen(),
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Werte pro Tag anzeigen'));
          await tester.tap(find.text('Werte pro Tag anzeigen'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        });

        testWidgets('the states fit $name (Q02)', (tester) async {
          for (final (label, container) in <(String, ProviderContainer)>[
            ('empty', _container(days: const <AnalysisDay>[])),
            ('no modules', _container(modules: <ModuleId>{})),
            (
              'error',
              _container(
                stream: (call, report) =>
                    Stream<AnalysisReport>.error(StateError('db')),
              ),
            ),
            (
              'new user',
              analysisContainer(usageStart: d2026(10, 1))
                ..read(analysisPeriodProvider.notifier)
                    .select(AnalysisPeriodLength.days90),
            ),
          ]) {
            addTearDown(container.dispose);
            await _open(tester, container, size: size, textScale: scale);
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull, reason: '$label at $name');
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }

    testWidgets('two columns at normal text, one column from 130 % on, one '
        'column on the narrowest phone (Q02)', (tester) async {
      Future<double> secondCardX(Size size, double scale) async {
        await _open(
          tester,
          _container(),
          size: Size(size.width, 4600),
          textScale: scale,
        );
        final cards = find.byType(AnalysisMetricCard);
        final x = tester.getTopLeft(cards.at(1)).dx;
        await tester.pumpWidget(const SizedBox());
        return x;
      }

      // First card at x = 16: the second one sits to its right or below it.
      expect(await secondCardX(const Size(393, 0), 1.0), greaterThan(100));
      expect(await secondCardX(const Size(360, 0), 1.0), greaterThan(100));
      expect(await secondCardX(const Size(430, 0), 1.0), greaterThan(100));
      expect(await secondCardX(const Size(393, 0), 1.3), greaterThan(100));
      expect(await secondCardX(const Size(393, 0), 1.5), 16);
      expect(await secondCardX(const Size(393, 0), 2.0), 16);
      expect(await secondCardX(const Size(320, 0), 1.0), 16);
    });
  });

  group('tap targets and labels (Q02, AT34)', () {
    for (final (name, size, scale) in <(String, Size, double)>[
      ('393 px', const Size(393, 852), 1.0),
      ('320 px at 200 %', const Size(320, 640), 2.0),
    ]) {
      testWidgets('the analysis tab meets the tap target and label '
          'guidelines at $name (Q02)', (tester) async {
        final handle = tester.ensureSemantics();
        await _open(
          tester,
          _container(days: syntheticDays(today: refToday)),
          size: size,
          textScale: scale,
        );

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('the table page meets the guidelines at $name, expanded '
          'too (Q02)', (tester) async {
        final handle = tester.ensureSemantics();
        await _open(
          tester,
          _container(),
          screen: const AnalysisTableScreen(),
          size: size,
          textScale: scale,
        );
        await tester.ensureVisible(find.text('Werte pro Tag anzeigen'));
        await tester.tap(find.text('Werte pro Tag anzeigen'));
        await tester.pump(const Duration(milliseconds: 100));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    testWidgets('the states meet the guidelines (Q02)', (tester) async {
      final handle = tester.ensureSemantics();
      for (final container in <ProviderContainer>[
        _container(modules: <ModuleId>{}),
        _container(
          stream: (call, report) =>
              Stream<AnalysisReport>.error(StateError('db')),
        ),
      ]) {
        await _open(tester, container);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await tester.pumpWidget(const SizedBox());
      }
      handle.dispose();
    });

    testWidgets('the chart toggles and the table link are buttons with a '
        'name (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container(), size: const Size(393, 4600));

      final link = tester.getSemantics(
        find.bySemanticsLabel('Analyse als Tabelle öffnen'),
      );
      expect(link.flagsCollection.isButton, isTrue);
      final toggles = find.bySemanticsLabel('Als Tabelle anzeigen');
      expect(toggles, findsNWidgets(7));
      expect(
        tester.getSemantics(toggles.first).flagsCollection.isButton,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('what a screen reader hears (AT34)', () {
    testWidgets('the period, every card, the strip and the week card are '
        'readable sentences (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container(), size: const Size(393, 4600));

      expect(
        find.bySemanticsLabel(
          'Zeitraum 7 Tage, 27.09. bis 03.10.2026, inklusive heute',
        ),
        findsOneWidget,
      );
      // The card of the steps: label, value, unit spelled out, coverage and
      // the comparison with its base, in one block.
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Schritte, Ø pro erfasstem Tag: 7\.000 Schritte, an 5 von 7 '
            r'Tagen erfasst\. Vorherige 7 Tage: 5\.000 Schritte, an 3 von 7 '
            r'Tagen erfasst\. plus 40 Prozent, plus 2\.000 Schritte '
            r'gegenüber den vorherigen 7 Tagen\.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Gewicht, Änderung vom ersten zum')),
        findsOneWidget,
      );
      // The strip names every day in words, so the ring colours are no cue.
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Tagesziele pro Tag: Sonntag, 27\.09\.2026: keine Tagesziele\. '
            r'Montag, 28\.09\.2026: 6 von 6 Tageszielen erfüllt, Tag komplett',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Workouts diese Woche, 28\.09\.')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a card without data is spoken as such, a missing comparison '
        'as "Noch kein Vergleich" (AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(
        tester,
        _container(
          days: <AnalysisDay>[
            AnalysisDay(date: d2026(10, 3), stepsRecorded: 8000),
          ],
        ),
        size: const Size(393, 4600),
      );

      expect(
        find.bySemanticsLabel('Wasser. Noch keine Daten.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Noch kein Vergleich')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('the incomplete calories are spoken with the card (AT14, '
        'AT34)', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container(), size: const Size(393, 4600));

      expect(
        find.bySemanticsLabel(RegExp(r'^Mahlzeiten, Anzahl: 5 Mahlzeiten')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Kalorien unvollständig\.')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('the summary of a chart is a readable text (AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _open(tester, _container(), size: const Size(393, 4600));

      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Schritte pro Tag, 27\.09\. bis 03\.10\.2026, inklusive heute\. '
            r'An 5 von 7 Tagen erfasst\.',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('themes and motion (Q03, AT35)', () {
    for (final theme in AppThemeVariant.values) {
      testWidgets('the analysis renders in ${theme.name} (Q03)', (
        tester,
      ) async {
        await _open(
          tester,
          _container(),
          size: const Size(393, 4600),
          theme: theme,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Tagesziele komplett'), findsOneWidget);
      });
    }

    testWidgets('with reduced motion the screen is complete at once (Q03)', (
      tester,
    ) async {
      await _open(
        tester,
        _container(),
        size: const Size(393, 4600),
        reducedMotion: true,
      );
      // No pump of an animation: everything is there after the first frame.
      expect(find.text('Tagesziele komplett'), findsOneWidget);
      await tester.tap(find.text('Als Tabelle anzeigen').first);
      await tester.pump();
      expect(find.text('Tabelle ausblenden'), findsOneWidget);
    });

    testWidgets('an increase and a decrease look the same: a change is '
        'neither good nor bad (Q03)', (tester) async {
      AnalysisFigure stepsOf(List<AnalysisDay> days) => buildAnalysisReport(
        period: refPeriod(AnalysisPeriodLength.days7),
        days: days,
        usageStart: refUsageStart,
        activeModules: {ModuleId.body},
      ).cards.first.figures.first;

      final up = stepsOf(<AnalysisDay>[
        AnalysisDay(date: d2026(9, 22), stepsRecorded: 4000),
        AnalysisDay(date: d2026(10, 1), stepsRecorded: 8000),
      ]);
      final down = stepsOf(<AnalysisDay>[
        AnalysisDay(date: d2026(9, 22), stepsRecorded: 8000),
        AnalysisDay(date: d2026(10, 1), stepsRecorded: 4000),
      ]);
      expect(up.changeText, startsWith('+'));
      expect(down.changeText, startsWith('\u2212'));

      Future<(Color?, Color?)> colorsOf(AnalysisFigure figure) async {
        await pumpApp(
          tester,
          Scaffold(body: ComparisonPill(figure: figure)),
          container: _container(),
        );
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(ComparisonPill),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final text = tester.widget<Text>(find.byType(Text).first);
        final span = text.textSpan! as TextSpan;
        return (
          (box.decoration as BoxDecoration).color,
          span.children!.last.style?.color,
        );
      }

      final upColors = await colorsOf(up);
      final downColors = await colorsOf(down);
      expect(upColors, downColors);
      expect(upColors.$1, isNotNull);
    });
  });
}
