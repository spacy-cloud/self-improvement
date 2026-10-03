import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Static gallery of all components in their states, used by the golden tests
/// and the text-scale tests. All values are synthetic.
class ComponentGallery extends StatelessWidget {
  /// Creates the gallery.
  const ComponentGallery({
    super.key,
    this.expandTable = true,
    this.includeNavigation = true,
  });

  /// Whether the chart summary table starts expanded.
  final bool expandTable;

  /// Whether the bottom navigation bars are part of the gallery.
  final bool includeNavigation;

  static void _noop() {}
  static void _noopBool(bool value) {}

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _Section('AppHeader'),
        const AppHeader(title: 'Mein Dashboard'),
        const AppHeader.subpage(title: 'Gewicht eintragen'),
        const _Section('Buttons'),
        const PrimaryButton(label: 'Eintrag speichern', onPressed: _noop),
        const SizedBox(height: 8),
        const PrimaryButton(
          label: 'Eintrag speichern',
          onPressed: _noop,
          loading: true,
        ),
        const SizedBox(height: 8),
        const PrimaryButton(label: 'Eintrag speichern', onPressed: null),
        const SizedBox(height: 8),
        const SecondaryButton(label: 'Abbrechen', onPressed: _noop),
        const SizedBox(height: 8),
        const SecondaryButton(
          label: 'Zurücksetzen …',
          onPressed: _noop,
          danger: true,
        ),
        const SizedBox(height: 8),
        const SecondaryButton(label: 'Abbrechen', onPressed: null),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            AppIconButton(
              icon: AppIcon.back.data,
              onPressed: _noop,
              semanticLabel: 'Zurück',
            ),
            AppIconButton(
              icon: AppIcon.back.data,
              onPressed: _noop,
              semanticLabel: 'Zurück',
              filled: true,
            ),
          ],
        ),
        const _Section('Toggle, Checkbox, Chips'),
        Row(
          children: <Widget>[
            AppSwitch(value: true, onChanged: _noopBool, semanticLabel: 'An'),
            AppSwitch(value: false, onChanged: _noopBool, semanticLabel: 'Aus'),
            RoundCheckbox(
              value: true,
              onChanged: _noopBool,
              semanticLabel: 'Erledigt',
            ),
            RoundCheckbox(
              value: false,
              onChanged: _noopBool,
              semanticLabel: 'Offen',
            ),
          ],
        ),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            AppChoiceChip(
              label: 'Kraft',
              selected: true,
              onSelected: _noopBool,
            ),
            AppChoiceChip(
              label: 'Cardio',
              selected: false,
              onSelected: _noopBool,
            ),
            AppFilterChip(
              label: 'Mobility',
              selected: false,
              onSelected: _noopBool,
            ),
          ],
        ),
        const _Section('PeriodSelector, QuantityStepper'),
        PeriodSelector<int>(
          options: PeriodSelector.dayOptions,
          selected: 7,
          onChanged: (_) {},
        ),
        gap,
        const QuantityStepper(
          valueText: '71,5',
          unit: 'kg',
          onIncrease: _noop,
          onDecrease: _noop,
          expand: true,
        ),
        const _Section('AppTextField'),
        const AppTextField(
          label: 'Gewicht in kg',
          requirementLabel: 'Pflichtfeld',
          hint: '71,5',
          numeric: true,
        ),
        gap,
        const AppTextField(
          label: 'Gewicht in kg',
          requirementLabel: 'Pflichtfeld',
          errorText: 'Bitte einen Wert zwischen 20 und 400 kg eingeben.',
        ),
        const _Section('Progress'),
        const AppProgressBar(value: 0.65),
        const SizedBox(height: 8),
        const AppProgressBar(value: 0.65, variant: AppProgressVariant.water),
        const SizedBox(height: 8),
        const AppProgressBar(value: 0.65, variant: AppProgressVariant.steps),
        const SizedBox(height: 8),
        const AppProgressBar(value: 0.65, variant: AppProgressVariant.focus),
        gap,
        const Center(
          child: ProgressRing(
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
        ),
        const _Section('Cards und Listen'),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Kartentitel', style: AppTextStyles.titleCard),
              SizedBox(height: 8),
              Text(
                'Karten wachsen mit dem Inhalt mit (große Schrift).',
                style: AppTextStyles.bodyRegular,
              ),
            ],
          ),
        ),
        gap,
        const AdaptiveGrid(
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
              title: 'Wasser',
              value: '1,5',
              target: '/ 2,5 l',
              subtitle: '60 % erreicht',
              icon: Icons.water_drop_outlined,
              accent: AppAccent.water,
              progress: 0.6,
              progressVariant: AppProgressVariant.water,
              onTap: _noop,
            ),
            MetricCard(
              title: 'Gewicht',
              value: '71,5',
              unit: 'kg',
              subtitle: '−1,2 kg in 7 Tagen',
              icon: Icons.monitor_weight_outlined,
              accent: AppAccent.weight,
              onTap: _noop,
            ),
            MetricCard(
              title: 'Workout',
              value: 'Upper Body',
              subtitle: 'Brust, Schulter, Rücken',
              icon: Icons.fitness_center_rounded,
              accent: AppAccent.workout,
              onTap: _noop,
              quickAction: MetricCardAction(
                label: 'Training eintragen',
                icon: Icons.add_rounded,
                accent: AppAccent.primary,
                onPressed: _noop,
              ),
            ),
          ],
        ),
        gap,
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              EntryListTile.chevron(
                title: 'Titel',
                subtitle: 'Untertitel',
                icon: Icons.favorite_rounded,
                onTap: _noop,
              ),
              const Divider(height: 1),
              EntryListTile.toggle(
                title: 'Erinnerung',
                subtitle: 'Täglich, 07:30',
                icon: Icons.notifications_none_rounded,
                accent: AppAccent.water,
                value: true,
                onToggle: _noopBool,
              ),
              const Divider(height: 1),
              const EntryListTile.value(
                title: 'Design',
                subtitle: 'Hell · Dunkel · OLED · System',
                icon: Icons.contrast_rounded,
                accent: AppAccent.focus,
                value: 'System',
                showChevron: true,
                onTap: _noop,
              ),
              const Divider(height: 1),
              const EntryListTile.chevron(
                title: 'Alle Daten zurücksetzen',
                subtitle: 'Profil und Einträge löschen',
                icon: Icons.restart_alt_rounded,
                accent: AppAccent.error,
                destructive: true,
                onTap: _noop,
              ),
            ],
          ),
        ),
        gap,
        const ModuleToggleCard(
          title: 'Körper',
          description: 'Gewicht, Schritte und Körperdaten',
          icon: Icons.monitor_weight_outlined,
          accent: AppAccent.weight,
          value: true,
          onChanged: _noopBool,
        ),
        const _Section('ChartSummary'),
        ChartSummary(
          title: 'Verlauf Gewicht',
          summary: 'Das Gewicht sinkt in 7 Tagen von 72,7 auf 71,5 kg.',
          columns: const <String>['Woche', 'Vorwoche', 'Änderung'],
          initiallyExpanded: expandTable,
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
        ),
        const _Section('Snackbars'),
        const UndoSnackBar.error(
          message: 'Speichern fehlgeschlagen',
          onAction: _noop,
        ),
        const SizedBox(height: 8),
        const UndoSnackBar.success(message: 'Gewicht gespeichert · +10 XP'),
        const SizedBox(height: 8),
        const UndoSnackBar.undo(
          message: '„Wäsche waschen“ erledigt',
          onAction: _noop,
        ),
        const _Section('EmptyState, ErrorState'),
        const EmptyState(
          title: 'Noch keine Daten',
          message:
              'Trag deinen ersten Wert ein, dann erscheint hier dein Verlauf.',
          actionLabel: 'Ersten Eintrag hinzufügen',
          onAction: _noop,
        ),
        gap,
        const ErrorState(onRetry: _noop),
        const _Section('ConfirmationSheet'),
        const ConfirmationSheet(
          title: 'Eintrag löschen?',
          message: 'Der Eintrag wird entfernt. Du kannst es direkt danach rückgängig machen.',
          confirmLabel: 'Löschen',
          onConfirm: _noop,
          onCancel: _noop,
        ),
        if (includeNavigation) ...<Widget>[
          const _Section('AppBottomNavBar'),
          const AppBottomNavBar(
            selectedIndex: 0,
            onSelected: _noopInt,
            onPlusPressed: _noop,
          ),
          const SizedBox(height: 8),
          const AppBottomNavBar(
            selectedIndex: 2,
            onSelected: _noopInt,
            onPlusPressed: _noop,
            plusOpen: true,
          ),
        ],
      ],
    );
  }

  static void _noopInt(int index) {}
}

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.captionStrong.copyWith(color: colors.textTertiary),
      ),
    );
  }
}
