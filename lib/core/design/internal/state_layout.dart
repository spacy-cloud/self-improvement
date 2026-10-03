import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Shared layout of `EmptyState` and `ErrorState`: a tinted circle with an icon,
/// a title, a message and one action. With [card] the block sits in a bordered
/// surface (Figma), without it the block is centred on the page.
class StateLayout extends StatelessWidget {
  /// Creates the layout.
  const StateLayout({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.message,
    required this.card,
    required this.liveRegion,
    super.key,
    this.action,
  });

  /// Glyph in the illustration circle.
  final IconData icon;

  /// Glyph colour.
  final Color iconColor;

  /// Circle tint.
  final Color tint;

  /// Title.
  final String title;

  /// Explanation.
  final String message;

  /// Action widget (button).
  final Widget? action;

  /// Whether the block is drawn as a bordered card.
  final bool card;

  /// Whether appearing content is announced to screen readers.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final texts = Semantics(
      container: true,
      liveRegion: liveRegion,
      label: '$title. $message',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleSection.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: card
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: <Widget>[
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: 10),
        texts,
        if (action != null) ...<Widget>[const SizedBox(height: 10), action!],
      ],
    );

    final padded = Padding(
      padding: card
          ? const EdgeInsets.fromLTRB(20, 24, 20, 20)
          : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: body,
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: card
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadii.sheetBorder,
                    border: Border.all(color: colors.borderDecorative),
                  ),
                  child: padded,
                )
              : padded,
        ),
      ),
    );
  }
}
