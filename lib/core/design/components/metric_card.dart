import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/components/app_card.dart';
import 'package:self_improvement/core/design/components/app_progress_bar.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/tokens/app_colors.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Dashboard card for one measure (steps, water, weight, workout, ...): icon,
/// title, big value with unit and target, optional progress bar, subtitle and
/// a free [child] slot.
///
/// The card body is one button ([onTap], with a chevron). The [quickAction]
/// slot sits below the body and outside of the tap area, so tapping it never
/// triggers [onTap]. The card hugs its content and grows with large text.
class MetricCard extends StatelessWidget {
  /// Creates a metric card.
  const MetricCard({
    required this.title,
    required this.value,
    super.key,
    this.unit,
    this.target,
    this.subtitle,
    this.icon,
    this.valueStyle,
    this.valueIcon,
    this.accent = AppAccent.primary,
    this.progress,
    this.progressVariant = AppProgressVariant.primary,
    this.progressSemanticLabel,
    this.child,
    this.quickAction,
    this.onTap,
    this.semanticLabel,
  });

  /// Card title, for example "Schritte".
  final String title;

  /// Formatted value, for example "7.450".
  final String value;

  /// Unit directly after the value, for example "kg".
  final String? unit;

  /// Target text after the value, for example "/ 10.000".
  final String? target;

  /// Line below the value or bar, for example "75 % erreicht".
  final String? subtitle;

  /// Glyph in front of the title.
  final IconData? icon;

  /// Style of [value]. The default is the big number style; a card that shows
  /// a text instead of a number (a day state such as "Ruhetag") passes a
  /// smaller one so the text does not break inside a word.
  final TextStyle? valueStyle;

  /// Glyph in front of [value] (for example the moon of a rest day), in the
  /// colour of [accent]. Decorative: [semanticLabel] says what it means.
  final IconData? valueIcon;

  /// Accent of the icon.
  final AppAccent accent;

  /// Progress from 0 to 1 (draws a bar); `null` hides the bar.
  final double? progress;

  /// Colour variant of the bar.
  final AppProgressVariant progressVariant;

  /// Spoken text of the bar; defaults to the card label.
  final String? progressSemanticLabel;

  /// Extra content below the value (for example a trend line). Visual only:
  /// describe it in [semanticLabel].
  final Widget? child;

  /// Action below the body, for example a [MetricCardAction].
  final Widget? quickAction;

  /// Tap callback of the card body; `null` makes the body static.
  final VoidCallback? onTap;

  /// Spoken label of the body; defaults to title, value, unit, target and
  /// subtitle joined with commas.
  final String? semanticLabel;

  String get _label {
    if (semanticLabel != null) {
      return semanticLabel!;
    }
    final valueParts = <String>[value];
    if (unit != null) {
      valueParts.add(unit!);
    }
    if (target != null) {
      valueParts.add(target!);
    }
    final parts = <String>[title, valueParts.join(' ')];
    if (subtitle != null) {
      parts.add(subtitle!);
    }
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final header = Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 24, color: colors.accent(accent)),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.titleCard.copyWith(color: colors.textPrimary),
          ),
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(width: 4),
          Icon(
            AppIcon.chevronRight.data,
            size: 20,
            color: colors.textSecondary,
          ),
        ],
      ],
    );
    final valueLine = Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: value,
            style: (valueStyle ?? AppTextStyles.titleScreen).copyWith(
              color: colors.textPrimary,
            ),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
          if (target != null)
            TextSpan(
              text: ' $target',
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
        ],
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          header,
          const SizedBox(height: 12),
          if (valueIcon == null)
            valueLine
          else
            // A Wrap, not a Row: a long word (for example "Übersprungen") that
            // does not fit next to the glyph moves below it instead of
            // breaking inside the word.
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Icon(valueIcon, size: 18, color: colors.accent(accent)),
                valueLine,
              ],
            ),
          if (progress != null) ...<Widget>[
            const SizedBox(height: 10),
            AppProgressBar(
              value: progress!,
              variant: progressVariant,
              semanticLabel: progressSemanticLabel,
            ),
          ],
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
          if (child != null) ...<Widget>[const SizedBox(height: 10), child!],
        ],
      ),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            container: true,
            button: onTap != null,
            label: _label,
            onTap: onTap,
            excludeSemantics: true,
            child: InkSurface(onTap: onTap, child: body),
          ),
          if (quickAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: quickAction,
            ),
        ],
      ),
    );
  }
}

/// Small pill action for the [MetricCard.quickAction] slot (for example
/// "+ Training eintragen"). The pill is 36 high with a 48 high tap area.
class MetricCardAction extends StatelessWidget {
  /// Creates a quick action.
  const MetricCardAction({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.accent = AppAccent.primary,
    this.semanticLabel,
  });

  /// Visible text.
  final String label;

  /// Tap callback; `null` disables the action.
  final VoidCallback? onPressed;

  /// Optional leading glyph (a plus sign for add actions).
  final IconData? icon;

  /// Accent of the pill.
  final AppAccent accent;

  /// Spoken label (defaults to [label]).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    final foreground = enabled ? colors.accent(accent) : colors.textTertiary;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          child: InkSurface(
            onTap: onPressed,
            shape: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
              child: Align(
                widthFactor: 1,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: enabled ? colors.accentTint(accent) : colors.track,
                    shape: const StadiumBorder(),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 36),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (icon != null) ...<Widget>[
                            Icon(icon, size: 16, color: foreground),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              label,
                              style: AppTextStyles.bodyStrong.copyWith(
                                color: foreground,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
