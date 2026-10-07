import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goal_row_tile.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goals_summary_card.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/not_today_banner.dart';

/// The content of "Ziele heute" for one [GoalsDay]: the ring with the numbers,
/// the list of the daily goals with their stand, target and status, and the
/// weekly workout goal apart from them.
///
/// It only shows what the model says; the model carries the numbers of the day
/// ring, so the page can never disagree with Home. Without a daily goal it
/// shows "Noch keine Tagesziele" and the way to the goal editor instead of a
/// ring that reads 0 of 0. A day that is not today gets the note "Nicht heute".
class GoalsDayView extends StatelessWidget {
  /// Creates the view of [day].
  const GoalsDayView({
    required this.day,
    required this.onSetGoals,
    this.onBackToToday,
    super.key,
  });

  /// The day shown.
  final GoalsDay day;

  /// Opens the goal editor from the empty state ("Ziele festlegen").
  final VoidCallback onSetGoals;

  /// Goes back to today from the note of a past day; `null` hides the action.
  final VoidCallback? onBackToToday;

  @override
  Widget build(BuildContext context) {
    final weekly = day.weekly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!day.isToday) ...<Widget>[
          NotTodayBanner(date: day.date, onBackToToday: onBackToToday),
          const SizedBox(height: AppSpacing.s12),
        ],
        if (day.hasGoals) ...<Widget>[
          GoalsSummaryCard(day: day),
          AppSectionHeader.group(title: day.listTitle),
          const SizedBox(height: AppSpacing.s4),
          AppListGroup(
            children: <Widget>[
              for (final row in day.rows) GoalRowTile(row: row),
            ],
          ),
        ] else
          EmptyState(
            title: 'Noch keine Tagesziele',
            message:
                'Lege fest, was du täglich erreichen willst. Dann siehst du '
                'hier deinen Fortschritt.',
            actionLabel: 'Ziele festlegen',
            onAction: onSetGoals,
          ),
        if (weekly != null) ...<Widget>[
          const SizedBox(height: AppSpacing.s8),
          const AppSectionHeader.group(
            title: 'Wochenziel · nicht im Tagesring',
          ),
          const SizedBox(height: AppSpacing.s4),
          AppListGroup(children: <Widget>[GoalRowTile(row: weekly)]),
        ],
      ],
    );
  }
}
