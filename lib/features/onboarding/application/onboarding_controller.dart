import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/domain/body_values_input.dart';
import 'package:self_improvement/features/onboarding/domain/daily_goal_stepper.dart';
import 'package:self_improvement/features/onboarding/domain/onboarding_options.dart';

/// Outcome of finishing or skipping the onboarding.
sealed class OnboardingSubmitResult {
  const OnboardingSubmitResult();
}

/// The completion command committed (or had committed before: a replay or an
/// already finished onboarding). The screen leaves for the dashboard.
final class OnboardingCompleted extends OnboardingSubmitResult {
  const OnboardingCompleted({this.alreadyCompleted = false});

  /// True when the profile was already marked as onboarded (a second
  /// completion with a different command id): nothing was written.
  final bool alreadyCompleted;
}

/// Nothing was committed and nothing needs a message: the input was invalid
/// (the step shows the field errors) or a completion is already running.
final class OnboardingRejected extends OnboardingSubmitResult {
  const OnboardingRejected();
}

/// Persisting failed. Nothing was committed, all input is kept and a retry
/// uses the same command id.
final class OnboardingFailed extends OnboardingSubmitResult {
  const OnboardingFailed(this.failure);

  final AppFailure failure;
}

/// Controller of the five-step onboarding flow.
///
/// All state is in memory. The only write is [finish] or [skip]: ONE atomic
/// `OnboardingRepository.complete` command with a stable command id per
/// content (the `SubmissionTracker` pattern), so a retry or a double tap can
/// never complete twice.
class OnboardingController extends Notifier<OnboardingState> {
  late SubmissionTracker _tracker;

  @override
  OnboardingState build() {
    // build() runs again after invalidation: reset the bookkeeping as well.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return OnboardingState.initial();
  }

  // ---- input -------------------------------------------------------------

  /// Selects or deselects a motivation goal. Unknown ids are ignored.
  void toggleMotivationGoal(String id) {
    if (state.busy || !SchemaKeys.motivationGoals.contains(id)) {
      return;
    }
    final next = Set<String>.of(state.motivationGoals);
    if (!next.add(id)) {
      next.remove(id);
    }
    state = _edited(state.copyWith(motivationGoals: next));
  }

  /// Keeps ([enabled]) or drops [module]. Dropping all five is allowed.
  void setModuleEnabled(ModuleId module, {required bool enabled}) {
    if (state.busy) {
      return;
    }
    final next = Set<ModuleId>.of(state.enabledModules);
    final changed = enabled ? next.add(module) : next.remove(module);
    if (!changed) {
      return;
    }
    state = _edited(state.copyWith(enabledModules: next));
  }

  void setNameText(String text) {
    if (state.busy) {
      return;
    }
    state = _edited(
      state.copyWith(
        nameText: text,
        fieldErrors: _without(ProfileFields.displayName),
      ),
    );
  }

  void setHeightText(String text) {
    if (state.busy) {
      return;
    }
    state = _edited(
      state.copyWith(
        heightText: text,
        fieldErrors: _without(ProfileFields.heightCm),
      ),
    );
  }

  void setAgeText(String text) {
    if (state.busy) {
      return;
    }
    state = _edited(
      state.copyWith(
        ageText: text,
        fieldErrors: _without(ProfileFields.ageYears),
      ),
    );
  }

  void setWeightText(String text) {
    if (state.busy) {
      return;
    }
    state = _edited(
      state.copyWith(
        weightText: text,
        fieldErrors: _without(ProfileFields.startWeight),
      ),
    );
  }

  /// Switches an on/off goal (task, weight entry) on or off. Other goal types
  /// are ignored: their target is edited with [adjustGoalTarget].
  void setGoalEnabled(GoalType type, {required bool enabled}) {
    if (state.busy || !onboardingSwitchGoals.contains(type)) {
      return;
    }
    final next = Set<GoalType>.of(state.goalsOff);
    final changed = enabled ? next.remove(type) : next.add(type);
    if (!changed) {
      return;
    }
    state = _edited(state.copyWith(goalsOff: next));
  }

  /// Plus ([direction] > 0) or minus ([direction] < 0) on a stepper goal.
  void adjustGoalTarget(GoalType type, int direction) {
    if (state.busy) {
      return;
    }
    final current = state.goalTargets[type];
    if (current == null) {
      return;
    }
    final next = steppedGoalTarget(type, current, direction);
    if (next == null) {
      return;
    }
    state = _edited(
      state.copyWith(
        goalTargets: <GoalType, int>{...state.goalTargets, type: next},
        fieldErrors: _without(type.key),
      ),
    );
  }

  // ---- navigation within the flow ----------------------------------------

  /// Goes to the next step. The body step validates its fields first and
  /// stays (with field errors and a focus request) when one is invalid.
  /// Returns whether the step changed.
  bool next() {
    final following = state.step.next;
    if (state.busy || following == null) {
      return false;
    }
    if (state.step == OnboardingStep.body) {
      final body = _parseBody();
      if (!body.isValid) {
        state = state.copyWith(
          fieldErrors: body.errors,
          focusRequest: state.focusRequest + 1,
        );
        return false;
      }
    }
    state = state.copyWith(
      step: following,
      movedBackward: false,
      fieldErrors: const <String, String>{},
    );
    return true;
  }

  /// Goes to the previous step. All input is kept. Returns whether the step
  /// changed (false on the first step).
  bool back() {
    final previous = state.step.previous;
    if (state.busy || previous == null) {
      return false;
    }
    state = state.copyWith(
      step: previous,
      movedBackward: true,
      fieldErrors: const <String, String>{},
    );
    return true;
  }

  // ---- completion ---------------------------------------------------------

  /// Completes the onboarding with the entered values (the last step's
  /// button). Validates the body values again, then runs ONE command.
  Future<OnboardingSubmitResult> finish() async {
    if (state.busy) {
      return const OnboardingRejected();
    }
    final body = _parseBody();
    if (!body.isValid) {
      state = state.copyWith(
        step: OnboardingStep.body,
        movedBackward: state.step.index > OnboardingStep.body.index,
        fieldErrors: body.errors,
        focusRequest: state.focusRequest + 1,
      );
      return const OnboardingRejected();
    }
    final draft = OnboardingDraft(
      displayName: body.displayName,
      heightCm: body.heightCm,
      ageYears: body.ageYears,
      startWeightGrams: body.startWeightGrams,
      motivationGoals: <String>[
        for (final option in OnboardingOptions.motivationGoals)
          if (state.motivationGoals.contains(option.id)) option.id,
      ],
      enabledModules: Set<ModuleId>.of(state.enabledModules),
      goals: <GoalType, GoalSetting>{
        for (final entry in state.goalTargets.entries)
          entry.key: GoalSetting(target: entry.value),
        for (final type in onboardingSwitchGoals)
          type: GoalSetting(enabled: !state.goalsOff.contains(type)),
      },
    );
    return _submit(
      draft,
      kind: OnboardingSubmitKind.finish,
      fingerprint: _fingerprint(draft),
    );
  }

  /// "Überspringen": completes with the defaults (all five modules, default
  /// goals, no name, no body values, no motivation goals) and discards what
  /// was entered so far. The screen asks for a confirmation first when there
  /// is input ([OnboardingState.hasUserInput]).
  Future<OnboardingSubmitResult> skip() async {
    if (state.busy) {
      return const OnboardingRejected();
    }
    return _submit(
      const OnboardingDraft.skipped(),
      kind: OnboardingSubmitKind.skip,
      fingerprint: 'skipped',
    );
  }

  /// Repeats the attempt that failed, with the same command id as long as the
  /// content is unchanged.
  Future<OnboardingSubmitResult> retry() => switch (state.failedSubmit) {
    OnboardingSubmitKind.skip => skip(),
    _ => finish(),
  };

  Future<OnboardingSubmitResult> _submit(
    OnboardingDraft draft, {
    required OnboardingSubmitKind kind,
    required String fingerprint,
  }) async {
    final commandId = _tracker.idFor(fingerprint);
    state = state.copyWith(
      submitting: true,
      fieldErrors: const <String, String>{},
      submitFailure: () => null,
      failedSubmit: () => null,
    );
    try {
      await ref
          .read(onboardingRepositoryProvider)
          .complete(commandId: commandId, draft: draft);
      return _committed();
    } on ValidationFailure catch (failure) {
      return _invalid(failure);
    } on ConflictFailure catch (failure) {
      if (failure.kind == ConflictKind.invalidState) {
        // The profile is already onboarded: the work is done, leave the flow.
        return _committed(alreadyCompleted: true);
      }
      return _failed(failure, kind);
    } on AppFailure catch (failure) {
      return _failed(failure, kind);
    } catch (error) {
      // Never leave the button stuck: unknown errors count as storage errors.
      return _failed(
        StorageFailure(causeType: error.runtimeType.toString()),
        kind,
      );
    }
  }

  OnboardingSubmitResult _committed({bool alreadyCompleted = false}) {
    _tracker.completed();
    if (ref.mounted) {
      state = state.copyWith(submitting: false, completed: true);
    }
    return OnboardingCompleted(alreadyCompleted: alreadyCompleted);
  }

  OnboardingSubmitResult _invalid(ValidationFailure failure) {
    if (ref.mounted) {
      final goalKeys = <String>{
        for (final type in onboardingGoalTypes) type.key,
      };
      final onGoals = failure.fieldErrors.keys.any(goalKeys.contains);
      state = state.copyWith(
        submitting: false,
        step: onGoals ? OnboardingStep.dailyGoals : OnboardingStep.body,
        movedBackward: !onGoals,
        fieldErrors: failure.fieldErrors,
        focusRequest: state.focusRequest + 1,
      );
    }
    return const OnboardingRejected();
  }

  OnboardingSubmitResult _failed(
    AppFailure failure,
    OnboardingSubmitKind kind,
  ) {
    if (ref.mounted) {
      state = state.copyWith(
        submitting: false,
        submitFailure: () => failure,
        failedSubmit: () => kind,
      );
    }
    return OnboardingFailed(failure);
  }

  // ---- helpers ------------------------------------------------------------

  BodyValuesInput _parseBody() => parseBodyValues(
    nameText: state.nameText,
    heightText: state.heightText,
    ageText: state.ageText,
    weightText: state.weightText,
  );

  /// An edit makes an earlier failed attempt obsolete.
  OnboardingState _edited(OnboardingState next) =>
      next.copyWith(submitFailure: () => null, failedSubmit: () => null);

  Map<String, String> _without(String field) {
    return Map<String, String>.of(state.fieldErrors)..remove(field);
  }

  /// A value-equal description of the draft: the command id is reused only
  /// while this string is unchanged. (A record holding lists would compare by
  /// identity and always yield a new id.)
  static String _fingerprint(OnboardingDraft draft) {
    final modules = draft.enabledModules.map((m) => m.key).toList()..sort();
    final goals =
        draft.goals.entries
            .map((e) => '${e.key.key}=${e.value.target}/${e.value.enabled}')
            .toList()
          ..sort();
    return <Object?>[
      draft.displayName,
      draft.heightCm,
      draft.ageYears,
      draft.startWeightGrams,
      draft.motivationGoals.join(','),
      modules.join(','),
      goals.join(','),
    ].join('|');
  }
}

/// The state of the running onboarding flow; disposed when the screen goes,
/// so a fresh onboarding (for example after a data reset) starts empty.
final onboardingControllerProvider =
    NotifierProvider.autoDispose<OnboardingController, OnboardingState>(
      OnboardingController.new,
    );
