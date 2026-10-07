import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';

/// The head of "Ziele heute": the day ring with "x von y", the date, the
/// headline "x von y erreicht" and one sentence.
///
/// The ring is the one of Home (`ProgressRing.goals`, which alone picks its
/// colour by the stand of the goals), drawn from the same two numbers. For a
/// screen reader the card is one element that says the date, the headline and
/// the sentence; the ring, a picture of the same numbers, is not read a second
/// time.
class GoalsSummaryCard extends StatelessWidget {
  /// Creates the card of [day] (at least one goal applies).
  const GoalsSummaryCard({required this.day, super.key});

  /// The day shown.
  final GoalsDay day;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final ring = ProgressRing.goals(
      fulfilled: day.fulfilled,
      applicable: day.applicable,
      size: 96,
      semanticLabel: day.ringLabel,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${day.fulfilled} von ${day.applicable}',
            maxLines: 1,
            style: AppTextStyles.titleSection.copyWith(
              color: colors.textPrimary,
            ),
          ),
          Text(
            day.ringUnit,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final heading = Text(
      day.title,
      style: AppTextStyles.titleSection.copyWith(color: colors.textPrimary),
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          day.dateText,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        if (day.isComplete)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  AppIcon.trophy.data,
                  size: 20,
                  color: colors.accent(AppAccent.gamification),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: heading),
            ],
          )
        else
          heading,
        const SizedBox(height: AppSpacing.s4),
        Text(
          day.sentence,
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
    return AppCard(
      child: Semantics(
        container: true,
        label: day.summarySpoken,
        excludeSemantics: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = context.isLargeText || constraints.maxWidth < 280;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[ring, const SizedBox(height: 14), texts],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                ring,
                const SizedBox(width: AppSpacing.s16),
                Expanded(child: texts),
              ],
            );
          },
        ),
      ),
    );
  }
}
