import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/shared/local_date.dart';

/// State of the daily water target form.
@immutable
final class WaterGoalFormState {
  const WaterGoalFormState({
    required this.targetText,
    required this.dirty,
    this.fieldError,
    this.submitting = false,
    this.submitFailure,
  });

  /// What the user typed or stepped to: whole millilitres.
  final String targetText;

  final bool dirty;

  /// German hint for the target field, null when fine.
  final String? fieldError;

  /// True while a save is running; further saves are ignored.
  final bool submitting;

  /// A persistent failure (e.g. storage); the input is kept.
  final AppFailure? submitFailure;

  WaterGoalFormState copyWith({
    String? targetText,
    bool? dirty,
    String? Function()? fieldError,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => WaterGoalFormState(
    targetText: targetText ?? this.targetText,
    dirty: dirty ?? this.dirty,
    fieldError: fieldError == null ? this.fieldError : fieldError(),
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [WaterGoalController.submit].
sealed class WaterGoalSubmitResult {
  const WaterGoalSubmitResult();
}

/// Saved. The target applies from [effectiveFrom] (tomorrow), never today.
final class WaterGoalSaved extends WaterGoalSubmitResult {
  const WaterGoalSaved(
    this.outcome, {
    required this.targetMl,
    required this.effectiveFrom,
  });

  final CommandOutcome outcome;
  final int targetMl;
  final LocalDate effectiveFrom;

  /// Success message (German); always says the change applies from tomorrow.
  String get message => waterGoalSavedMessage(targetMl);
}

/// Not saved; the form shows the reason and keeps the input.
final class WaterGoalRejected extends WaterGoalSubmitResult {
  const WaterGoalRejected();
}

/// Edits the daily water target (250 to 10000 ml in 50 ml steps).
///
/// A change applies FROM TOMORROW through `GoalsCommands.update`: today keeps
/// its frozen threshold, several edits made today replace one another.
/// Saving a target also switches the goal on from tomorrow (a goal that was
/// switched off becomes active again with the chosen value).
///
/// The family argument is the value to start from: the stored target from
/// tomorrow on (`WaterGoalSettings.tomorrowTargetMl`).
class WaterGoalController extends Notifier<WaterGoalFormState> {
  WaterGoalController(this.initialTargetMl);

  final int initialTargetMl;

  late SubmissionTracker _tracker;

  @override
  WaterGoalFormState build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    return WaterGoalFormState(targetText: '$initialTargetMl', dirty: false);
  }

  void setTargetText(String text) => state = state.copyWith(
    targetText: text,
    dirty: true,
    fieldError: () => null,
  );

  /// Plus (+1) or minus (-1) button: 50 ml per step from the typed value or,
  /// when that is not valid, from the starting value. Clamped to 250 to 10000.
  void step(int direction) {
    final ml = stepWaterGoalMl(
      currentText: state.targetText,
      direction: direction,
      fallbackMl: initialTargetMl,
    );
    if (ml != null) {
      setTargetText('$ml');
    }
  }

  /// Validates and saves. Ignored while a save is running (double tap).
  Future<WaterGoalSubmitResult> submit() async {
    if (state.submitting) {
      return const WaterGoalRejected();
    }
    final int ml;
    switch (parseWaterGoalMl(state.targetText)) {
      case WaterGoalParsed(ml: final parsed):
        ml = parsed;
      case WaterGoalInvalid(:final error):
        state = state.copyWith(fieldError: () => waterGoalErrorMessage(error));
        return const WaterGoalRejected();
    }

    final commandId = _tracker.idFor(ml);
    state = state.copyWith(
      submitting: true,
      fieldError: () => null,
      submitFailure: () => null,
    );
    final commands = ref.read(goalsCommandsProvider);
    final fallbackDate = nextEffectiveDate(ref.read(clockProvider).today());
    try {
      final outcome = await commands.update(
        commandId: commandId,
        changes: {GoalType.water: GoalSetting(target: ml)},
      );
      _tracker.completed();
      state = state.copyWith(submitting: false, dirty: false);
      return WaterGoalSaved(
        outcome,
        targetMl: ml,
        effectiveFrom:
            LocalDate.tryParse(outcome.entityId ?? '') ?? fallbackDate,
      );
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldError: () => failure.userMessage,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const WaterGoalRejected();
  }
}

/// Provider of the water target form, keyed by the value to start from;
/// auto-disposed with its sheet or screen.
final waterGoalControllerProvider = NotifierProvider.autoDispose
    .family<WaterGoalController, WaterGoalFormState, int>(
      WaterGoalController.new,
    );
