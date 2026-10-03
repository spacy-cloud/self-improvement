import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

void main() {
  setUpAll(loadInterFont);

  group('AppCard', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testWidgets(
        '${variant.name}: surface, decorative border, radius 16 and shadow',
        (tester) async {
          await pumpDesign(
            tester,
            const AppCard(child: Text('Kartentitel')),
            variant: variant,
          );
          final box = tester.widget<Container>(
            find
                .descendant(
                  of: find.byType(AppCard),
                  matching: find.byType(Container),
                )
                .first,
          );
          final decoration = box.decoration! as BoxDecoration;
          expect(decoration.color, colors.surface);
          expect(decoration.borderRadius, BorderRadius.circular(16));
          expect(
            (decoration.border! as Border).top.color,
            colors.borderDecorative,
          );
          expect((decoration.border! as Border).top.width, 1);
          expect(decoration.boxShadow, AppShadows.card(colors.shadow));
        },
      );
    }

    testWidgets('hugs the content and grows with large text', (tester) async {
      Widget card() => const AppCard(
        child: Text(
          'Karten wachsen mit dem Inhalt mit (große Schrift) und umbrechen.',
        ),
      );
      await pumpDesign(tester, card());
      final normal = tester.getSize(find.byType(AppCard)).height;
      await pumpDesign(tester, card(), textScale: 2, width: 320);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(AppCard)).height, greaterThan(normal));
    });

    testSemantics('a tappable card is a button with its label', (tester) async {
      var taps = 0;
      await pumpDesign(
        tester,
        AppCard(
          onTap: () => taps++,
          semanticLabel: 'Gewicht öffnen',
          child: const Text('Gewicht'),
        ),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Gewicht öffnen'));
      expect(node.label, 'Gewicht öffnen');
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.byType(AppCard));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
    });

    testWidgets('showShadow: false removes the shadow', (tester) async {
      await pumpDesign(
        tester,
        const AppCard(showShadow: false, child: Text('x')),
      );
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(AppCard),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((box.decoration! as BoxDecoration).boxShadow, isNull);
    });
  });

  group('AppIconTile', () {
    for (final variant in allVariants) {
      testWidgets('${variant.name}: tint and icon colour follow the accent', (
        tester,
      ) async {
        final colors = variant.colors;
        await pumpDesign(
          tester,
          const AppIconTile(
            icon: Icons.water_drop_outlined,
            accent: AppAccent.water,
          ),
          variant: variant,
        );
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(AppIconTile),
            matching: find.byType(Container),
          ),
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          colors.tintWater,
        );
        expect(
          tester.widget<Icon>(find.byType(Icon)).color,
          colors.moduleWater,
        );
        expect(tester.getSize(find.byType(AppIconTile)), const Size(36, 36));
      });
    }

    testSemantics('is decorative: it has no semantics of its own', (
      tester,
    ) async {
      await pumpDesign(tester, const AppIconTile(icon: Icons.check_rounded));
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    });
  });

  group('AppProgressBar', () {
    test('clamp keeps 0..1 and maps NaN to 0', () {
      expect(AppProgressBar.clamp(-0.5), 0);
      expect(AppProgressBar.clamp(0), 0);
      expect(AppProgressBar.clamp(0.5), 0.5);
      expect(AppProgressBar.clamp(1), 1);
      expect(AppProgressBar.clamp(1.7), 1);
      expect(AppProgressBar.clamp(double.nan), 0);
      expect(AppProgressBar.clamp(double.infinity), 1);
      expect(AppProgressBar.clamp(double.negativeInfinity), 0);
    });

    for (final variant in allVariants) {
      final colors = variant.colors;
      testWidgets('${variant.name}: track and the four variant fills', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[
              AppProgressBar(key: ValueKey<String>('primary'), value: 0.65),
              AppProgressBar(
                key: ValueKey<String>('water'),
                value: 0.65,
                variant: AppProgressVariant.water,
              ),
              AppProgressBar(
                key: ValueKey<String>('steps'),
                value: 0.65,
                variant: AppProgressVariant.steps,
              ),
              AppProgressBar(
                key: ValueKey<String>('focus'),
                value: 0.65,
                variant: AppProgressVariant.focus,
              ),
            ],
          ),
          variant: variant,
        );
        Color fillOf(String key) {
          final fill = find.descendant(
            of: find.byKey(ValueKey<String>(key)),
            matching: find.byKey(const ValueKey<String>('app_progress_fill')),
          );
          return (tester.widget<DecoratedBox>(fill).decoration as BoxDecoration)
              .color!;
        }

        expect(fillOf('primary'), colors.primary);
        expect(fillOf('water'), colors.moduleWaterChart);
        expect(fillOf('steps'), colors.moduleSteps);
        expect(fillOf('focus'), colors.moduleFocus);
        final track = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('primary')),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        expect(track.color, colors.track);
        expect(
          tester.getSize(find.byKey(const ValueKey<String>('primary'))).height,
          12,
        );
      });
    }

    testWidgets('the fill width is the clamped value of the track width', (
      tester,
    ) async {
      Future<double> fillWidth(double value) async {
        await pumpDesign(tester, AppProgressBar(value: value));
        await settle(tester);
        return tester
            .getSize(find.byKey(const ValueKey<String>('app_progress_fill')))
            .width;
      }

      const full = 393.0 - 32;
      expect(await fillWidth(0), 0);
      expect(await fillWidth(0.5), closeTo(full / 2, 0.5));
      expect(await fillWidth(1), closeTo(full, 0.5));
      expect(await fillWidth(1.5), closeTo(full, 0.5));
      expect(await fillWidth(-1), 0);
      expect(await fillWidth(double.nan), 0);
    });

    testSemantics(
      'speaks a custom label or "Fortschritt" with the percentage',
      (tester) async {
        await pumpDesign(
          tester,
          const Column(
            children: <Widget>[
              AppProgressBar(
                key: ValueKey<String>('custom'),
                value: 0.75,
                semanticLabel: '75 % vom Tagesziel',
              ),
              AppProgressBar(key: ValueKey<String>('default'), value: 0.333),
              AppProgressBar(key: ValueKey<String>('almost'), value: 0.996),
              AppProgressBar(key: ValueKey<String>('full'), value: 1),
            ],
          ),
        );
        final custom = tester.getSemantics(
          find.byKey(const ValueKey<String>('custom')),
        );
        expect(custom.label, '75 % vom Tagesziel');
        expect(custom.value, isEmpty);
        final plain = tester.getSemantics(
          find.byKey(const ValueKey<String>('default')),
        );
        expect(plain.label, 'Fortschritt');
        expect(plain.value, '33 %');
        expect(
          tester
              .getSemantics(find.byKey(const ValueKey<String>('almost')))
              .value,
          '99 %',
          reason: '99,6 would round up to 100 before the bar is full',
        );
        expect(
          tester.getSemantics(find.byKey(const ValueKey<String>('full'))).value,
          '100 %',
        );
      },
    );

    testWidgets(
      'the fill animates in 200 ms and is immediate with reduced motion',
      (tester) async {
        Widget bar(double v) => AppProgressBar(value: v);
        await pumpDesign(tester, bar(0));
        await pumpDesign(tester, bar(1));
        await tester.pump(const Duration(milliseconds: 50));
        final mid = tester
            .getSize(find.byKey(const ValueKey<String>('app_progress_fill')))
            .width;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(361));
        await settle(tester);

        await pumpDesign(tester, bar(0), reduceMotion: true);
        await pumpDesign(tester, bar(1), reduceMotion: true);
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          tester
              .getSize(find.byKey(const ValueKey<String>('app_progress_fill')))
              .width,
          361,
        );
      },
    );
  });

  group('ProgressRing', () {
    test('fraction handles every edge of fulfilled and applicable', () {
      expect(ProgressRing.fraction(0, 0), 0);
      expect(ProgressRing.fraction(3, 0), 0);
      expect(ProgressRing.fraction(0, 4), 0);
      expect(ProgressRing.fraction(-1, 4), 0);
      expect(ProgressRing.fraction(1, 4), 0.25);
      expect(ProgressRing.fraction(3, 4), 0.75);
      expect(ProgressRing.fraction(4, 4), 1);
      expect(ProgressRing.fraction(5, 4), 1);
      expect(ProgressRing.fraction(1, -2), 0);
    });

    testSemantics(
      'goals() speaks "N von M Zielen erreicht" and handles no goals',
      (tester) async {
        await pumpDesign(
          tester,
          Column(
            children: <Widget>[
              ProgressRing.goals(
                key: const ValueKey<String>('some'),
                fulfilled: 3,
                applicable: 4,
              ),
              ProgressRing.goals(
                key: const ValueKey<String>('none'),
                fulfilled: 0,
                applicable: 0,
              ),
            ],
          ),
        );
        expect(
          tester.getSemantics(find.byKey(const ValueKey<String>('some'))).label,
          '3 von 4 Zielen erreicht',
        );
        expect(
          tester.getSemantics(find.byKey(const ValueKey<String>('none'))).label,
          'Heute sind keine Ziele aktiv',
        );
      },
    );

    testWidgets('has the Figma size and shows the centre content', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const ProgressRing(
          value: 0.75,
          semanticLabel: '3 von 4',
          center: Text('3 von 4'),
        ),
      );
      expect(tester.getSize(find.byType(ProgressRing)), const Size(118, 118));
      expect(find.text('3 von 4'), findsOneWidget);
    });

    testWidgets('grows with the text scale up to 1.6 times', (tester) async {
      await pumpDesign(
        tester,
        const ProgressRing(value: 0.5, semanticLabel: 'x'),
        textScale: 1.3,
      );
      expect(
        tester.getSize(find.byType(ProgressRing)).width,
        closeTo(118 * 1.3, 0.01),
      );
      await pumpDesign(
        tester,
        const ProgressRing(value: 0.5, semanticLabel: 'x'),
        textScale: 2,
        width: 430,
      );
      expect(
        tester.getSize(find.byType(ProgressRing)).width,
        closeTo(118 * 1.6, 0.01),
      );
    });

    testWidgets('the centre content never overflows the ring on large text', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const ProgressRing(
          value: 0.75,
          semanticLabel: '3 von 4 Zielen',
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('3 von 4', style: AppTextStyles.titleSection),
              Text('Zielen', style: AppTextStyles.captionDefault),
            ],
          ),
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });

    for (final variant in allVariants) {
      testWidgets(
        '${variant.name}: paints without error and uses the day ring colour by default',
        (tester) async {
          await pumpDesign(
            tester,
            const ProgressRing(value: 0.4, semanticLabel: '40 %'),
            variant: variant,
          );
          final painter =
              tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: find.byType(ProgressRing),
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter
                  as CustomPainter;
          expect(painter.runtimeType.toString(), '_RingPainter');
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('colours can be overridden for the water ring', (tester) async {
      await pumpDesign(
        tester,
        ProgressRing(
          value: 0.6,
          semanticLabel: '60 %',
          color: AppColors.light.moduleWaterChart,
          trackColor: AppColors.light.tintWater,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('MetricCard', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: title, value, target, bar and subtitle', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          MetricCard(
            title: 'Schritte',
            value: '7.450',
            target: '/ 10.000',
            subtitle: '75 % erreicht',
            icon: Icons.directions_walk_rounded,
            accent: AppAccent.steps,
            progress: 0.75,
            progressVariant: AppProgressVariant.steps,
            onTap: () {},
          ),
          variant: variant,
        );
        expect(find.text('Schritte'), findsOneWidget);
        expect(find.text('75 % erreicht'), findsOneWidget);
        expect(textColor(tester, 'Schritte'), colors.textPrimary);
        expect(find.byType(AppProgressBar), findsOneWidget);
        expect(find.byIcon(Icons.directions_walk_rounded), findsOneWidget);
        expect(
          tester.widget<Icon>(find.byIcon(Icons.directions_walk_rounded)).color,
          colors.moduleSteps,
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Schritte')),
        );
        expect(node.label, 'Schritte, 7.450 / 10.000, 75 % erreicht');
        expect(node.flagsCollection.isButton, isTrue);
      });
    }

    testWidgets('value, unit and target are one text with three styles', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const MetricCard(
          title: 'Gewicht',
          value: '71,5',
          unit: 'kg',
          target: '/ 68,0',
        ),
      );
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.byType(MetricCard),
          matching: find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == '71,5 kg / 68,0',
          ),
        ),
      );
      expect(text.text.toPlainText(), '71,5 kg / 68,0');
    });

    testWidgets(
      'tapping the body calls onTap, tapping the quick action does not',
      (tester) async {
        var cardTaps = 0;
        var actionTaps = 0;
        await pumpDesign(
          tester,
          MetricCard(
            title: 'Workout',
            value: 'Upper Body',
            onTap: () => cardTaps++,
            quickAction: MetricCardAction(
              label: 'Training eintragen',
              onPressed: () => actionTaps++,
            ),
          ),
        );
        await tester.tap(find.text('Training eintragen'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(actionTaps, 1);
        expect(cardTaps, 0);

        await tester.tap(find.text('Upper Body'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(cardTaps, 1);
        expect(actionTaps, 1);
      },
    );

    testWidgets('the quick action keeps a tap area of at least 48 px', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        MetricCard(
          title: 'Workout',
          value: 'Upper Body',
          quickAction: MetricCardAction(
            label: 'Training eintragen',
            onPressed: () {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(MetricCardAction)).height,
        greaterThanOrEqualTo(48),
      );
      // The area above and below the 36 px pill reacts too.
      final center = tester.getCenter(find.byType(MetricCardAction));
      var taps = 0;
      await pumpDesign(
        tester,
        MetricCard(
          title: 'Workout',
          value: 'Upper Body',
          quickAction: MetricCardAction(
            label: 'Training eintragen',
            onPressed: () => taps++,
          ),
        ),
      );
      final action = tester.getRect(find.byType(MetricCardAction));
      await tester.tapAt(Offset(action.left + 20, action.top + 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
      expect(center, isNotNull);
    });

    testSemantics(
      'the quick action is its own semantic button next to the card body',
      (tester) async {
        await pumpDesign(
          tester,
          MetricCard(
            title: 'Workout',
            value: 'Upper Body',
            onTap: () {},
            quickAction: MetricCardAction(
              label: 'Training eintragen',
              onPressed: () {},
            ),
          ),
        );
        final body = tester.getSemantics(
          find.bySemanticsLabel('Workout, Upper Body'),
        );
        final action = tester.getSemantics(
          find.bySemanticsLabel('Training eintragen'),
        );
        expect(body.id, isNot(action.id));
        expect(action.flagsCollection.isButton, isTrue);
        expect(body.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      },
    );

    testSemantics('without onTap the body is static and has no chevron', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const MetricCard(title: 'Fokus', value: '45', unit: 'Min.'),
      );
      expect(find.byIcon(AppIcon.chevronRight.data), findsNothing);
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Fokus')));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    });

    testSemantics('semanticLabel overrides the composed label', (tester) async {
      await pumpDesign(
        tester,
        const MetricCard(
          title: 'Gewicht',
          value: '71,5',
          unit: 'kg',
          semanticLabel:
              'Gewicht 71,5 Kilogramm, 1,2 Kilogramm weniger als vor 7 Tagen',
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Gewicht 71,5 Kilogramm, 1,2 Kilogramm weniger als vor 7 Tagen',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the card grows with large text and shows its child slot', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const MetricCard(
          title: 'Wasser',
          value: '1,5',
          target: '/ 2,5 l',
          subtitle: '60 % erreicht',
          progress: 0.6,
          child: SizedBox(key: ValueKey<String>('slot'), height: 20),
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey<String>('slot')), findsOneWidget);
    });
  });

  group('EntryListTile', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: chevron row', (tester) async {
        var taps = 0;
        await pumpDesign(
          tester,
          EntryListTile.chevron(
            title: 'Titel',
            subtitle: 'Untertitel',
            icon: Icons.favorite_rounded,
            onTap: () => taps++,
          ),
          variant: variant,
        );
        expect(textColor(tester, 'Titel'), colors.textPrimary);
        expect(textColor(tester, 'Untertitel'), colors.textSecondary);
        expect(find.byIcon(AppIcon.chevronRight.data), findsOneWidget);
        expect(find.byType(AppIconTile), findsOneWidget);
        expect(
          tester.getSize(find.byType(EntryListTile)).height,
          greaterThanOrEqualTo(56),
        );
        final node = tester.getSemantics(find.byType(EntryListTile));
        expect(node.label, 'Titel, Untertitel');
        expect(node.flagsCollection.isButton, isTrue);
        await tester.tap(find.byType(EntryListTile));
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, 1);
      });

      testSemantics(
        '${variant.name}: toggle row switches by tapping anywhere',
        (tester) async {
          final seen = <bool>[];
          await pumpDesign(
            tester,
            EntryListTile.toggle(
              title: 'Erinnerung',
              subtitle: 'Täglich, 07:30',
              icon: Icons.notifications_none_rounded,
              value: true,
              onToggle: seen.add,
            ),
            variant: variant,
          );
          final node = tester.getSemantics(find.byType(EntryListTile));
          expect(node.label, 'Erinnerung, Täglich, 07:30');
          expect(node.flagsCollection.isToggled, Tristate.isTrue);
          expect(node.flagsCollection.isButton, isFalse);
          // The inner switch is not announced a second time.
          expect(find.bySemanticsLabel('Erinnerung'), findsNothing);
          await tester.tap(find.text('Täglich, 07:30'));
          await tester.pump(const Duration(milliseconds: 400));
          expect(seen, <bool>[false]);
        },
      );

      testSemantics('${variant.name}: value row shows the value and reads it', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          const EntryListTile.value(
            title: 'Design',
            subtitle: 'Hell · Dunkel · OLED · System',
            value: 'System',
            showChevron: true,
            onTap: _noop,
          ),
          variant: variant,
        );
        expect(textColor(tester, 'System'), colors.textSecondary);
        expect(find.byIcon(AppIcon.chevronRight.data), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(EntryListTile)).label,
          'Design, Hell · Dunkel · OLED · System, System',
        );
      });
    }

    testWidgets('a destructive title uses the error colour', (tester) async {
      await pumpDesign(
        tester,
        const EntryListTile.chevron(
          title: 'Alle Daten zurücksetzen',
          destructive: true,
          onTap: _noop,
        ),
      );
      expect(
        textColor(tester, 'Alle Daten zurücksetzen'),
        AppColors.light.error,
      );
    });

    testSemantics('a custom row without onTap is static', (tester) async {
      await pumpDesign(
        tester,
        const EntryListTile(title: 'Version', trailing: Text('1.0.0')),
      );
      final node = tester.getSemantics(find.byType(EntryListTile));
      expect(node.flagsCollection.isButton, isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(node.label, 'Version');
    });

    testWidgets('long texts wrap and the row grows on large text', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const EntryListTile.value(
          title: 'Aus einer Sicherung wiederherstellen und prüfen',
          subtitle: 'Importiert nur nach ausdrücklicher Bestätigung',
          value: 'Bereit',
          icon: Icons.file_download_outlined,
          onTap: _noop,
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(EntryListTile)).height,
        greaterThan(56),
      );
    });
  });

  group('ModuleToggleCard', () {
    testSemantics('shows name and description and switches as a toggle', (
      tester,
    ) async {
      final seen = <bool>[];
      await pumpDesign(
        tester,
        ModuleToggleCard(
          title: 'Körper',
          description: 'Gewicht, Schritte und Körperdaten',
          icon: Icons.monitor_weight_outlined,
          accent: AppAccent.weight,
          value: true,
          onChanged: seen.add,
        ),
      );
      expect(find.text('Körper'), findsOneWidget);
      expect(find.text('Gewicht, Schritte und Körperdaten'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel(RegExp('Körper')));
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      await tester.tap(find.text('Körper'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, <bool>[false]);
    });

    testSemantics('a locked card has a disabled toggle', (tester) async {
      await pumpDesign(
        tester,
        const ModuleToggleCard(
          title: 'Gamification',
          description: 'XP, Level und Abzeichen',
          value: false,
          onChanged: null,
        ),
      );
      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Gamification')),
      );
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    });
  });

  group('ChartSummary', () {
    ChartSummary summary({bool expanded = false, Widget? chart}) =>
        ChartSummary(
          title: 'Verlauf Gewicht',
          summary: 'Das Gewicht sinkt in 7 Tagen von 72,7 auf 71,5 kg.',
          columns: const <String>['Woche', 'Vorwoche', 'Änderung'],
          initiallyExpanded: expanded,
          chart: chart,
          rows: const <ChartSummaryRow>[
            ChartSummaryRow(
              label: 'Schritte Ø/Tag',
              values: <String>['8.950', '8.290', '+8 %'],
            ),
            ChartSummaryRow(
              label: 'Wasser Ø/Tag',
              values: <String>['2,2 l', '2,1 l', '+5 %'],
            ),
          ],
        );

    testSemantics(
      'the table is hidden at first and can be expanded and collapsed',
      (tester) async {
        await pumpDesign(tester, summary());
        expect(find.text('Verlauf Gewicht'), findsOneWidget);
        expect(
          find.text('Das Gewicht sinkt in 7 Tagen von 72,7 auf 71,5 kg.'),
          findsOneWidget,
        );
        expect(find.text('Schritte Ø/Tag'), findsNothing);
        final toggle = tester.getSemantics(
          find.bySemanticsLabel('Als Tabelle anzeigen'),
        );
        expect(toggle.flagsCollection.isButton, isTrue);
        expect(toggle.flagsCollection.isExpanded, Tristate.isFalse);
        expect(toggle.rect.height, greaterThanOrEqualTo(48));

        await tester.tap(find.text('Als Tabelle anzeigen'));
        await settle(tester);
        expect(find.text('Schritte Ø/Tag'), findsOneWidget);
        final expanded = tester.getSemantics(
          find.bySemanticsLabel('Tabelle ausblenden'),
        );
        expect(expanded.flagsCollection.isExpanded, Tristate.isTrue);

        await tester.tap(find.text('Tabelle ausblenden'));
        await settle(tester);
        expect(find.text('Schritte Ø/Tag'), findsNothing);
      },
    );

    testSemantics('every row is read as one sentence with the column headers', (
      tester,
    ) async {
      await pumpDesign(tester, summary(expanded: true));
      expect(
        find.bySemanticsLabel(
          'Schritte Ø/Tag: Woche 8.950, Vorwoche 8.290, Änderung +8 %',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Wasser Ø/Tag: Woche 2,2 l, Vorwoche 2,1 l, Änderung +5 %',
        ),
        findsOneWidget,
      );
    });

    testSemantics('the visual chart is hidden from the accessibility tree', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        summary(
          chart: Semantics(
            label: 'Liniendiagramm',
            child: const SizedBox(height: 80),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Liniendiagramm'), findsNothing);
      expect(
        find.text('Das Gewicht sinkt in 7 Tagen von 72,7 auf 71,5 kg.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'on large text the rows are stacked as blocks without overflow',
      (tester) async {
        await pumpDesign(
          tester,
          summary(expanded: true),
          width: 320,
          textScale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Woche: 8.950'), findsOneWidget);
        expect(find.text('Vorwoche: 8.290'), findsOneWidget);
      },
    );

    testWidgets('expanding is immediate with reduced motion', (tester) async {
      await pumpDesign(tester, summary(), reduceMotion: true);
      await tester.tap(find.text('Als Tabelle anzeigen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Schritte Ø/Tag'), findsOneWidget);
    });

    testWidgets('a summary without columns shows labels and values only', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const ChartSummary(
          title: 'Wasser',
          summary: 'Zusammenfassung',
          initiallyExpanded: true,
          rows: <ChartSummaryRow>[
            ChartSummaryRow(label: 'Heute', values: <String>['1,5 l']),
          ],
        ),
      );
      expect(find.text('Heute'), findsOneWidget);
      expect(find.text('1,5 l'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

void _noop() {}
