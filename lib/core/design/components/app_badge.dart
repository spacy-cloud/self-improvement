import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Small status pill on the tint of an [AppAccent], for example "Fast
/// geschafft!", "Noch 1,0 l bis zum Ziel" or a change against the last entry.
///
/// Not interactive. The text always reaches 4.5:1 on the tint (see
/// [AppColors.accentTextOnTint]); the optional [icon] uses the accent colour.
/// The pill wraps its text on large type instead of clipping it.
class AppBadge extends StatelessWidget {
  /// Creates a badge.
  const AppBadge({
    required this.label,
    super.key,
    this.accent = AppAccent.primary,
    this.icon,
    this.semanticLabel,
  });

  /// Badge text.
  final String label;

  /// Accent role that selects tint and icon colour.
  final AppAccent accent;

  /// Optional leading glyph.
  final IconData? icon;

  /// Overrides the spoken text (defaults to [label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.accentTint(accent),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: colors.accent(accent)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.accentTextOnTint(accent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
