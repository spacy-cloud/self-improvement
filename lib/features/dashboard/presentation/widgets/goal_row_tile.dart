import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goal_visuals.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/tap_surface.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/features/focus/presentation/workout_day_sheet.dart'
    show workoutRestIcon, workoutSkipIcon;

/// One goal of "Ziele heute": symbol, name, status word, the stand with the
/// target in the units of the app, and a bar.
///
/// Without [onTap] the row only shows; with it the whole row is one button
/// that opens the module of the goal, with a chevron. For a screen reader it
/// is one element (name, stand, status, and "öffnen" for a button). The state
/// is never carried by colour alone: the pill has a word, and a reached goal a
/// symbol too.
///
/// On large text (or in a narrow card) the row stacks: the pill moves below the
/// name and the chevron gives way, as in the design.
class GoalRowTile extends StatelessWidget {
  /// Creates the row of [row].
  const GoalRowTile({required this.row, this.onTap, super.key});

  /// What the row shows.
  final GoalsDayRow row;

  /// Opens the module of the goal; `null` makes the row a plain display.
  final VoidCallback? onTap;

  /// Below this width of the card the row stacks, also at normal text size.
  static const double _stackWidth = 300;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final visual = goalVisual(row);
    final tappable = onTap != null;
    final tile = AppIconTile(
      icon: visual.icon,
      accent: visual.accent,
      size: 40,
      iconSize: 22,
    );
    final name = Text(
      row.title,
      style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
    );
    final detail = Text(
      row.detail,
      style: AppTextStyles.bodyRegular.copyWith(color: colors.textSecondary),
    );
    final fraction = row.fraction;
    final bar = fraction == null
        ? null
        : goalBar(
            value: fraction,
            accent: visual.accent,
            semanticLabel: row.detail,
          );
    final pill = _StatusPill(status: row.status);

    return Semantics(
      container: true,
      button: tappable,
      label: tappable ? '${row.spoken}, öffnen' : row.spoken,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.listRowMinHeight),
        child: TapSurface(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  context.isLargeText || constraints.maxWidth < _stackWidth;
              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              tile,
                              const SizedBox(width: AppSpacing.s12),
                              Expanded(child: name),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.s8),
                          pill,
                          const SizedBox(height: AppSpacing.s8),
                          detail,
                          if (bar != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.s8),
                            bar,
                          ],
                        ],
                      )
                    : Stack(
                        children: <Widget>[
                          Padding(
                            padding: EdgeInsets.only(right: tappable ? 28 : 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                tile,
                                const SizedBox(width: AppSpacing.s12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Row(
                                        children: <Widget>[
                                          Expanded(child: name),
                                          const SizedBox(width: AppSpacing.s8),
                                          pill,
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      detail,
                                      if (bar != null) ...<Widget>[
                                        const SizedBox(height: 6),
                                        bar,
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (tappable)
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Icon(
                                  AppIcon.chevronRight.data,
                                  size: 20,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The status of a goal as a small pill: "Offen" quiet, "Erreicht", "Ruhetag"
/// and "Übersprungen" on the green tint with their symbol.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final GoalRowStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final open = status == GoalRowStatus.open;
    final icon = switch (status) {
      GoalRowStatus.open => null,
      GoalRowStatus.reached => AppIcon.check.data,
      GoalRowStatus.rest => workoutRestIcon,
      GoalRowStatus.skipped => workoutSkipIcon,
    };
    final foreground = open ? colors.textSecondary : colors.primaryText;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: open ? colors.surfaceMuted : colors.primaryTint,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: AppSpacing.s4),
            ],
            Flexible(
              child: Text(
                status.label,
                style: AppTextStyles.captionStrong.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
