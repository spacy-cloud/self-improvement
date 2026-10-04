import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/errors/app_failure.dart';

/// Field keys of the profile forms (keys of [ValidationFailure.fieldErrors]).
abstract final class ProfileFields {
  static const String displayName = 'displayName';
  static const String heightCm = 'heightCm';
  static const String ageYears = 'ageYears';
  static const String startWeight = 'startWeight';
  static const String targetWeight = 'targetWeight';
  static const String motivationGoals = 'motivationGoals';
}

const int maxDisplayNameLength = 40;
const int minHeightCm = 100;
const int maxHeightCm = 250;
const int minAgeYears = 18;
const int maxAgeYears = 120;
const int minProfileWeightGrams = 20000;
const int maxProfileWeightGrams = 350000;

/// Validated, normalised profile values (all optional).
final class ProfileValues {
  const ProfileValues({
    this.displayName,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.targetWeightGrams,
    this.motivationGoals = const [],
  });

  final String? displayName;
  final int? heightCm;
  final int? ageYears;
  final int? startWeightGrams;
  final int? targetWeightGrams;
  final List<String> motivationGoals;
}

/// Validates and normalises profile input.
///
/// - Name: trimmed, 1-40 characters; empty means no name ("Mein Profil").
/// - Height 100-250 cm, age 18-120 years (no birth date), start and target
///   weight 20,0-350,0 kg in 0,1 kg steps. All optional; nothing is invented.
/// - Motivation goals: only the known onboarding ids, deduplicated, original
///   order kept.
/// Throws [ValidationFailure] with all field errors.
ProfileValues validateProfileValues({
  String? displayName,
  int? heightCm,
  int? ageYears,
  int? startWeightGrams,
  int? targetWeightGrams,
  Iterable<String> motivationGoals = const [],
}) {
  final errors = <String, String>{};

  String? name = displayName?.trim();
  if (name != null && name.isEmpty) {
    name = null;
  }
  if (name != null && name.length > maxDisplayNameLength) {
    errors[ProfileFields.displayName] =
        'Der Name darf höchstens $maxDisplayNameLength Zeichen lang sein.';
  }
  if (heightCm != null && (heightCm < minHeightCm || heightCm > maxHeightCm)) {
    errors[ProfileFields.heightCm] =
        'Bitte gib eine Größe zwischen $minHeightCm und $maxHeightCm cm ein.';
  }
  if (ageYears != null && (ageYears < minAgeYears || ageYears > maxAgeYears)) {
    errors[ProfileFields.ageYears] =
        'Bitte gib ein Alter zwischen $minAgeYears und $maxAgeYears Jahren ein.';
  }
  bool badWeight(int? grams) =>
      grams != null &&
      (grams < minProfileWeightGrams ||
          grams > maxProfileWeightGrams ||
          grams % 100 != 0);
  if (badWeight(startWeightGrams)) {
    errors[ProfileFields.startWeight] =
        'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.';
  }
  if (badWeight(targetWeightGrams)) {
    errors[ProfileFields.targetWeight] =
        'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.';
  }

  final goals = <String>[];
  for (final goal in motivationGoals) {
    if (!SchemaKeys.motivationGoals.contains(goal)) {
      errors[ProfileFields.motivationGoals] = 'Unbekannte Auswahl.';
    } else if (!goals.contains(goal)) {
      goals.add(goal);
    }
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return ProfileValues(
    displayName: name,
    heightCm: heightCm,
    ageYears: ageYears,
    startWeightGrams: startWeightGrams,
    targetWeightGrams: targetWeightGrams,
    motivationGoals: List.unmodifiable(goals),
  );
}
