/// Manually logged workouts: the stored entry and the user's draft.
///
/// ## Old workout type -> new fields
///
/// Earlier drafts of the specification classified a workout with one visible
/// `type`. That field no longer exists; the visible classification is the
/// [TrainingCategory] plus optional [MuscleGroup]s and a [WorkoutIntensity].
/// If legacy rows ever have to be converted, this mapping applies (it only
/// adds information, nothing is lost):
///
/// | Old `type` | `training_category` | `muscle_groups` |
/// |---|---|---|
/// | `upper_body` | `strength` | `chest`, `shoulders`, `back`, `biceps`, `triceps` |
/// | `lower_body` | `strength` | `legs` |
/// | `full_body` | `strength` | `full_body` |
/// | `cardio` | `cardio` | none |
/// | `other` | `sport` | none |
///
/// The old rule "a custom title is mandatory for `other`" is gone: the title is
/// optional for every category. There is no stored legacy data in this app, so
/// no migration code exists.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_intensity.dart';
import 'package:self_improvement/shared/local_date.dart';

/// A stored workout entry.
@immutable
final class WorkoutEntry {
  const WorkoutEntry({
    required this.id,
    required this.category,
    required this.durationMinutes,
    required this.occurredAtUtc,
    required this.localDate,
    required this.timezoneId,
    required this.rowVersion,
    required this.gamificationEligible,
    this.title,
    this.muscleGroups = const [],
    this.intensity,
    this.note,
  });

  final String id;
  final TrainingCategory category;

  /// The optional custom title (1 to 80 characters); null when none was given.
  final String? title;

  /// Whole minutes, 1 to 600.
  final int durationMinutes;

  /// Deduplicated, in canonical order; empty when none was chosen.
  final List<MuscleGroup> muscleGroups;

  /// Null when none was chosen.
  final WorkoutIntensity? intensity;

  /// When the workout took place (UTC).
  final DateTime occurredAtUtc;

  /// Business date frozen when the entry was created (or its time changed).
  final LocalDate localDate;

  final String timezoneId;
  final String? note;

  /// Incremented on every change; used for conflict detection and undo.
  final int rowVersion;

  /// Frozen at creation (was gamification enabled then).
  final bool gamificationEligible;

  /// The title to display: the custom title, or the German name of the
  /// category when there is none (or it is blank).
  String get displayTitle {
    final custom = title?.trim();
    return custom == null || custom.isEmpty ? category.label : custom;
  }

  @override
  bool operator ==(Object other) =>
      other is WorkoutEntry &&
      other.id == id &&
      other.category == category &&
      other.title == title &&
      other.durationMinutes == durationMinutes &&
      listEquals(other.muscleGroups, muscleGroups) &&
      other.intensity == intensity &&
      other.occurredAtUtc == occurredAtUtc &&
      other.localDate == localDate &&
      other.timezoneId == timezoneId &&
      other.note == note &&
      other.rowVersion == rowVersion &&
      other.gamificationEligible == gamificationEligible;

  @override
  int get hashCode => Object.hash(
    id,
    category,
    title,
    durationMinutes,
    Object.hashAll(muscleGroups),
    intensity,
    occurredAtUtc,
    localDate,
    timezoneId,
    note,
    rowVersion,
    gamificationEligible,
  );

  @override
  String toString() =>
      'WorkoutEntry($id, ${category.key}, $durationMinutes min, $localDate)';
}

/// User input for creating or editing a workout.
@immutable
final class WorkoutDraft {
  const WorkoutDraft({
    required this.category,
    required this.durationMinutes,
    required this.occurredAtUtc,
    this.title,
    this.muscleGroups = const [],
    this.intensity,
    this.note,
  });

  final TrainingCategory category;
  final int durationMinutes;
  final DateTime occurredAtUtc;

  /// Free text, at most 80 characters after trimming; blank means none.
  final String? title;

  /// Any selection; duplicates are removed when the draft is validated.
  final List<MuscleGroup> muscleGroups;

  final WorkoutIntensity? intensity;

  /// Free text, at most 500 characters after trimming; blank means none.
  final String? note;
}
