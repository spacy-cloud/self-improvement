import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/first_entry_action.dart';

/// The dashboard of the very first day, before anything was recorded: a
/// welcome with one clear first step and the starting points of the design
/// ("Schnell starten").
///
/// Nothing here is a measurement: no ring, no card with numbers. Every action
/// only opens an entry screen.
class FirstDaySection extends StatelessWidget {
  /// Creates the section.
  const FirstDaySection({
    required this.name,
    required this.quickStarts,
    required this.onFirstEntry,
    required this.onQuickStart,
    required this.hasFirstEntry,
    super.key,
  });

  /// The name from the profile, or `null`.
  final String? name;

  /// The starting points of enabled modules.
  final List<QuickStart> quickStarts;

  /// Whether any enabled module offers an entry; without one the primary action
  /// leads to the module selection instead.
  final bool hasFirstEntry;

  /// The primary action ("Ersten Eintrag hinzufügen" / "Module auswählen").
  final VoidCallback onFirstEntry;

  /// A starting point was chosen.
  final ValueChanged<QuickStart> onQuickStart;

  static AppAccent _accent(String id) => switch (id) {
    'weight' => AppAccent.weight,
    'water' => AppAccent.water,
    _ => AppAccent.habits,
  };

  static IconData _icon(String id) => switch (id) {
    'weight' => AppIcon.weight.data,
    'water' => AppIcon.water.data,
    _ => AppIcon.habit.data,
  };

  @override
  Widget build(BuildContext context) {
    final greeting = name == null ? 'Willkommen!' : 'Willkommen, $name!';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EmptyState(
          title: greeting,
          message: hasFirstEntry
              ? 'Heute ist noch nichts eingetragen. Fang klein an – ein '
                    'Eintrag reicht für den Start.'
              : 'Heute ist noch nichts eingetragen. Schalte ein Modul ein, '
                    'um deinen ersten Eintrag zu erfassen.',
          actionLabel: hasFirstEntry
              ? 'Ersten Eintrag hinzufügen'
              : 'Module auswählen',
          onAction: onFirstEntry,
        ),
        if (quickStarts.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.s16),
          const AppSectionHeader(title: 'Schnell starten'),
          const SizedBox(height: AppSpacing.s8),
          AppListGroup(
            children: <Widget>[
              for (final start in quickStarts)
                EntryListTile.chevron(
                  title: start.title,
                  subtitle: start.subtitle,
                  icon: _icon(start.id),
                  accent: _accent(start.id),
                  onTap: () => onQuickStart(start),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
