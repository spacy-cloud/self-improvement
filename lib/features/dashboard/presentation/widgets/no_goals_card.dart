import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// The day overview without an applicable daily goal: an honest text and the
/// way to set goals, never a ring that reads 0 of 0.
///
/// For a day that is not today ([pastDay], BS-93) there is nothing to set: goals
/// apply from tomorrow, so the card only says that no daily goal counted on that
/// day, and has no button.
class NoGoalsCard extends StatelessWidget {
  /// Creates the card; [onSetGoals] opens the goals editor.
  const NoGoalsCard({this.onSetGoals, this.pastDay = false, super.key});

  /// Opens the goals editor ("Ziele festlegen"); `null` hides the button.
  final VoidCallback? onSetGoals;

  /// Whether the card is the one of a day that is not today.
  final bool pastDay;

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
              pastDay
                  ? 'Keine Tagesziele an diesem Tag'
                  : 'Noch keine Tagesziele',
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            pastDay
                ? 'An diesem Tag galt kein Tagesziel. Ziele, die du festlegst, '
                      'gelten ab morgen.'
                : 'Lege fest, was du jeden Tag erreichen möchtest. Dann füllt '
                      'sich hier dein Tagesring.',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (onSetGoals != null && !pastDay) ...<Widget>[
            const SizedBox(height: AppSpacing.s16),
            SecondaryButton(label: 'Ziele festlegen', onPressed: onSetGoals),
          ],
        ],
      ),
    );
  }
}
