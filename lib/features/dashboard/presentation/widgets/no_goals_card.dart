import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// The day overview without an applicable daily goal: an honest text and the
/// way to set goals, never a ring that reads 0 of 0.
class NoGoalsCard extends StatelessWidget {
  /// Creates the card; [onSetGoals] opens the goals editor.
  const NoGoalsCard({required this.onSetGoals, super.key});

  /// Opens the goals editor ("Ziele festlegen").
  final VoidCallback onSetGoals;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text(
              'Noch keine Tagesziele',
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Lege fest, was du jeden Tag erreichen möchtest. Dann füllt sich '
            'hier dein Tagesring.',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.s16),
          SecondaryButton(label: 'Ziele festlegen', onPressed: onSetGoals),
        ],
      ),
    );
  }
}
