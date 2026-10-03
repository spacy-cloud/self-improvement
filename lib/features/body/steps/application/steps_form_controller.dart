import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/body/steps/domain/steps_input.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Which date the steps form opens for (null: today).
@immutable
final class StepsFormArgs {
  const StepsFormArgs({this.date});

  final LocalDate? date;

  @override
  bool operator ==(Object other) =>
      other is StepsFormArgs && other.date == date;

  @override
  int get hashCode => date.hashCode;
}

@immutable
final class StepsFormState {
  const StepsFormState({
    required this.stepsText,
    required this.date,
    required this.dirty,
    this.existingSteps,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  final String stepsText;
  final LocalDate date;

  /// The value already stored for [date]: saving REPLACES it (the form says so
  /// explicitly); null means no record yet.
  final int? existingSteps;

  final bool dirty;
  final Map<String, String> fieldErrors;
  final bool submitting;
  final AppFailure? submitFailure;

  bool get replacesExisting => existingSteps != null;

  StepsFormState copyWith({
    String? stepsText,
    LocalDate? date,
    bool? dirty,
    int? Function()? existingSteps,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => StepsFormState(
    stepsText: stepsText ?? this.stepsText,
    date: date ?? this.date,
    dirty: dirty ?? this.dirty,
    existingSteps: existingSteps == null ? this.existingSteps : existingSteps(),
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

sealed class StepsSubmitResult {
  const StepsSubmitResult();
}

final class StepsSaved extends StepsSubmitResult {
  const StepsSaved(this.outcome, {required this.replaced});

  final CommandOutcome outcome;

  /// True if an existing total was replaced.
  final bool replaced;

  String get message =>
      replaced ? 'Schritte aktualisiert' : 'Schritte gespeichert';
}

final class StepsRejected extends StepsSubmitResult {
  const StepsRejected();
}

class StepsFormController extends Notifier<StepsFormState> {
  StepsFormController(this.args);

  final StepsFormArgs args;
  late SubmissionTracker _tracker;
  var _generation = 0;

  @override
  StepsFormState build() {
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    final date = args.date ?? ref.read(clockProvider).today();
    unawaited(_loadExisting(date));
    return StepsFormState(stepsText: '', date: date, dirty: false);
  }

  Future<void> _loadExisting(LocalDate date) async {
    final generation = ++_generation;
    final existing = await ref.read(stepsRepositoryProvider).findDay(date);
    if (generation != _generation || !ref.mounted) {
      return;
    }
    state = state.copyWith(existingSteps: () => existing?.steps);
  }

  void setStepsText(String text) => state = state.copyWith(
    stepsText: text,
    dirty: true,
    fieldErrors: _without(StepsFields.steps),
  );

  void setDate(LocalDate date) {
    state = state.copyWith(
      date: date,
      dirty: true,
      fieldErrors: _without(StepsFields.date),
      existingSteps: () => null,
    );
    unawaited(_loadExisting(date));
  }

  Future<StepsSubmitResult> submit() async {
    if (state.submitting) {
      return const StepsRejected();
    }
    final errors = <String, String>{};
    int? steps;
    switch (parseSteps(state.stepsText)) {
      case StepsParsed(steps: final parsed):
        steps = parsed;
      case StepsInvalid(:final error):
        errors[StepsFields.steps] = stepsErrorMessage(error);
    }
    final today = ref.read(clockProvider).today();
    if (state.date.isAfter(today)) {
      errors[StepsFields.date] = 'Das Datum darf nicht in der Zukunft liegen.';
    }
    if (errors.isNotEmpty || steps == null) {
      state = state.copyWith(fieldErrors: errors);
      return const StepsRejected();
    }

    final commandId = _tracker.idFor((state.date, steps));
    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    try {
      final replaced = state.replacesExisting;
      final outcome = await ref
          .read(stepsRepositoryProvider)
          .setSteps(commandId: commandId, date: state.date, steps: steps);
      _tracker.completed();
      state = state.copyWith(submitting: false, dirty: false);
      return StepsSaved(outcome, replaced: replaced);
    } on ValidationFailure catch (failure) {
      state = state.copyWith(
        submitting: false,
        fieldErrors: failure.fieldErrors,
      );
    } on AppFailure catch (failure) {
      state = state.copyWith(submitting: false, submitFailure: () => failure);
    }
    return const StepsRejected();
  }

  Map<String, String> _without(String field) =>
      Map<String, String>.of(state.fieldErrors)..remove(field);
}

final stepsFormProvider = NotifierProvider.autoDispose
    .family<StepsFormController, StepsFormState, StepsFormArgs>(
      StepsFormController.new,
    );
