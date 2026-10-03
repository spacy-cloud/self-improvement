import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/bootstrap/app_services.dart';
import 'package:self_improvement/app/feedback/snack_bar_feedback_service.dart';
import 'package:self_improvement/app/router/app_router.dart';
import 'package:self_improvement/core/backup/backup_ports.dart';
import 'package:self_improvement/core/backup/backup_providers.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/platform/reminder_platform.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/data_epoch.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';

/// The provider overrides of the running app: the opened database, the clock,
/// the router, the snack bar feedback, and the integration of the reminder
/// and backup engines. Test overrides are appended after these.
List<Override> buildAppOverrides({
  required AppServices services,
  required List<SelfImprovementModule> modules,
  required GoRouter router,
  required GlobalKey<NavigatorState> navigatorKey,
  required double Function() feedbackBottomOffset,
}) {
  return <Override>[
    appDatabaseProvider.overrideWithValue(services.database),
    clockProvider.overrideWithValue(services.clock),
    deviceTimeZoneSourceProvider.overrideWithValue(services.zoneSource),
    appModulesProvider.overrideWithValue(modules),
    appRouterProvider.overrideWithValue(router),
    feedbackServiceProvider.overrideWith(
      (ref) => SnackBarFeedbackService(
        context: () => navigatorKey.currentContext,
        ids: ref.watch(idGeneratorProvider),
        bottomOffset: feedbackBottomOffset,
      ),
    ),
    // Reminders: water reminders stop once today's water goal is reached.
    waterGoalReachedTodayProvider.overrideWith(
      (ref) => () async {
        final today = ref.read(clockProvider).today();
        final status = await ref
            .read(dayStatusRepositoryProvider)
            .statusFor(today);
        return status?.goals.any(
              (goal) =>
                  goal.goalKey == GoalType.water.key &&
                  goal.applicable &&
                  goal.fulfilled,
            ) ??
            false;
      },
    ),
    // Backup: after an import or a reset the system notifications are
    // cancelled and the app refreshes what it caches.
    notificationCancellerProvider.overrideWith(
      (ref) =>
          PlatformNotificationCanceller(ref.watch(reminderPlatformProvider)),
    ),
    backupListenerProvider.overrideWith(AppBackupListener.new),
  ];
}

/// Cancels every pending system notification of the app (the reminder
/// platform's own list).
final class PlatformNotificationCanceller implements NotificationCanceller {
  const PlatformNotificationCanceller(this._platform);

  final ReminderPlatform _platform;

  @override
  Future<void> cancelAllNotifications() => _platform.cancelAllPending();
}

/// What the app does after ALL data was replaced (import or reset): bump the
/// data epoch (feature providers and tickers that cache more than a database
/// stream follow it), refresh the core providers, re-read today, and plan the
/// reminders again from the new rules. Database streams refresh by
/// themselves. Never throws for the caller: the backup engine reports a
/// failing follow-up without undoing the replace.
final class AppBackupListener implements BackupListener {
  AppBackupListener(this._ref);

  final Ref _ref;

  @override
  Future<void> onDataReplaced() async {
    _ref.read(dataEpochProvider.notifier).bump();
    _ref
      ..invalidate(profileProvider)
      ..invalidate(appSettingsProvider)
      ..invalidate(moduleStatusesProvider)
      ..invalidate(dashboardCardsProvider)
      ..invalidate(goalVersionsProvider)
      ..invalidate(todayStatusProvider)
      ..invalidate(streakProvider)
      ..invalidate(openFocusSessionProvider);
    _ref.read(todayProvider.notifier).refresh();
    await _ref.read(reminderServiceProvider).reconcile();
  }
}
