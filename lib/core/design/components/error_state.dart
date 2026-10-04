import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/secondary_button.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/state_layout.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Load error state: error illustration, message that the entries are safe,
/// and a retry action. Announced as a live region when it appears.
class ErrorState extends StatelessWidget {
  /// Creates an error state.
  const ErrorState({
    required this.onRetry,
    super.key,
    this.title = 'Daten konnten nicht geladen werden',
    this.message =
        'Deine Einträge sind sicher gespeichert. Versuche es noch '
        'einmal.',
    this.retryLabel = 'Erneut versuchen',
    this.card = true,
  });

  /// Retry callback.
  final VoidCallback? onRetry;

  /// Title.
  final String title;

  /// Explanation.
  final String message;

  /// Label of the retry button.
  final String retryLabel;

  /// Whether the block is drawn as a bordered card (Figma) or free on the page.
  final bool card;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return StateLayout(
      icon: AppIcon.cloudOff.data,
      iconColor: colors.error,
      tint: colors.errorTint,
      title: title,
      message: message,
      card: card,
      liveRegion: true,
      action: SecondaryButton(
        label: retryLabel,
        onPressed: onRetry,
        icon: AppIcon.retry.data,
        expand: card,
      ),
    );
  }
}
