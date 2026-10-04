import 'package:flutter/foundation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The local profile (singleton). There are no accounts.
@immutable
final class UserProfile {
  const UserProfile({
    required this.startedOn,
    required this.onboardingCompleted,
    required this.rowVersion,
    this.displayName,
    this.heightCm,
    this.ageYears,
    this.startWeightGrams,
    this.targetWeightGrams,
    this.motivationGoals = const [],
  });

  /// Default display name when none was entered.
  static const String defaultName = 'Mein Profil';

  /// First local business day of this installation.
  final LocalDate startedOn;

  final bool onboardingCompleted;
  final int rowVersion;

  /// Trimmed name, 1-40 characters, or null.
  final String? displayName;

  /// Optional body data, never auto-filled and never a measurement.
  final int? heightCm;
  final int? ageYears;
  final int? startWeightGrams;
  final int? targetWeightGrams;

  /// Voluntary, deduplicated onboarding preference ids (e.g. `move_more`).
  final List<String> motivationGoals;

  /// Name to show: the entered name or "Mein Profil".
  String get effectiveName => displayName ?? defaultName;

  /// Initials of at most two name parts, or null without a name (neutral
  /// profile icon).
  String? get initials {
    final name = displayName;
    if (name == null) {
      return null;
    }
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) {
      return null;
    }
    return parts
        .map((part) => String.fromCharCode(part.runes.first).toUpperCase())
        .join();
  }
}
