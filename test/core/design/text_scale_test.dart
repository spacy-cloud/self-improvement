import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'support/component_gallery.dart';
import 'support/design_test_harness.dart';

void _noop() {}
void _noopBool(bool value) {}
void _noopInt(int value) {}

/// Every component of the design system in a representative state with long
/// German texts, so that wrapping and growing is exercised.
final Map<String, Widget Function()> _components = <String, Widget Function()>{
  'AppHeader tab': () =>
      const AppHeader(title: 'Mein Dashboard für den heutigen Tag'),
  'AppHeader subpage': () => const AppHeader.subpage(
    title: 'Eintrag für den gestrigen Tag bearbeiten',
    actions: <Widget>[
      AppIconButton(
        icon: Icons.delete_outline_rounded,
        semanticLabel: 'Löschen',
        onPressed: _noop,
      ),
    ],
  ),
  'PrimaryButton': () => const PrimaryButton(
    label: 'Ersten Eintrag hinzufügen und speichern',
    onPressed: _noop,
    icon: Icons.add,
  ),
  'PrimaryButton loading': () => const PrimaryButton(
    label: 'Eintrag speichern',
    onPressed: _noop,
    loading: true,
  ),
  'SecondaryButton': () => const SecondaryButton(
    label: 'Alle Daten zurücksetzen und neu beginnen',
    onPressed: _noop,
    danger: true,
  ),
  'AppIconButton row': () => Row(
    children: <Widget>[
      AppIconButton(
        icon: AppIcon.back.data,
        semanticLabel: 'Zurück',
        onPressed: _noop,
        filled: true,
      ),
      AppIconButton(
        icon: AppIcon.close.data,
        semanticLabel: 'Schließen',
        onPressed: _noop,
      ),
    ],
  ),
  'AppSwitch and RoundCheckbox': () => const Row(
    children: <Widget>[
      AppSwitch(value: true, onChanged: _noopBool, semanticLabel: 'An'),
      RoundCheckbox(value: true, onChanged: _noopBool, semanticLabel: 'Fertig'),
    ],
  ),
  'chips': () => const Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      AppChoiceChip(
        label: 'Kraft und Ausdauer',
        selected: true,
        onSelected: _noopBool,
      ),
      AppFilterChip(
        label: 'Beweglichkeit',
        selected: false,
        onSelected: _noopBool,
      ),
      AppChoiceChip(
        label: 'Ganzkörpertraining',
        selected: false,
        onSelected: _noopBool,
      ),
    ],
  ),
  'PeriodSelector': () => PeriodSelector<int>(
    options: PeriodSelector.dayOptions,
    selected: 30,
    onChanged: (_) {},
  ),
  'PeriodSelector with long labels': () => PeriodSelector<String>(
    options: const <PeriodOption<String>>[
      PeriodOption<String>(value: 'a', label: 'Aufgaben'),
      PeriodOption<String>(value: 'g', label: 'Gewohnheiten'),
    ],
    selected: 'g',
    onChanged: (_) {},
  ),
  'QuantityStepper': () => const QuantityStepper(
    valueText: '71,5',
    unit: 'kg',
    onIncrease: _noop,
    onDecrease: _noop,
    expand: true,
  ),
  'QuantityStepper ml': () => const QuantityStepper(
    valueText: '1.250',
    unit: 'ml',
    onIncrease: _noop,
    onDecrease: _noop,
  ),
  'AppTextField': () => const AppTextField(
    label: 'Gewicht in Kilogramm für diese Messung',
    requirementLabel: 'Pflichtfeld',
    suffixText: 'kg',
    numeric: true,
  ),
  'AppTextField error': () => const AppTextField(
    label: 'Gewicht in kg',
    errorText: 'Bitte einen Wert zwischen 20 und 400 kg eingeben.',
  ),
  'AppCard': () => const AppCard(
    child: Text(
      'Karten wachsen mit dem Inhalt mit, auch bei sehr großer Schrift.',
    ),
  ),
  'MetricCard grid': () => const AdaptiveGrid(
    children: <Widget>[
      MetricCard(
        title: 'Schritte',
        value: '7.450',
        target: '/ 10.000',
        subtitle: '75 % erreicht',
        icon: Icons.directions_walk_rounded,
        accent: AppAccent.steps,
        progress: 0.75,
        progressVariant: AppProgressVariant.steps,
        onTap: _noop,
      ),
      MetricCard(
        title: 'Workout',
        value: 'Upper Body',
        subtitle: 'Brust, Schulter, Rücken, Bizeps, Trizeps',
        icon: Icons.fitness_center_rounded,
        accent: AppAccent.workout,
        onTap: _noop,
        quickAction: MetricCardAction(
          label: 'Training eintragen',
          icon: Icons.add_rounded,
          onPressed: _noop,
        ),
      ),
    ],
  ),
  'EntryListTile variants': () => const AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        EntryListTile.chevron(
          title: 'Aus einer Sicherung wiederherstellen',
          subtitle: 'Importiert nach ausdrücklicher Bestätigung',
          icon: Icons.file_download_outlined,
          onTap: _noop,
        ),
        EntryListTile.toggle(
          title: 'Wiege-Erinnerung',
          subtitle: 'Täglich, 07:30',
          icon: Icons.notifications_none_rounded,
          value: true,
          onToggle: _noopBool,
        ),
        EntryListTile.value(
          title: 'Design',
          subtitle: 'Hell · Dunkel · OLED · System',
          value: 'System',
          icon: Icons.contrast_rounded,
          showChevron: true,
          onTap: _noop,
        ),
      ],
    ),
  ),
  'ModuleToggleCard': () => const ModuleToggleCard(
    title: 'Ernährung',
    description: 'Wasser trinken und Mahlzeiten eintragen',
    icon: Icons.restaurant_rounded,
    accent: AppAccent.nutrition,
    value: true,
    onChanged: _noopBool,
  ),
  'AppProgressBar': () =>
      const AppProgressBar(value: 0.6, variant: AppProgressVariant.water),
  'ProgressRing with content': () => const ProgressRing(
    value: 0.75,
    semanticLabel: '3 von 4 Zielen erreicht',
    center: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text('3 von 4', style: AppTextStyles.titleSection),
        Text('Zielen', style: AppTextStyles.captionDefault),
      ],
    ),
  ),
  'ChartSummary': () => const ChartSummary(
    title: 'Verlauf Gewicht in den letzten sieben Tagen',
    summary: 'Das Gewicht sinkt in 7 Tagen von 72,7 auf 71,5 kg.',
    columns: <String>['Woche', 'Vorwoche', 'Änderung'],
    initiallyExpanded: true,
    rows: <ChartSummaryRow>[
      ChartSummaryRow(
        label: 'Schritte Ø/Tag',
        values: <String>['8.950', '8.290', '+8 %'],
      ),
      ChartSummaryRow(
        label: 'Workouts',
        values: <String>['2 · 105 Min.', '–', 'kein Vergleich'],
      ),
    ],
  ),
  'UndoSnackBar variants': () => const Column(
    children: <Widget>[
      UndoSnackBar.undo(
        message: '„Wäsche waschen“ wurde als erledigt markiert',
        onAction: _noop,
      ),
      SizedBox(height: 8),
      UndoSnackBar.error(
        message: 'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
        onAction: _noop,
      ),
      SizedBox(height: 8),
      UndoSnackBar.success(message: 'Gewicht gespeichert · +10 XP'),
    ],
  ),
  'EmptyState': () => const EmptyState(
    title: 'Noch keine Daten vorhanden',
    message: 'Trag deinen ersten Wert ein, dann erscheint hier dein Verlauf.',
    actionLabel: 'Ersten Eintrag hinzufügen',
    onAction: _noop,
  ),
  'ErrorState': () => const ErrorState(onRetry: _noop),
  'ConfirmationSheet': () => const ConfirmationSheet(
    title: 'Messung vom 13. Sep. löschen?',
    message:
        '71,8 kg wird entfernt. Du kannst es direkt danach rückgängig machen.',
    confirmLabel: 'Löschen',
    onConfirm: _noop,
    onCancel: _noop,
  ),
  'AppBottomNavBar': () => const AppBottomNavBar(
    selectedIndex: 2,
    onSelected: _noopInt,
    onPlusPressed: _noop,
  ),
};

void main() {
  setUpAll(loadInterFont);

  const widths = <double>[320, 360, 393, 430];

  group('no overflow at 200 % text', () {
    for (final entry in _components.entries) {
      for (final width in widths) {
        testWidgets('${entry.key} at ${width.toInt()} px', (tester) async {
          await pumpDesign(
            tester,
            entry.value(),
            width: width,
            height: 800,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final variant in allVariants) {
      for (final width in widths) {
        testWidgets('whole gallery in ${variant.name} at ${width.toInt()} px', (
          tester,
        ) async {
          await pumpDesign(
            tester,
            const ComponentGallery(),
            variant: variant,
            width: width,
            height: 800,
            textScale: 2,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('no overflow at other text scales', () {
    for (final scale in <double>[0.85, 1.0, 1.3, 1.5, 1.8]) {
      testWidgets('whole gallery at scale $scale on 320 px', (tester) async {
        await pumpDesign(
          tester,
          const ComponentGallery(),
          width: 320,
          height: 800,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('nothing is clamped globally', () {
    testWidgets('a Text in the design system doubles its size at scale 2.0', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppCard(
          child: Text('Skalierung', style: AppTextStyles.bodyRegular),
        ),
      );
      final normal = tester.getSize(find.text('Skalierung')).height;
      await pumpDesign(
        tester,
        const AppCard(
          child: Text('Skalierung', style: AppTextStyles.bodyRegular),
        ),
        textScale: 2,
      );
      expect(
        tester.getSize(find.text('Skalierung')).height,
        closeTo(normal * 2, 0.5),
      );
    });

    testWidgets('component texts grow with the scale', (tester) async {
      Future<double> heightOf(double scale) async {
        await pumpDesign(
          tester,
          PrimaryButton(label: 'Eintrag speichern', onPressed: () {}),
          textScale: scale,
        );
        return tester.getSize(find.text('Eintrag speichern')).height;
      }

      final normal = await heightOf(1);
      final large = await heightOf(2);
      expect(large, closeTo(normal * 2, 0.5));
    });
  });
}
