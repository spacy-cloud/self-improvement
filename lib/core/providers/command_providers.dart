import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/modules/dashboard_card_repository.dart';
import 'package:self_improvement/core/modules/module_manager.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_commands.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/settings/settings_commands.dart';

/// Atomic onboarding completion (also used for "Überspringen").
final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
    goals: ref.watch(goalVersionRepositoryProvider),
  ),
);

/// Module activation commands.
final moduleManagerProvider = Provider<ModuleManager>(
  (ref) => ModuleManager(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
    status: ref.watch(moduleStatusRepositoryProvider),
  ),
);

final dashboardCardRepositoryProvider = Provider<DashboardCardRepository>(
  (ref) => DashboardCardRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

/// All dashboard cards in display order (hidden ones included).
final dashboardCardsProvider = StreamProvider<List<DashboardCardConfig>>(
  (ref) => ref.watch(dashboardCardRepositoryProvider).watchCards(),
);

final goalsCommandsProvider = Provider<GoalsCommands>(
  (ref) => GoalsCommands(
    runner: ref.watch(commandRunnerProvider),
    versions: ref.watch(goalVersionRepositoryProvider),
  ),
);

final profileCommandsProvider = Provider<ProfileCommands>(
  (ref) => ProfileCommands(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);

final settingsCommandsProvider = Provider<SettingsCommands>(
  (ref) => SettingsCommands(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
  ),
);
