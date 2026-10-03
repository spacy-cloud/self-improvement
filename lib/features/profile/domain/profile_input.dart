/// Text input of the profile form and its strict parsing.
///
/// Reuses the weight parser ([parseWeightKg]) and the profile validators
/// ([validateProfileValues]) so the editor, onboarding and the database agree
/// on every limit: height 100 to 250 cm, age 18 to 120 years, weights 20,0 to
/// 350,0 kg in 0,1 kg steps. All values are optional.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The raw text of the profile form fields.
@immutable
final class ProfileInput {
  const ProfileInput({
    this.name = '',
    this.heightText = '',
    this.ageText = '',
    this.startWeightText = '',
    this.targetWeightText = '',
  });

  /// The texts that show the stored [profile] (empty for missing values; the
  /// default name "Mein Profil" is never put into the field).
  factory ProfileInput.fromProfile(UserProfile profile) {
    String weight(int? grams) => grams == null ? '' : formatKilograms(grams);
    return ProfileInput(
      name: profile.displayName ?? '',
      heightText: profile.heightCm?.toString() ?? '',
      ageText: profile.ageYears?.toString() ?? '',
      startWeightText: weight(profile.startWeightGrams),
      targetWeightText: weight(profile.targetWeightGrams),
    );
  }

  final String name;
  final String heightText;
  final String ageText;
  final String startWeightText;
  final String targetWeightText;

  ProfileInput copyWith({
    String? name,
    String? heightText,
    String? ageText,
    String? startWeightText,
    String? targetWeightText,
  }) => ProfileInput(
    name: name ?? this.name,
    heightText: heightText ?? this.heightText,
    ageText: ageText ?? this.ageText,
    startWeightText: startWeightText ?? this.startWeightText,
    targetWeightText: targetWeightText ?? this.targetWeightText,
  );

  /// Equality ignores surrounding blanks, so typing and deleting a space is no
  /// change (drives the "Änderungen verwerfen?" question).
  @override
  bool operator ==(Object other) =>
      other is ProfileInput &&
      other.name.trim() == name.trim() &&
      other.heightText.trim() == heightText.trim() &&
      other.ageText.trim() == ageText.trim() &&
      other.startWeightText.trim() == startWeightText.trim() &&
      other.targetWeightText.trim() == targetWeightText.trim();

  @override
  int get hashCode => Object.hash(
    name.trim(),
    heightText.trim(),
    ageText.trim(),
    startWeightText.trim(),
    targetWeightText.trim(),
  );
}

/// Result of [parseProfileInput].
sealed class ProfileParseResult {
  const ProfileParseResult();
}

/// All fields are valid; [values] are normalised and ready for the command.
final class ProfileParsed extends ProfileParseResult {
  const ProfileParsed(this.values);

  final ProfileValues values;
}

/// At least one field is invalid; [fieldErrors] maps [ProfileFields] keys to
/// German hints. The input itself stays untouched.
final class ProfileInvalid extends ProfileParseResult {
  const ProfileInvalid(this.fieldErrors);

  final Map<String, String> fieldErrors;
}

/// Digits above this count are treated as "far out of range" so the field
/// shows its normal range hint instead of an overflow.
const int _maxDigits = 9;

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Parses and validates the form [input].
///
/// Empty height, age and weights mean "not given". Weights accept comma or
/// period and one decimal place (`71,5` and `71.5`); `71,55`, letters and
/// values outside 20,0 to 350,0 kg are rejected with a hint.
ProfileParseResult parseProfileInput(ProfileInput input) {
  final errors = <String, String>{};

  final height = _wholeNumber(
    input.heightText,
    field: ProfileFields.heightCm,
    message: 'Bitte gib die Größe in ganzen Zentimetern ein, zum Beispiel 170.',
    errors: errors,
  );
  final age = _wholeNumber(
    input.ageText,
    field: ProfileFields.ageYears,
    message: 'Bitte gib das Alter in ganzen Jahren ein, zum Beispiel 30.',
    errors: errors,
  );
  final start = parseOptionalWeight(
    input.startWeightText,
    field: ProfileFields.startWeight,
    errors: errors,
  );
  final target = parseOptionalWeight(
    input.targetWeightText,
    field: ProfileFields.targetWeight,
    errors: errors,
  );

  ProfileValues? values;
  try {
    values = validateProfileValues(
      displayName: input.name,
      heightCm: height,
      ageYears: age,
      startWeightGrams: start,
      targetWeightGrams: target,
    );
  } on ValidationFailure catch (failure) {
    for (final entry in failure.fieldErrors.entries) {
      errors.putIfAbsent(entry.key, () => entry.value);
    }
  }
  if (errors.isNotEmpty || values == null) {
    return ProfileInvalid(Map.unmodifiable(errors));
  }
  return ProfileParsed(values);
}

int? _wholeNumber(
  String text, {
  required String field,
  required String message,
  required Map<String, String> errors,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (!_digitsOnly.hasMatch(trimmed)) {
    errors[field] = message;
    return null;
  }
  final significant = trimmed.replaceFirst(RegExp(r'^0+'), '');
  if (significant.length > _maxDigits) {
    return 999999999;
  }
  return int.parse(trimmed);
}

/// Parses an optional weight text: empty gives `null`, a valid weight gives
/// its grams and an invalid text records the German hint under [field] in
/// [errors] (and gives `null`).
int? parseOptionalWeight(
  String text, {
  required String field,
  required Map<String, String> errors,
}) {
  if (text.trim().isEmpty) {
    return null;
  }
  switch (parseWeightKg(text)) {
    case WeightKgParsed(:final grams):
      return grams;
    case WeightKgInvalid(:final error):
      errors[field] = weightKgErrorMessage(error);
      return null;
  }
}

/// The latest weight measurement offered as start weight.
@immutable
final class StartWeightProposal {
  const StartWeightProposal(this.grams);

  /// The latest measurement in grams.
  final int grams;
}

/// Whether to offer the latest measurement as start weight.
///
/// Only while the user is setting or changing the target weight ([targetText]
/// parses and differs from [storedTargetGrams]), no start weight is given
/// ([startText] is empty, [storedStartGrams] is `null`) and a measurement
/// exists. The proposal is never applied silently: the user confirms it, and
/// only then it lands in the form. The measurement itself is never changed.
StartWeightProposal? proposeStartWeight({
  required String targetText,
  required int? storedTargetGrams,
  required String startText,
  required int? latestMeasurementGrams,
  int? storedStartGrams,
}) {
  final latest = latestMeasurementGrams;
  if (latest == null ||
      startText.trim().isNotEmpty ||
      storedStartGrams != null) {
    return null;
  }
  return switch (parseWeightKg(targetText)) {
    WeightKgParsed(:final grams) when grams != storedTargetGrams =>
      StartWeightProposal(latest),
    _ => null,
  };
}
