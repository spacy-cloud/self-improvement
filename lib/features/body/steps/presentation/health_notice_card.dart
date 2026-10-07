import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_labels.dart';

/// A text button in the colour of the primary text with a 48 px tap area, the
/// action of the notices and cards of the Health comparison (design frames
/// `4122:667` and `4123:316`).
class HealthTextAction extends StatelessWidget {
  const HealthTextAction({
    required this.label,
    required this.onPressed,
    super.key,
    this.semanticLabel,
    this.icon,
  });

  /// Visible text.
  final String label;

  /// Tap callback; `null` disables the action.
  final VoidCallback? onPressed;

  /// The spoken text when it differs from [label].
  final String? semanticLabel;

  /// An optional glyph in front of the text.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null;
    final color = enabled ? colors.primaryText : colors.textTertiary;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSizes.touchMin,
          minWidth: AppSizes.touchMin,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: AppRadii.controlBorder,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        style: AppTextStyles.bodyStrong.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The honest explanation of a state in which the values of Health do not
/// arrive (no access, interface missing or outdated, comparison failed), with
/// the way out. Warning tint with an alert glyph; title and text carry the
/// meaning, not the colour. Announced as a live region when it appears.
class HealthNoticeCard extends StatelessWidget {
  const HealthNoticeCard({
    required this.notice,
    required this.onAction,
    super.key,
    this.busy = false,
  });

  final HealthNotice notice;

  /// Called with the action of the tapped button.
  final ValueChanged<HealthNoticeAction> onAction;

  /// While true the buttons are disabled (a request is running).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.warningTint,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: colors.warningTint),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox.square(
                dimension: 40,
                child: ExcludeSemantics(
                  child: Icon(
                    AppIcon.error.data,
                    size: 24,
                    color: colors.warningText,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      container: true,
                      label: '${notice.title}. ${notice.text}',
                      excludeSemantics: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            notice.title,
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: colors.warningText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            notice.text,
                            style: AppTextStyles.captionDefault.copyWith(
                              color: colors.warningText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        for (final button in notice.buttons)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: HealthTextAction(
                              label: button.label,
                              semanticLabel: button.semanticLabel,
                              onPressed: busy
                                  ? null
                                  : () => onAction(button.action),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The source card of "Meine Schritte" while Health delivers (design frame
/// `4122:553`, node `4122:652`): the name of the interface, when it was last
/// compared (or what is happening) and the action "Aktualisieren".
///
/// With large text the action moves below the texts instead of squeezing them.
class HealthSourceCard extends StatelessWidget {
  const HealthSourceCard({
    required this.name,
    required this.line,
    required this.refreshLabel,
    required this.onRefresh,
    super.key,
  });

  /// How the interface is called, for example `Health Connect`.
  final String name;

  /// The second line: `Zuletzt: heute, 09:41`, `Wird abgeglichen …`, ...
  final String line;

  /// The spoken label of the action.
  final String refreshLabel;

  /// Starts a comparison; `null` while one runs.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final large =
        MediaQuery.textScalerOf(context).scale(1) > AppSizes.stackTextScale;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          name,
          style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 2),
        Semantics(
          container: true,
          liveRegion: true,
          label: line,
          excludeSemantics: true,
          child: Text(
            line,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
    final action = HealthTextAction(
      label: 'Aktualisieren',
      semanticLabel: refreshLabel,
      icon: AppIcon.retry.data,
      onPressed: onRefresh,
    );
    final tile = AppIconTile(
      icon: AppIcon.heart.data,
      accent: AppAccent.steps,
      size: 40,
      iconSize: 22,
      radius: 12,
    );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: large
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    tile,
                    const SizedBox(width: 12),
                    Expanded(child: texts),
                  ],
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: action),
              ],
            )
          : Row(
              children: <Widget>[
                tile,
                const SizedBox(width: 12),
                Expanded(child: texts),
                const SizedBox(width: 8),
                action,
              ],
            ),
    );
  }
}
