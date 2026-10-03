import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_card.dart';
import 'package:self_improvement/core/design/components/entry_list_tile.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';

/// Card that switches a functional module on or off ("Module verwalten"):
/// icon in the module accent, module name, description and a toggle. The whole
/// card is the touch target; the state is announced as a toggle.
class ModuleToggleCard extends StatelessWidget {
  /// Creates a module card.
  const ModuleToggleCard({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    super.key,
    this.icon,
    this.accent = AppAccent.primary,
    this.semanticLabel,
  });

  /// Module name, for example "Körper".
  final String title;

  /// What the module offers (may wrap).
  final String description;

  /// Whether the module is on.
  final bool value;

  /// Called with the new value; `null` locks the toggle.
  final ValueChanged<bool>? onChanged;

  /// Glyph in the module accent.
  final IconData? icon;

  /// Accent of the module.
  final AppAccent accent;

  /// Spoken label (defaults to title and description).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: EntryListTile.toggle(
        title: title,
        subtitle: description,
        value: value,
        onToggle: onChanged,
        icon: icon,
        accent: accent,
        semanticLabel: semanticLabel,
      ),
    );
  }
}
