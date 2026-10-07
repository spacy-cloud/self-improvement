import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';

/// A goal value chosen in onboarding (or the default).
@immutable
final class GoalSetting {
  const GoalSetting({this.target, this.enabled = true});

  /// Null means the default of the goal type.
  final int? target;
  final bool enabled;
}

/// Everything onboarding collects. Every field is optional and voluntary.
///
/// [OnboardingDraft.skipped] is the "Überspringen" result: all five modules,
/// default goals, no name and NO body data.
@immutable
final class OnboardingDraft {
  const OnboardingDraft({
    this.displayName,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.motivationGoals = const [],
    this.enabledModules = const {...ModuleId.values},
    this.goals = const {},
  });

  /// Skipping onboarding: standard modules and goals, nothing invented.
  const OnboardingDraft.skipped() : this();

  final String? displayName;
  final int? heightCm;
  final int? ageYears;
  final int? startWeightGrams;

  /// Voluntary preference ids (`lose_weight`, ...). No pre-selection, no
  /// derived recommendations.
  final List<String> motivationGoals;

  /// Selected modules; may be empty (all modules off is allowed).
  final Set<ModuleId> enabledModules;

  /// Overrides per goal type; missing types use their defaults.
  final Map<GoalType, GoalSetting> goals;
}

/// Completes onboarding atomically.
///
/// ONE command: profile values, module activation history, goal versions
/// effective from today and the default dashboard cards are written together;
/// `onboarding_completed` becomes true only with that commit. Entered body
/// values are profile data, never weight measurements. A goal that is off by
/// default ([GoalType.defaultEnabled], the daily workout goal) gets no version
/// unless the draft sets it.
class OnboardingRepository {
  OnboardingRepository({
    required this._database,
    required this._runner,
    required this._goals,
  });

  static const String completeType = 'onboarding.complete';

  final AppDatabase _database;
  final CommandRunner _runner;
  final GoalVersionRepository _goals;

  /// Completes (or skips) onboarding. A second completion is a conflict.
  Future<CommandOutcome> complete({
    required String commandId,
    required OnboardingDraft draft,
  }) {
    return _runner.run(
      commandId: commandId,
      type: completeType,
      body: (ctx) async {
        final values = validateProfileValues(
          displayName: draft.displayName,
          heightCm: draft.heightCm,
          ageYears: draft.ageYears,
          startWeightGrams: draft.startWeightGrams,
          motivationGoals: draft.motivationGoals,
        );
        final goalErrors = <String, String>{};
        for (final entry in draft.goals.entries) {
          final target = entry.value.target;
          if (target != null && !entry.key.validateTarget(target).isValid) {
            goalErrors[entry.key.key] = 'Ungültiger Zielwert.';
          }
        }
        if (goalErrors.isNotEmpty) {
          throw ValidationFailure(goalErrors);
        }

        final profile = await _database
            .select(_database.profile)
            .getSingleOrNull();
        if (profile == null) {
          throw const NotFoundFailure(entity: 'profile');
        }
        if (profile.onboardingCompleted) {
          throw const ConflictFailure(ConflictKind.invalidState);
        }

        final today = ctx.today;
        await (_database.update(
          _database.profile,
        )..where((p) => p.id.equals('local'))).write(
          ProfileCompanion(
            displayName: Value(values.displayName),
            heightCm: Value(values.heightCm),
            ageYears: Value(values.ageYears),
            startWeightGrams: Value(values.startWeightGrams),
            motivationGoals: Value(values.motivationGoals),
            startedLocalDate: Value(today),
            onboardingCompleted: const Value(true),
            updatedAtUtc: Value(ctx.nowUtc),
            rowVersion: Value(profile.rowVersion + 1),
          ),
        );

        for (final module in ModuleId.values) {
          await _database
              .into(_database.moduleStatusHistory)
              .insert(
                ModuleStatusHistoryCompanion.insert(
                  id: ctx.ids.newId(),
                  moduleId: module.key,
                  effectiveAtUtc: ctx.nowUtc,
                  localDate: today,
                  enabled: draft.enabledModules.contains(module),
                ),
              );
        }

        for (final type in GoalType.values) {
          final chosen = draft.goals[type];
          if (chosen == null && !type.defaultEnabled) {
            // "No version" means off (the optional daily workout goal): only
            // an explicit choice writes a version for such a goal.
            continue;
          }
          final setting = chosen ?? const GoalSetting();
          await _goals.upsert(
            GoalVersion(
              type: type,
              target: type.resolveTarget(setting.target),
              enabled: setting.enabled,
              effectiveFrom: today,
            ),
            newId: ctx.ids.newId(),
            nowUtc: ctx.nowUtc,
          );
        }

        var index = 0;
        for (final card in SchemaKeys.defaultCardOrder) {
          await _database
              .into(_database.dashboardCards)
              .insert(
                DashboardCardsCompanion.insert(
                  cardId: card,
                  moduleId: SchemaKeys.dashboardCardModule[card]!,
                  sortIndex: index++,
                ),
              );
        }

        return CommandEffect(
          entityId: 'local',
          affectedDays: {today},
          extraEvents: const [GoalsChanged()],
        );
      },
    );
  }
}
