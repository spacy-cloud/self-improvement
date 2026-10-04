import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_ui_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';

/// The `focus` card of the dashboard.
///
/// Without an open session: today's saved focus time against the daily goal;
/// tapping opens the start screen. With an open session: its state and the
/// remaining time (whole minutes, so the card does not change every second)
/// and the way back to it ("Fokus fortsetzen").
class FocusDashboardCard extends ConsumerWidget {
  const FocusDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(focusSessionProvider)
        .when(
          loading: () => MetricCard(
            title: 'Fokus',
            value: '–',
            icon: AppIcon.focus.data,
            accent: AppAccent.focus,
          ),
          error: (error, stack) =>
              ErrorState(onRetry: () => ref.invalidate(focusSessionProvider)),
          data: (session) => session == null
              ? const _TodayCard()
              : _OpenSessionCard(session: session),
        );
  }
}

class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(focusTodaySummaryProvider)
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
                ..invalidate(focusSessionsTodayProvider)
                ..invalidate(goalVersionsProvider);
            },
          ),
          data: (summary) {
            final goal = summary.goalMinutes;
            final caption = focusTodayCaption(summary);
            return MetricCard(
              title: 'Fokus',
              value: '${summary.completedMinutes}',
              unit: goal == null ? 'Min.' : null,
              target: goal == null ? null : '/ $goal Min.',
              progress: summary.goalFraction,
              progressVariant: AppProgressVariant.focus,
              progressSemanticLabel: focusTodaySpoken(summary),
              subtitle: caption,
              icon: AppIcon.focus.data,
              accent: AppAccent.focus,
              onTap: () => context.push(FocusRoutes.start),
              semanticLabel: 'Fokus, ${focusTodaySpoken(summary)}, $caption',
            );
          },
        );
  }
}

class _OpenSessionCard extends ConsumerWidget {
  const _OpenSessionCard({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minutes = ref.watch(focusRemainingMinutesProvider);
    final status = session.status;
    final remaining = switch (status) {
      FocusStatus.running =>
        minutes == null
            ? session.plannedSeconds - session.accumulatedSeconds
            : minutes * 60,
      FocusStatus.paused => session.plannedSeconds - session.accumulatedSeconds,
      _ => 0,
    };
    final value = focusOpenCardValue(status);
    final subtitle = focusOpenCardSubtitle(
      status: status,
      category: session.category,
      remainingSeconds: remaining,
    );
    final resume = focusResumeLabel(status);
    return MetricCard(
      title: 'Fokus',
      value: value,
      subtitle: subtitle,
      icon: AppIcon.focus.data,
      accent: AppAccent.focus,
      onTap: () => context.push(FocusRoutes.session),
      semanticLabel: 'Fokus, $value, $subtitle',
      quickAction: MetricCardAction(
        label: resume,
        icon: Icons.play_arrow_rounded,
        accent: AppAccent.focus,
        onPressed: () => context.push(FocusRoutes.session),
      ),
    );
  }
}
