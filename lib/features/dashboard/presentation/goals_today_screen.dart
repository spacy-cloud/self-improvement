import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/application/goals_today_providers.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/dashboard_routes.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/async_body.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/goals_day_view.dart';

/// "Ziele heute" (`/goals/today`): every daily goal of today with its stand,
/// target and status, the ring of Home in the same numbers, and the weekly
/// workout goal apart from them.
///
/// Opened by the day card on Home. The numbers are the ones of
/// `DashboardView.dayStatus`, the status the ring counts; the screen holds no
/// rule and calculates nothing. Back leads to where it was opened, or to Home
/// after a deep link. States: loading (a neutral line only when it takes a
/// moment), error with retry, no daily goal ("Noch keine Tagesziele") and the
/// list.
class GoalsTodayScreen extends ConsumerWidget {
  /// Creates the screen.
  const GoalsTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(goalsTodayProvider);
    return AppScaffold.subpage(
      title: 'Ziele heute',
      onBack: () => leaveToHome(context),
      body: AsyncBody<GoalsDay>(
        value: day,
        onRetry: () => reloadGoalsToday(ref),
        data: (day) => GoalsDayView(
          day: day,
          onSetGoals: () => context.push(DashboardRoutes.goals),
        ),
      ),
    );
  }
}
