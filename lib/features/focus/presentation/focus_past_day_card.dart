import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The `focus` card of Home for a day that is not today (BS-93): the saved focus
/// time of the sessions completed on [day] against the goal of that day.
///
/// It only shows. The open session, "Fokus fortsetzen" and starting one belong
/// to the present and are not offered here; the card opens the start screen,
/// like the live card does. A day without a session reads "Keine Sitzung an
/// diesem Tag" and no number.
class FocusPastDayCard extends ConsumerWidget {
  /// Creates the card of [day].
  const FocusPastDayCard({required this.day, super.key});

  /// The day shown.
  final LocalDate day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(focusDaySummaryProvider(day))
        .when(
          loading: () => MetricCard(
            title: 'Fokus',
            value: '–',
            icon: AppIcon.focus.data,
            accent: AppAccent.focus,
          ),
          error: (error, stack) => ErrorState(
            onRetry: () {
              ref
                ..invalidate(focusSessionsOnProvider(day))
                ..invalidate(goalVersionsProvider);
            },
          ),
          data: (summary) => _build(context, summary),
        );
  }

  Widget _build(BuildContext context, FocusTodaySummary summary) {
    final goal = summary.goalMinutes;
    final caption = focusDayCaption(summary);
    final spoken = focusDaySpoken(summary);
    final empty = summary.isEmpty;
    return MetricCard(
      title: 'Fokus',
      value: empty ? '–' : '${summary.completedMinutes}',
      unit: empty || goal != null ? null : 'Min.',
      target: goal == null ? null : '/ $goal Min.',
      progress: empty ? null : summary.goalFraction,
      progressVariant: AppProgressVariant.focus,
      progressSemanticLabel: spoken,
      subtitle: caption,
      icon: AppIcon.focus.data,
      accent: AppAccent.focus,
      onTap: () => context.push(FocusRoutes.start),
      semanticLabel: empty ? 'Fokus, $spoken' : 'Fokus, $spoken, $caption',
    );
  }
}
