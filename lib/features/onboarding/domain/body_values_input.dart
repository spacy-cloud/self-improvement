import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/body/domain/weight_validation.dart';

/// The optional personal values of the onboarding body step after parsing.
///
/// Every field is voluntary: a blank text is "not given" ([displayName],
/// [heightCm] and the others stay `null`), never a default and never an example
/// value. Nothing here is a weight measurement; the values only end up in the
/// profile.
@immutable
final class BodyValuesInput {
  const BodyValuesInput({
    this.displayName,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.errors = const <String, String>{},
  });

  /// Trimmed name of 1 to 40 characters, or `null` (the profile then reads
  /// "Mein Profil").
  final String? displayName;

  /// Height in whole centimetres, 100 to 250, or `null`.
  final int? heightCm;

  /// Age in whole years, 18 to 120, or `null` (no birth date is asked).
  final int? ageYears;

  /// Start weight in grams (20,0 to 350,0 kg in 0,1 kg steps), or `null`.
  final int? startWeightGrams;

  /// German hint per field, keyed like [ProfileFields]. Empty when valid.
  final Map<String, String> errors;

  bool get isValid => errors.isEmpty;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');
final RegExp _leadingZeros = RegExp(r'^0+');

/// Parses a whole number; blank is `(value: null, invalid: false)`.
({int? value, bool invalid}) _parseWholeNumber(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return (value: null, invalid: false);
  }
  if (!_digitsOnly.hasMatch(text)) {
    return (value: null, invalid: true);
  }
  final significant = text.replaceFirst(_leadingZeros, '');
  if (significant.length > 6) {
    // Far out of range anyway: avoids integer overflow, the range check below
    // reports it.
    return (value: 999999, invalid: false);
  }
  return (
    value: significant.isEmpty ? 0 : int.parse(significant),
    invalid: false,
  );
}

/// Parses and validates the four texts of the body step.
///
/// Reuses the strict weight parser of the weight form (`71,5` and `71.5` are
/// valid, `71,55`, `NaN`, 19,9 and 350,1 are rejected) and the profile
/// validator for the ranges (name up to 40 characters after trimming, height
/// 100 to 250, age 18 to 120, weight 20,0 to 350,0 kg). Blank texts are valid
/// and mean "not given".
BodyValuesInput parseBodyValues({
  required String nameText,
  required String heightText,
  required String ageText,
  required String weightText,
}) {
  final errors = <String, String>{};

  final height = _parseWholeNumber(heightText);
  if (height.invalid) {
    errors[ProfileFields.heightCm] =
        'Bitte gib die Größe als ganze Zahl in cm '
        'ein.';
  }
  final age = _parseWholeNumber(ageText);
  if (age.invalid) {
    errors[ProfileFields.ageYears] =
        'Bitte gib das Alter als ganze Zahl in Jahren ein.';
  }

  int? weightGrams;
  switch (parseWeightKg(weightText)) {
    case WeightKgParsed(:final grams):
      weightGrams = grams;
    case WeightKgInvalid(error: WeightKgError.empty):
      break;
    case WeightKgInvalid(:final error):
      errors[ProfileFields.startWeight] = weightKgErrorMessage(error);
  }

  final name = nameText.trim();
  try {
    validateProfileValues(
      displayName: name,
      heightCm: height.value,
      ageYears: age.value,
      startWeightGrams: weightGrams,
    );
  } on ValidationFailure catch (failure) {
    for (final entry in failure.fieldErrors.entries) {
      errors.putIfAbsent(entry.key, () => entry.value);
    }
  }

  return BodyValuesInput(
    displayName: errors.containsKey(ProfileFields.displayName) || name.isEmpty
        ? null
        : name,
    heightCm: errors.containsKey(ProfileFields.heightCm) ? null : height.value,
    ageYears: errors.containsKey(ProfileFields.ageYears) ? null : age.value,
    startWeightGrams: errors.containsKey(ProfileFields.startWeight)
        ? null
        : weightGrams,
    errors: Map<String, String>.unmodifiable(errors),
  );
}
