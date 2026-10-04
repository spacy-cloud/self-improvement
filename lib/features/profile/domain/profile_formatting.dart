/// Pure, deterministic German texts used by the profile, goals and settings
/// screens. No locale data is needed, so tests, emulators and devices show
/// exactly the same text. Dates come from `lib/shared/german_date.dart`.
library;

import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// "Dabei seit Oktober 2026": month and year of the profile start.
String formatMemberSince(LocalDate startedOn) {
  return 'Dabei seit ${monthLong(startedOn.month)} ${startedOn.year}';
}

/// Initials of at most two name parts for the live avatar preview, or `null`
/// for an empty name (the avatar then shows the neutral profile icon).
///
/// Uses the same rule as the stored profile ([UserProfile.initials]).
String? initialsForName(String? name) {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return UserProfile(
    startedOn: LocalDate(2000, 1, 1),
    onboardingCompleted: false,
    rowVersion: 0,
    displayName: trimmed,
  ).initials;
}

/// A weight in grams as "71,5 kg".
String formatWeightKg(int grams) => '${formatKilograms(grams)} kg';

/// A signed weight difference as "−2,5 kg" (true minus sign, explicit plus).
String formatSignedWeightKg(int gramsDelta) {
  return '${formatSignedKilograms(gramsDelta)} kg';
}
