import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/presentation/focus_dashboard_card.dart';
import 'package:self_improvement/features/focus/presentation/focus_history_screen.dart';
import 'package:self_improvement/features/focus/presentation/focus_past_day_card.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_session_detail_screen.dart';
import 'package:self_improvement/features/focus/presentation/focus_session_screen.dart';
import 'package:self_improvement/features/focus/presentation/focus_start_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_dashboard_card.dart';
import 'package:self_improvement/features/focus/presentation/workout_form_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_history_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_overview_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_past_day_card.dart';

/// The `focus` module: the persistent focus timer (start, running, paused and
/// confirmation screens, history) and manual workouts (form, week overview,
/// all workouts), with their dashboard cards and plus menu entries.
///
/// An open focus session blocks switching the module off (`canDeactivate`):
/// the user resolves it first on [FocusRoutes.session] (save or discard).
final class FocusModule extends SelfImprovementModule {
  const FocusModule();

  @override
  ModuleId get id => ModuleId.focus;

  @override
  String get title => 'Fokus & Workouts';

  @override
  String get description => 'Fokus-Timer und Trainings';

  @override
  IconData get icon => Icons.schedule_rounded;

  /// Static paths come before the parametric ones (`/workouts/new` and
  /// `/workouts/all` before `/workouts/:id`).
  @override
  List<RouteBase> get routes => [
    GoRoute(
      path: FocusRoutes.start,
      builder: (context, state) => const FocusStartScreen(),
    ),
    GoRoute(
      path: FocusRoutes.session,
      builder: (context, state) => const FocusSessionScreen(),
    ),
    GoRoute(
      path: FocusRoutes.history,
      builder: (context, state) => const FocusHistoryScreen(),
    ),
    GoRoute(
      path: FocusRoutes.historyDetailPattern,
      builder: (context, state) =>
          FocusSessionDetailScreen(sessionId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: WorkoutRoutes.overview,
      builder: (context, state) => const WorkoutOverviewScreen(),
    ),
    GoRoute(
      path: WorkoutRoutes.create,
      builder: (context, state) => const WorkoutFormScreen(),
    ),
    GoRoute(
      path: WorkoutRoutes.all,
      builder: (context, state) => const WorkoutHistoryScreen(),
    ),
    GoRoute(
      path: WorkoutRoutes.editPattern,
      builder: (context, state) =>
          WorkoutFormScreen(entryId: state.pathParameters['id']),
    ),
  ];

  @override
  List<DashboardCardDescriptor> get dashboardCards => [
    DashboardCardDescriptor(
      cardId: 'workout',
      title: 'Workout',
      defaultRank: 3,
      builder: (context, ref) => const WorkoutDashboardCard(),
      dayBuilder: (context, ref, day) => WorkoutPastDayCard(day: day),
    ),
    DashboardCardDescriptor(
      cardId: 'focus',
      title: 'Fokus',
      defaultRank: 4,
      builder: (context, ref) => const FocusDashboardCard(),
      dayBuilder: (context, ref, day) => FocusPastDayCard(day: day),
    ),
  ];

  /// The plus menu: "Workout" (position 1) and "Fokus" (position 4). While a
  /// session is open the entry reads "Fokus fortsetzen"; the start screen then
  /// offers the way back to the session instead of a second start.
  @override
  List<QuickAction> get quickActions => [
    QuickAction(
      id: 'workout',
      label: 'Workout',
      icon: AppIcon.workout.data,
      route: WorkoutRoutes.create,
      plusOrder: 1,
    ),
    QuickAction(
      id: 'focus',
      label: 'Fokus',
      icon: AppIcon.focus.data,
      route: FocusRoutes.start,
      plusOrder: 4,
      dynamicLabel: (ref) => ref.watch(focusSessionProvider).value == null
          ? 'Fokus'
          : 'Fokus fortsetzen',
    ),
  ];

  /// Starts the foreground side of the timer: an open session is restored from
  /// its persisted segments (a running session that is past its planned end
  /// becomes "awaiting confirmation"). Idempotent; a storage problem does not
  /// stop the app from starting (the screens report it themselves).
  @override
  Future<void> initialize(Ref ref) async {
    try {
      await ref.read(focusRestorerProvider).restore();
    } on AppFailure {
      // Reported by the focus screens when they read the session.
    }
  }

  /// Refuses to switch the module off while a session is open. Nothing is
  /// deleted or discarded silently: the user saves or discards the session on
  /// [focusDeactivationResolveRoute] first.
  @override
  Future<DeactivationCheck> canDeactivate(Ref ref) async {
    final open = await ref.read(focusRepositoryProvider).findOpen();
    if (open == null) {
      return const CanDeactivate();
    }
    if (open.status == FocusStatus.awaitingConfirmation) {
      return const MustResolveFirst(
        message:
            'Eine Fokus-Sitzung wartet noch auf deine Bestätigung. Speichere '
            'oder verwirf sie, bevor du das Modul ausschaltest.',
        resolveLabel: 'Sitzung zuerst bestätigen',
      );
    }
    return const MustResolveFirst(
      message:
          'Es läuft noch eine Fokus-Sitzung. Speichere oder verwirf sie, '
          'bevor du das Modul ausschaltest.',
      resolveLabel: 'Sitzung zuerst beenden',
    );
  }
}
