/// Workout input rules: strict duration parsing, stepping and the validation of
/// a whole draft (specification section 8.3 with the category/muscle group
/// override).
library;

import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Shortest and longest duration in minutes.
const int minWorkoutMinutes = 1;
const int maxWorkoutMinutes = 600;

/// Longest custom title and note (characters).
const int maxWorkoutTitleLength = 80;
const int maxWorkoutNoteLength = 500;

/// Step of the duration plus/minus buttons (5 minutes).
const int workoutDurationStepMinutes = 5;

/// Where the plus/minus buttons start when the field is empty (30 minutes).
/// It is only a starting point for the stepper; nothing is saved unless the
/// user presses save.
const int workoutDurationStartMinutes = 30;

/// Earliest accepted business date (technical minimum, 2000-01-01).
final LocalDate workoutEarliestDate = LocalDate(2000, 1, 1);

/// Field keys of the workout form (keys of [ValidationFailure.fieldErrors]).
abstract final class WorkoutFields {
  static const String category = 'category';
  static const String title = 'title';
  static const String duration = 'duration';
  static const String occurredAt = 'occurredAt';
  static const String note = 'note';
}

/// German message when no category was chosen.
const String workoutCategoryMissingMessage =
    'Bitte wähle eine Trainingskategorie.';

/// German message for a duration outside 1 to 600 minutes.
const String workoutDurationRangeMessage =
    'Bitte gib eine Dauer zwischen 1 und 600 Minuten ein.';

/// Why a duration text was rejected.
enum WorkoutMinutesError {
  /// Nothing entered.
  empty,

  /// Not a plain whole number (letters, decimals, signs, separators).
  invalidFormat,

  /// Below 1 minute.
  belowMinimum,

  /// Above 600 minutes.
  aboveMaximum,
}

/// German message for a rejected duration text.
String workoutMinutesErrorMessage(WorkoutMinutesError error) => switch (error) {
  WorkoutMinutesError.empty => 'Bitte gib die Dauer in Minuten ein.',
  WorkoutMinutesError.invalidFormat =>
    'Bitte gib eine ganze Zahl ein, zum Beispiel 45.',
  WorkoutMinutesError.belowMinimum ||
  WorkoutMinutesError.aboveMaximum => workoutDurationRangeMessage,
};

/// Result of [parseWorkoutMinutes].
sealed class WorkoutMinutesParseResult {
  const WorkoutMinutesParseResult();
}

/// A valid duration in whole minutes.
final class WorkoutMinutesParsed extends WorkoutMinutesParseResult {
  const WorkoutMinutesParsed(this.minutes);

  final int minutes;
}

/// A rejected input with the reason.
final class WorkoutMinutesInvalid extends WorkoutMinutesParseResult {
  const WorkoutMinutesInvalid(this.error);

  final WorkoutMinutesError error;
}

final RegExp _plainInteger = RegExp(r'^\d+$');

/// Parses a duration typed by the user: digits only (no decimals, signs,
/// separators or exponents), 1 to 600 inclusive. Leading zeros are accepted.
WorkoutMinutesParseResult parseWorkoutMinutes(String input) {
  final text = input.trim();
  if (text.isEmpty) {
    return const WorkoutMinutesInvalid(WorkoutMinutesError.empty);
  }
  if (!_plainInteger.hasMatch(text)) {
    return const WorkoutMinutesInvalid(WorkoutMinutesError.invalidFormat);
  }
  final digits = text.replaceFirst(RegExp(r'^0+'), '');
  if (digits.length > 4) {
    return const WorkoutMinutesInvalid(WorkoutMinutesError.aboveMaximum);
  }
  final minutes = digits.isEmpty ? 0 : int.parse(digits);
  if (minutes < minWorkoutMinutes) {
    return const WorkoutMinutesInvalid(WorkoutMinutesError.belowMinimum);
  }
  if (minutes > maxWorkoutMinutes) {
    return const WorkoutMinutesInvalid(WorkoutMinutesError.aboveMaximum);
  }
  return WorkoutMinutesParsed(minutes);
}

/// Applies a plus (+1) or minus (-1) step to the current text.
///
/// A valid [currentText] is changed by 5 minutes (clamped to 1 to 600). An empty
/// or invalid text is replaced by [workoutDurationStartMinutes] (30): the first
/// press only shows the starting point, in either direction.
int stepWorkoutMinutes({required String currentText, required int direction}) {
  switch (parseWorkoutMinutes(currentText)) {
    case WorkoutMinutesParsed(:final minutes):
      return (minutes + direction * workoutDurationStepMinutes).clamp(
        minWorkoutMinutes,
        maxWorkoutMinutes,
      );
    case WorkoutMinutesInvalid():
      return workoutDurationStartMinutes;
  }
}

/// Validates [draft] and returns it normalised: title and note trimmed (blank
/// becomes null), muscle groups deduplicated in canonical order. Several
/// errors are reported together as a [ValidationFailure].
WorkoutDraft validateWorkoutDraft(
  WorkoutDraft draft, {
  required DateTime nowUtc,
  required ClockService clock,
}) {
  final errors = <String, String>{};

  final title = draft.title?.trim();
  if (title != null && title.runes.length > maxWorkoutTitleLength) {
    errors[WorkoutFields.title] =
        'Der Titel darf höchstens $maxWorkoutTitleLength Zeichen lang sein.';
  }

  if (draft.durationMinutes < minWorkoutMinutes ||
      draft.durationMinutes > maxWorkoutMinutes) {
    errors[WorkoutFields.duration] = workoutDurationRangeMessage;
  }

  if (draft.occurredAtUtc.isAfter(nowUtc)) {
    errors[WorkoutFields.occurredAt] =
        'Der Zeitpunkt darf nicht in der Zukunft liegen.';
  } else if (clock.localDateOf(draft.occurredAtUtc) < workoutEarliestDate) {
    errors[WorkoutFields.occurredAt] =
        'Das Datum darf nicht vor dem 01.01.2000 liegen.';
  }

  final note = draft.note?.trim();
  if (note != null && note.runes.length > maxWorkoutNoteLength) {
    errors[WorkoutFields.note] =
        'Die Notiz darf höchstens $maxWorkoutNoteLength Zeichen lang sein.';
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return WorkoutDraft(
    category: draft.category,
    durationMinutes: draft.durationMinutes,
    occurredAtUtc: draft.occurredAtUtc,
    title: (title == null || title.isEmpty) ? null : title,
    muscleGroups: MuscleGroup.normalize(draft.muscleGroups),
    intensity: draft.intensity,
    note: (note == null || note.isEmpty) ? null : note,
  );
}
