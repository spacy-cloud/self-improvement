import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/profile/user_profile.dart';

/// Read access to the singleton local profile.
///
/// Mutations (onboarding, profile editor) are commands run through the
/// `CommandRunner` and live with the features that own them.
class ProfileRepository {
  ProfileRepository(this._database);

  final AppDatabase _database;

  /// Emits the profile whenever it changes; null before the singleton exists.
  Stream<UserProfile?> watch() => _database
      .select(_database.profile)
      .watchSingleOrNull()
      .map((row) => row == null ? null : mapProfile(row));

  /// The current profile or null.
  Future<UserProfile?> get() async {
    final row = await _database.select(_database.profile).getSingleOrNull();
    return row == null ? null : mapProfile(row);
  }

  /// Maps a database row to the domain model.
  static UserProfile mapProfile(ProfileRow row) => UserProfile(
    startedOn: row.startedLocalDate,
    onboardingCompleted: row.onboardingCompleted,
    rowVersion: row.rowVersion,
    displayName: row.displayName,
    heightCm: row.heightCm,
    ageYears: row.ageYears,
    startWeightGrams: row.startWeightGrams,
    targetWeightGrams: row.targetWeightGrams,
    motivationGoals: row.motivationGoals,
  );
}
