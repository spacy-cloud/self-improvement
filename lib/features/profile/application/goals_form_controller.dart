import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/profile/domain/profile_input.dart';
import 'package:self_improvement/shared/number_format.dart';

/// What the user set for one goal: the switch and the typed value.
///
/// Switch goals (weight entry, task completion) have no value; their [text] is
/// empty. Equality ignores blanks around the text.
@immutable
final class GoalDraft {
  const GoalDraft({required this.enabled, required this.text});

  /// The draft that shows [value] (what applies from tomorrow).
  factory GoalDraft.fromValue(GoalType type, GoalValue value) => GoalDraft(
    enabled: value.enabled,
    text: type.isSwitch ? '' : '${value.target}',
  );

  final bool enabled;
  final String text;

  GoalDraft copyWith({bool? enabled, String? text}) =>
      GoalDraft(enabled: enabled ?? this.enabled, text: text ?? this.text);

  @override
  bool operator ==(Object other) =>
      other is GoalDraft &&
      other.enabled == enabled &&
      other.text.trim() == text.trim();

  @override
  int get hashCode => Object.hash(enabled, text.trim());
}

/// What the goal editor opened with: the goals of today and tomorrow plus the
/// body values it needs for the target weight.
///
/// Two args are the same form while all values are equal, so the form keeps
/// its input while streams re-emit unchanged data; the screen keeps the args
/// it opened with.
@immutable
final class GoalsFormArgs {
  const GoalsFormArgs({
    required this.model,
    this.bodyVisible = true,
    this.targetWeightGrams,
    this.startWeightGrams,
    this.latestWeightGrams,
  });

  final GoalEditorModel model;

  /// Whether the body module is on (the target weight row is shown).
  final bool bodyVisible;

  /// Stored target weight of the profile (effective immediately).
  final int? targetWeightGrams;

  /// Stored start weight of the profile.
  final int? startWeightGrams;

  /// Latest weight measurement, only used as a proposal and as the starting
  /// point of the plus and minus buttons. Never saved without confirmation.
  final int? latestWeightGrams;

  @override
  bool operator ==(Object other) =>
      other is GoalsFormArgs &&
      other.model == model &&
      other.bodyVisible == bodyVisible &&
      other.targetWeightGrams == targetWeightGrams &&
      other.startWeightGrams == startWeightGrams &&
      other.latestWeightGrams == latestWeightGrams;

  @override
  int get hashCode => Object.hash(
    model,
    bodyVisible,
    targetWeightGrams,
    startWeightGrams,
    latestWeightGrams,
  );
}

/// State of the goal editor. All input stays here when saving fails.
@immutable
final class GoalsFormState {
  const GoalsFormState({
    required this.drafts,
    required this.targetWeightText,
    required this.dirty,
    this.acceptedStartGrams,
    this.proposal,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// One draft per goal type (hidden goals included, they are never sent).
  final Map<GoalType, GoalDraft> drafts;

  /// The typed target weight in kilograms; empty means "not set".
  final String targetWeightText;

  /// True once something differs from what is saved.
  final bool dirty;

  /// The latest measurement the user confirmed as start weight, or `null`.
  final int? acceptedStartGrams;

  /// Offer to use the latest measurement as start weight, or `null`.
  final StartWeightProposal? proposal;

  /// [GoalType.key] or [ProfileFields.targetWeight] -> German hint.
  final Map<String, String> fieldErrors;

  final bool submitting;

  /// A form level failure (for example storage); the input is kept.
  final AppFailure? submitFailure;

  GoalsFormState copyWith({
    Map<GoalType, GoalDraft>? drafts,
    String? targetWeightText,
    bool? dirty,
    int? Function()? acceptedStartGrams,
    StartWeightProposal? Function()? proposal,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => GoalsFormState(
    drafts: drafts ?? this.drafts,
    targetWeightText: targetWeightText ?? this.targetWeightText,
    dirty: dirty ?? this.dirty,
    acceptedStartGrams: acceptedStartGrams == null
        ? this.acceptedStartGrams
        : acceptedStartGrams(),
    proposal: proposal == null ? this.proposal : proposal(),
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [GoalsFormController.submit].
sealed class GoalsSubmitResult {
  const GoalsSubmitResult();
}

/// Committed. Show the success feedback now, not earlier.
final class GoalsSaved extends GoalsSubmitResult {
  const GoalsSaved({required this.goalsSaved, required this.targetSaved});

  /// Goal values or switches were saved (they apply from tomorrow).
  final bool goalsSaved;

  /// The target weight (and a confirmed start weight) were saved (immediate).
  final bool targetSaved;

  /// The success message after the commit; it says when the change applies.
  String get message {
    if (goalsSaved && targetSaved) {
      return 'Ziele gespeichert. Tagesziele gelten ab morgen, '
          'das Zielgewicht sofort.';
    }
    if (targetSaved) {
      return 'Zielgewicht gespeichert. Es gilt sofort.';
    }
    return 'Ziele gespeichert. Sie gelten ab morgen.';
  }
}

/// Nothing was changed, so nothing was written.
final class GoalsUnchanged extends GoalsSubmitResult {
  const GoalsUnchanged();
}

/// Not saved (completely or partly); the form shows the reasons and keeps all
/// input. [goalsSaved] is true when the goals were committed before the target
/// weight failed.
final class GoalsRejected extends GoalsSubmitResult {
  const GoalsRejected({this.goalsSaved = false});

  final bool goalsSaved;
}

/// Controller of the goal editor. Starts from what applies tomorrow (that
/// includes a change saved earlier today) and saves through `GoalsCommands`:
/// every goal change takes effect from tomorrow. The target weight is a
/// profile value and is saved through `ProfileCommands`, effective at once.
class GoalsFormController extends Notifier<GoalsFormState> {
  GoalsFormController(this.args);

  final GoalsFormArgs args;

  late SubmissionTracker _goalsTracker;
  late SubmissionTracker _profileTracker;
  late Map<GoalType, GoalDraft> _baseline;
  late int? _savedTargetGrams;

  GoalEditorModel get model => args.model;

  @override
  GoalsFormState build() {
    // build() runs again after invalidation: reset the per-form bookkeeping.
    final ids = ref.read(idGeneratorProvider);
    _goalsTracker = SubmissionTracker(ids);
    _profileTracker = SubmissionTracker(ids);
    _baseline = {
      for (final row in model.rows)
        row.type: GoalDraft.fromValue(row.type, row.tomorrow),
    };
    _savedTargetGrams = args.targetWeightGrams;
    return GoalsFormState(
      drafts: _baseline,
      targetWeightText: _targetText(_savedTargetGrams),
      dirty: false,
    );
  }

  /// Switches [type] on or off.
  void setEnabled(GoalType type, {required bool enabled}) {
    _changeDraft(type, state.drafts[type]!.copyWith(enabled: enabled));
  }

  /// The user typed [text] into the value field of [type].
  void setText(GoalType type, String text) {
    _changeDraft(type, state.drafts[type]!.copyWith(text: text));
  }

  /// Plus ([direction] 1) or minus ([direction] -1) next to the value field.
  void step(GoalType type, int direction) {
    final next = stepGoalTarget(
      type: type,
      text: state.drafts[type]!.text,
      fallback: _savedTarget(type),
      direction: direction,
    );
    if (next != null) {
      setText(type, '$next');
    }
  }

  /// The user typed [text] into the target weight field.
  void setTargetWeightText(String text) {
    _emit(
      state.copyWith(
        targetWeightText: text,
        fieldErrors: _without(ProfileFields.targetWeight),
      ),
    );
  }

  /// Plus ([direction] 1) or minus ([direction] -1) next to the target weight:
  /// 0,1 kg per step from the typed value, else from the start weight, else
  /// from the latest measurement. Does nothing without a value to start from.
  void stepTargetWeight(int direction) {
    final grams = stepWeightGrams(
      currentText: state.targetWeightText,
      direction: direction,
      fallbackGrams: args.startWeightGrams ?? args.latestWeightGrams,
    );
    if (grams != null) {
      setTargetWeightText(formatKilograms(grams));
    }
  }

  /// Explicit confirmation of the proposed start weight (the latest
  /// measurement). It is saved together with the form, never silently.
  void acceptStartWeightProposal() {
    final proposal = state.proposal;
    if (proposal == null) {
      return;
    }
    _emit(state.copyWith(acceptedStartGrams: () => proposal.grams));
  }

  /// Validates and saves the changed goals of the visible modules and the
  /// target weight. Ignored while a save runs (double tap).
  Future<GoalsSubmitResult> submit() async {
    if (state.submitting) {
      return const GoalsRejected();
    }

    final changes = <GoalType, GoalSetting>{};
    final errors = <String, String>{};
    for (final row in model.visibleRows) {
      final type = row.type;
      final draft = state.drafts[type]!;
      if (draft == _baseline[type]) {
        continue;
      }
      if (type.isSwitch) {
        changes[type] = GoalSetting(enabled: draft.enabled);
        continue;
      }
      switch (parseGoalText(type, draft.text)) {
        case GoalTextValid(:final value):
          changes[type] = GoalSetting(target: value, enabled: draft.enabled);
        case GoalTextInvalid(:final message):
          if (draft.enabled) {
            errors[type.key] = message;
          } else {
            // A switched-off goal keeps its last valid value.
            changes[type] = GoalSetting(
              target: _savedTarget(type),
              enabled: false,
            );
          }
      }
    }

    var targetChanged = false;
    int? newTarget;
    if (args.bodyVisible) {
      final text = state.targetWeightText.trim();
      if (text.isNotEmpty) {
        newTarget = parseOptionalWeight(
          text,
          field: ProfileFields.targetWeight,
          errors: errors,
        );
      }
      targetChanged =
          !errors.containsKey(ProfileFields.targetWeight) &&
          newTarget != _savedTargetGrams;
    }

    if (errors.isNotEmpty) {
      state = state.copyWith(fieldErrors: errors);
      return const GoalsRejected();
    }
    final startToSave =
        targetChanged && newTarget != null && args.startWeightGrams == null
        ? state.acceptedStartGrams
        : null;
    final profileChanged = targetChanged || startToSave != null;
    if (changes.isEmpty && !profileChanged) {
      return const GoalsUnchanged();
    }

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    var goalsSaved = false;
    try {
      if (changes.isNotEmpty) {
        await ref
            .read(goalsCommandsProvider)
            .update(
              commandId: _goalsTracker.idFor(_goalsFingerprint(changes)),
              changes: changes,
            );
        _goalsTracker.completed();
        goalsSaved = true;
        _baseline = {
          for (final entry in state.drafts.entries)
            entry.key: _savedDraft(entry.key, entry.value, changes),
        };
      }
      if (profileChanged) {
        final profile = await ref.read(profileRepositoryProvider).get();
        if (profile == null) {
          throw const NotFoundFailure(entity: 'profile');
        }
        await ref
            .read(profileCommandsProvider)
            .update(
              commandId: _profileTracker.idFor((newTarget, startToSave)),
              displayName: profile.displayName,
              heightCm: profile.heightCm,
              ageYears: profile.ageYears,
              startWeightGrams: startToSave ?? profile.startWeightGrams,
              targetWeightGrams: newTarget,
            );
        _profileTracker.completed();
        _savedTargetGrams = newTarget;
      }
      if (ref.mounted) {
        state = state.copyWith(
          drafts: _baseline,
          targetWeightText: _targetText(_savedTargetGrams),
          acceptedStartGrams: () => null,
          proposal: () => null,
          submitting: false,
          dirty: false,
        );
      }
      return GoalsSaved(goalsSaved: goalsSaved, targetSaved: profileChanged);
    } on ValidationFailure catch (failure) {
      _failed(fieldErrors: failure.fieldErrors, goalsSaved: goalsSaved);
    } on AppFailure catch (failure) {
      _failed(failure: failure, goalsSaved: goalsSaved);
    }
    return GoalsRejected(goalsSaved: goalsSaved);
  }

  /// After a failure: keep all input, show the reason and (when the goals were
  /// committed before the target weight failed) show them as saved.
  void _failed({
    required bool goalsSaved,
    AppFailure? failure,
    Map<String, String>? fieldErrors,
  }) {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      drafts: goalsSaved ? _baseline : null,
      submitting: false,
      fieldErrors: fieldErrors,
      submitFailure: () => failure,
      dirty: _isDirty(
        goalsSaved ? _baseline : state.drafts,
        state.targetWeightText,
        state.acceptedStartGrams,
      ),
    );
  }

  /// The value that is saved for [type] (what applies tomorrow).
  int _savedTarget(GoalType type) {
    final baseline = _baseline[type]!;
    if (type.isSwitch) {
      return type.defaultTarget;
    }
    return switch (parseGoalText(type, baseline.text)) {
      GoalTextValid(:final value) => value,
      GoalTextInvalid() => model.rowOf(type).tomorrow.target,
    };
  }

  /// After a save the draft shows what was sent (a switched-off goal with an
  /// unusable text goes back to its saved value).
  GoalDraft _savedDraft(
    GoalType type,
    GoalDraft draft,
    Map<GoalType, GoalSetting> sent,
  ) {
    final setting = sent[type];
    if (setting == null || type.isSwitch) {
      return draft;
    }
    return draft.copyWith(text: '${setting.target}');
  }

  void _changeDraft(GoalType type, GoalDraft next) {
    _emit(
      state.copyWith(
        drafts: {...state.drafts, type: next},
        fieldErrors: _without(type.key),
      ),
    );
  }

  /// Stores [next] with the derived values (dirty flag and start proposal).
  void _emit(GoalsFormState next) {
    final proposal = args.bodyVisible
        ? proposeStartWeight(
            targetText: next.targetWeightText,
            storedTargetGrams: _savedTargetGrams,
            startText: '',
            latestMeasurementGrams: args.latestWeightGrams,
            storedStartGrams: args.startWeightGrams,
          )
        : null;
    final accepted = proposal == null ? null : next.acceptedStartGrams;
    state = next.copyWith(
      proposal: () => proposal,
      acceptedStartGrams: () => accepted,
      dirty: _isDirty(next.drafts, next.targetWeightText, accepted),
    );
  }

  bool _isDirty(
    Map<GoalType, GoalDraft> drafts,
    String targetText,
    int? acceptedStart,
  ) {
    return !mapEquals(drafts, _baseline) ||
        targetText.trim() != _targetText(_savedTargetGrams) ||
        acceptedStart != null;
  }

  Map<String, String> _without(String field) {
    return Map<String, String>.of(state.fieldErrors)..remove(field);
  }

  String _targetText(int? grams) => grams == null ? '' : formatKilograms(grams);

  String _goalsFingerprint(Map<GoalType, GoalSetting> changes) {
    final keys = changes.keys.toList()..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final type in keys)
        '${type.key}:${changes[type]!.target}:${changes[type]!.enabled}',
    ].join('|');
  }
}

/// Provider of the goal editor; auto-disposed with its screen. The args are
/// the family key, so one editor lives as long as the screen keeps the args it
/// opened with.
final goalsFormProvider = NotifierProvider.autoDispose
    .family<GoalsFormController, GoalsFormState, GoalsFormArgs>(
      GoalsFormController.new,
    );
