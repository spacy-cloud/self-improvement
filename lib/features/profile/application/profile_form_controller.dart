import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/profile/domain/profile_input.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Identifies a profile form: the profile as it was when the editor opened.
///
/// Two args are the same form while the row version is the same, so the form
/// keeps its input while the profile stream re-emits.
@immutable
final class ProfileFormArgs {
  const ProfileFormArgs(this.profile, {this.bodyVisible = true});

  final UserProfile profile;

  /// Whether the body module is on. The body fields (height, age, start and
  /// target weight) are hidden when it is off and keep their stored values.
  final bool bodyVisible;

  @override
  bool operator ==(Object other) =>
      other is ProfileFormArgs &&
      other.profile.rowVersion == profile.rowVersion &&
      other.bodyVisible == bodyVisible;

  @override
  int get hashCode => Object.hash(profile.rowVersion, bodyVisible);
}

/// State of the profile form. All input stays here when saving fails.
@immutable
final class ProfileFormState {
  const ProfileFormState({
    required this.input,
    required this.dirty,
    this.fieldErrors = const {},
    this.submitting = false,
    this.submitFailure,
  });

  /// What the user typed.
  final ProfileInput input;

  /// True once the input differs from what is stored (drives the
  /// "Änderungen verwerfen?" question).
  final bool dirty;

  /// [ProfileFields] key -> German hint.
  final Map<String, String> fieldErrors;

  /// True while a save runs; further saves are ignored.
  final bool submitting;

  /// A form level failure (for example storage); the input is kept.
  final AppFailure? submitFailure;

  ProfileFormState copyWith({
    ProfileInput? input,
    bool? dirty,
    Map<String, String>? fieldErrors,
    bool? submitting,
    AppFailure? Function()? submitFailure,
  }) => ProfileFormState(
    input: input ?? this.input,
    dirty: dirty ?? this.dirty,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    submitting: submitting ?? this.submitting,
    submitFailure: submitFailure == null ? this.submitFailure : submitFailure(),
  );
}

/// Outcome of [ProfileFormController.submit].
sealed class ProfileSubmitResult {
  const ProfileSubmitResult();
}

/// Committed. Show the success feedback now, not earlier.
final class ProfileSaved extends ProfileSubmitResult {
  const ProfileSaved(this.outcome);

  final CommandOutcome outcome;

  /// The success message after the commit.
  String get message => 'Profil gespeichert';
}

/// Nothing was changed, so nothing was written.
final class ProfileUnchanged extends ProfileSubmitResult {
  const ProfileUnchanged();
}

/// Not saved; the form shows the reasons and keeps all input.
final class ProfileRejected extends ProfileSubmitResult {
  const ProfileRejected();
}

/// Controller of the profile editor.
class ProfileFormController extends Notifier<ProfileFormState> {
  ProfileFormController(this.args);

  final ProfileFormArgs args;

  late SubmissionTracker _tracker;
  late ProfileInput _baseline;

  @override
  ProfileFormState build() {
    // build() runs again after invalidation: reset the per-form bookkeeping.
    _tracker = SubmissionTracker(ref.read(idGeneratorProvider));
    _baseline = ProfileInput.fromProfile(args.profile);
    return ProfileFormState(input: _baseline, dirty: false);
  }

  void setName(String text) =>
      _change(state.input.copyWith(name: text), ProfileFields.displayName);

  void setAge(String text) =>
      _change(state.input.copyWith(ageText: text), ProfileFields.ageYears);

  void setHeight(String text) =>
      _change(state.input.copyWith(heightText: text), ProfileFields.heightCm);

  void setStartWeight(String text) => _change(
    state.input.copyWith(startWeightText: text),
    ProfileFields.startWeight,
  );

  void setTargetWeight(String text) => _change(
    state.input.copyWith(targetWeightText: text),
    ProfileFields.targetWeight,
  );

  /// Explicit confirmation of the suggested start weight (the latest
  /// measurement). The value only lands in the form; it is saved with the
  /// form, never silently.
  void acceptStartWeightSuggestion(int grams) =>
      setStartWeight(formatKilograms(grams));

  /// Validates and saves. Ignored while a save runs (double tap).
  Future<ProfileSubmitResult> submit() async {
    if (state.submitting) {
      return const ProfileRejected();
    }

    // A hidden body section (body module off) keeps its stored values.
    var input = state.input;
    if (!args.bodyVisible) {
      input = input.copyWith(
        heightText: _baseline.heightText,
        ageText: _baseline.ageText,
        startWeightText: _baseline.startWeightText,
        targetWeightText: _baseline.targetWeightText,
      );
    }

    final parsed = parseProfileInput(input);
    final ProfileValues values;
    switch (parsed) {
      case ProfileInvalid(:final fieldErrors):
        state = state.copyWith(fieldErrors: fieldErrors);
        return const ProfileRejected();
      case ProfileParsed(values: final parsedValues):
        values = parsedValues;
    }

    if (!state.dirty) {
      return const ProfileUnchanged();
    }

    final commandId = _tracker.idFor((
      values.displayName,
      values.heightCm,
      values.ageYears,
      values.startWeightGrams,
      values.targetWeightGrams,
    ));

    state = state.copyWith(
      submitting: true,
      fieldErrors: const {},
      submitFailure: () => null,
    );
    try {
      final outcome = await ref
          .read(profileCommandsProvider)
          .update(
            commandId: commandId,
            displayName: values.displayName,
            heightCm: values.heightCm,
            ageYears: values.ageYears,
            startWeightGrams: values.startWeightGrams,
            targetWeightGrams: values.targetWeightGrams,
          );
      _tracker.completed();
      if (ref.mounted) {
        _baseline = state.input;
        state = state.copyWith(submitting: false, dirty: false);
      }
      return ProfileSaved(outcome);
    } on ValidationFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(
          submitting: false,
          fieldErrors: failure.fieldErrors,
        );
      }
    } on AppFailure catch (failure) {
      if (ref.mounted) {
        state = state.copyWith(submitting: false, submitFailure: () => failure);
      }
    }
    return const ProfileRejected();
  }

  void _change(ProfileInput next, String field) {
    final errors = Map<String, String>.of(state.fieldErrors)..remove(field);
    state = state.copyWith(
      input: next,
      dirty: next != _baseline,
      fieldErrors: errors,
    );
  }
}

/// Provider of a profile form; auto-disposed with its screen.
final profileFormProvider = NotifierProvider.autoDispose
    .family<ProfileFormController, ProfileFormState, ProfileFormArgs>(
      ProfileFormController.new,
    );
