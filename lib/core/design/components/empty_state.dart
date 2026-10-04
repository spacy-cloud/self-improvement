import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/primary_button.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/state_layout.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Empty list or first-day state: illustration circle, title, explanation and
/// an optional primary action ("Ersten Eintrag hinzufügen").
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.icon = AppIcon.sprout,
    this.accent = AppAccent.primary,
    this.card = true,
  });

  /// Title, for example "Noch keine Daten".
  final String title;

  /// Explanation of what to do next.
  final String message;

  /// Label of the action button; without it no button is shown.
  final String? actionLabel;

  /// Action callback.
  final VoidCallback? onAction;

  /// Glyph of the illustration.
  final AppIcon icon;

  /// Accent of the illustration.
  final AppAccent accent;

  /// Whether the block is drawn as a bordered card (Figma) or free on the page.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return StateLayout(
      icon: icon.data,
      iconColor: colors.accent(accent),
      tint: colors.accentTint(accent),
      title: title,
      message: message,
      card: card,
      liveRegion: false,
      action: actionLabel == null
          ? null
          : PrimaryButton(
              label: actionLabel!,
              onPressed: onAction,
              expand: card,
            ),
    );
  }
}
