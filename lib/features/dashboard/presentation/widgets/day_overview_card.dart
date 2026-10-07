import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';

/// The day overview: the ring with "x von y" in the middle, the title of the day
/// (one of the three neutral texts of the stand of the goals) and a factual
/// sentence about today's goals.
///
/// Only for a day with at least one applicable goal; without one the dashboard
/// shows "Noch keine Tagesziele" instead, never a 0/0 ring. The ring is a
/// picture of the same numbers that the text says, and it has its own spoken
/// label. Its arc colour follows the stand (grey, yellow, green) and is chosen
/// by `ProgressRing.goals`, not here, so that every day ring looks the same.
class DayOverviewCard extends StatelessWidget {
  /// Creates the card for [fulfilled] of [applicable] goals (applicable >= 1).
  const DayOverviewCard({
    required this.fulfilled,
    required this.applicable,
    this.motivation,
    super.key,
  }) : assert(applicable >= 1, 'The ring needs at least one applicable goal');

  /// Goals reached today.
  final int fulfilled;

  /// Goals that apply today.
  final int applicable;

  /// The title of the day (`motivationTextFor`), or `null` for no title: the
  /// texts speak of "today", so a past day shows only the factual sentence.
  final String? motivation;

  /// The spoken text of the ring.
  String get ringLabel => applicable == 1
      ? '$fulfilled von 1 Ziel erreicht'
      : '$fulfilled von $applicable Zielen erreicht';

  /// The factual sentence next to the ring.
  String get summary {
    if (fulfilled >= applicable) {
      return applicable == 1
          ? 'Du hast heute dein Tagesziel erreicht.'
          : 'Du hast heute alle Tagesziele erreicht.';
    }
    if (fulfilled == 0) {
      return 'Du hast heute noch kein Ziel erreicht.';
    }
    return 'Du hast heute $fulfilled von $applicable Zielen erreicht.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final ring = ProgressRing.goals(
      fulfilled: fulfilled,
      applicable: applicable,
      semanticLabel: ringLabel,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '$fulfilled von $applicable',
            maxLines: 1,
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
          Text(
            applicable == 1 ? 'Ziel' : 'Zielen',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final title = motivation;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Text(
            title,
            style: AppTextStyles.titleSection.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
        Text(
          summary,
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = context.isLargeText || constraints.maxWidth < 280;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(child: ring),
                const SizedBox(height: AppSpacing.s16),
                texts,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ring,
              const SizedBox(width: AppSpacing.s24),
              Expanded(child: texts),
            ],
          );
        },
      ),
    );
  }
}
