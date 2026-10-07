import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/dashboard/domain/dashboard_layout.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/dashboard/application/day_browser_providers.dart';
import 'package:self_improvement/features/dashboard/data/dashboard_activity_repository.dart';
import 'package:self_improvement/features/dashboard/domain/card_configuration.dart';
import 'package:self_improvement/features/dashboard/domain/day_browser.dart';
import 'package:self_improvement/features/dashboard/domain/first_entry_action.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The modules whose cards and quick actions the dashboard shows: the five
/// bundled modules. Tests replace it with fake modules.
final dashboardModulesProvider = Provider<List<SelfImprovementModule>>(
  (ref) => bundledModules,
);

final dashboardActivityRepositoryProvider =
    Provider<DashboardActivityRepository>(
      (ref) => DashboardActivityRepository(ref.watch(appDatabaseProvider)),
    );

/// Whether any record exists at all (drives the first-day welcome hint).
final hasAnyEntryProvider = StreamProvider<bool>(
  (ref) => ref.watch(dashboardActivityRepositoryProvider).watchHasAnyEntry(),
);

/// Everything the Home screen shows, derived from the live providers.
///
/// Home shows one day: today, or one of the days before it (BS-93). The status
/// of that day, the goals of that day and the cards all follow [day].
@immutable
final class DashboardView {
  const DashboardView({
    required this.day,
    required this.dayStatus,
    required this.entries,
    required this.emptyReason,
    required this.moduleStatuses,
    required this.showWelcome,
    required this.welcomeName,
    required this.firstEntry,
    required this.quickStarts,
  });

  /// The day shown and its place between the oldest reachable day and today.
  final BrowsedDay day;

  /// Today's local date.
  LocalDate get today => day.today;

  /// Status of the day shown (the ring): its goals and thresholds from the
  /// snapshot of THAT day and its facts. `null` when no snapshot exists.
  final DayStatus? dayStatus;

  /// The cards to show, in display order.
  final List<DashboardEntry> entries;

  /// Why [entries] is empty, or `none`.
  final DashboardEmptyReason emptyReason;

  /// Which modules are on right now.
  final Map<ModuleId, bool> moduleStatuses;

  /// Whether the first-day welcome hint is shown: nothing has been recorded
  /// yet and today is the first day of the profile.
  final bool showWelcome;

  /// The entered profile name for the greeting, or `null`.
  final String? welcomeName;

  /// The entry the welcome hint opens, or `null` when no module offers one.
  final QuickAction? firstEntry;

  /// The starting points listed under the welcome hint.
  final List<QuickStart> quickStarts;

  /// Whether the module "Fortschritt" (XP, level, streak) is on.
  bool get gamificationEnabled => moduleStatuses[ModuleId.gamification] ?? true;

  /// Whether the ring can be drawn: at least one applicable daily goal.
  bool get hasRing => dayStatus != null && dayStatus!.hasApplicableGoals;
}

/// The Home screen model. Loading until the card configuration, the module
/// statuses and the status of the day shown arrived (today, or the day the
/// person paged to, BS-93); an error in one of them is an error of the model.
/// The welcome hint is best effort: a failing profile or activity query only
/// means "no welcome hint", never a broken dashboard.
final dashboardViewProvider = Provider<AsyncValue<DashboardView>>((ref) {
  final modules = ref.watch(dashboardModulesProvider);
  final configs = ref.watch(dashboardCardsProvider);
  final statuses = ref.watch(moduleStatusesProvider);
  final browsed = ref.watch(browsedDayProvider);
  // Today keeps its own stream (the live status the rest of the app reads);
  // another day reads the status of that day from its snapshot.
  final day = browsed.isToday
      ? ref.watch(todayStatusProvider)
      : ref.watch(dayStatusProvider(browsed.date));
  final today = browsed.today;
  final profile = ref.watch(profileProvider);
  final hasAny = ref.watch(hasAnyEntryProvider);

  final required = <AsyncValue<Object?>>[configs, statuses, day];
  for (final input in required) {
    if (input.hasError) {
      return AsyncError<DashboardView>(
        input.error!,
        input.stackTrace ?? StackTrace.empty,
      );
    }
  }
  final bestEffort = <AsyncValue<Object?>>[profile, hasAny];
  if (required.any((input) => !input.hasValue) ||
      bestEffort.any((input) => !input.hasValue && !input.hasError)) {
    return const AsyncLoading<DashboardView>();
  }

  final moduleStatuses = statuses.requireValue;
  final entries = visibleDashboardEntries(
    configs: configs.requireValue,
    moduleStatuses: moduleStatuses,
    modules: modules,
  );
  final emptyReason = dashboardEmptyReason(
    shown: entries,
    moduleStatuses: moduleStatuses,
  );
  final actions = availableQuickActions(
    modules: modules,
    moduleStatuses: moduleStatuses,
  );
  final profileValue = profile.value;
  final noEntryYet = hasAny.hasValue && !hasAny.requireValue;
  final firstDay = profileValue != null && profileValue.startedOn == today;
  return AsyncData<DashboardView>(
    DashboardView(
      day: browsed,
      dayStatus: day.value,
      entries: entries,
      emptyReason: emptyReason,
      moduleStatuses: moduleStatuses,
      showWelcome:
          firstDay &&
          noEntryYet &&
          emptyReason != DashboardEmptyReason.allModulesOff,
      welcomeName: profileValue?.displayName,
      firstEntry: firstEntryAction(actions),
      quickStarts: quickStartEntries(actions),
    ),
  );
});

/// The cards of enabled modules for the configuration page, visible or hidden,
/// in stored order.
final configurableCardsProvider = Provider<AsyncValue<List<ConfigurableCard>>>((
  ref,
) {
  final modules = ref.watch(dashboardModulesProvider);
  final configs = ref.watch(dashboardCardsProvider);
  final statuses = ref.watch(moduleStatusesProvider);
  if (configs.hasError) {
    return AsyncError<List<ConfigurableCard>>(
      configs.error!,
      configs.stackTrace ?? StackTrace.empty,
    );
  }
  if (statuses.hasError) {
    return AsyncError<List<ConfigurableCard>>(
      statuses.error!,
      statuses.stackTrace ?? StackTrace.empty,
    );
  }
  if (!configs.hasValue || !statuses.hasValue) {
    return const AsyncLoading<List<ConfigurableCard>>();
  }
  return AsyncData<List<ConfigurableCard>>(
    configurableDashboardCards(
      configs: configs.requireValue,
      moduleStatuses: statuses.requireValue,
      modules: modules,
    ),
  );
});

/// How many stored cards are not listed on the configuration page because
/// their module is switched off.
final cardsOfOffModulesProvider = Provider<int>((ref) {
  final configs = ref.watch(dashboardCardsProvider).value;
  final statuses = ref.watch(moduleStatusesProvider).value;
  if (configs == null || statuses == null) {
    return 0;
  }
  return hiddenByModuleCount(
    configs: configs,
    moduleStatuses: statuses,
    modules: ref.watch(dashboardModulesProvider),
  );
});

/// Re-reads everything the Home screen depends on ("Erneut versuchen").
void reloadDashboard(WidgetRef ref) {
  ref
    ..invalidate(dashboardCardsProvider)
    ..invalidate(moduleStatusesProvider)
    ..invalidate(todayStatusProvider)
    ..invalidate(dayStatusProvider)
    ..invalidate(hasAnyEntryProvider);
}
