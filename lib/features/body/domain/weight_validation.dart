import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/shared/local_date.dart';

/// Field keys of the weight form (keys of [ValidationFailure.fieldErrors]).
abstract final class WeightFields {
  static const String weight = 'weight';
  static const String measuredAt = 'measuredAt';
  static const String note = 'note';
}

/// Earliest accepted business date for any event form (technical minimum).
final LocalDate earliestEventDate = LocalDate(2000, 1, 1);

/// Maximum note length.
const int maxNoteLength = 500;

/// German message for a rejected weight text.
String weightKgErrorMessage(WeightKgError error) => switch (error) {
  WeightKgError.empty => 'Bitte gib dein Gewicht ein.',
  WeightKgError.invalidFormat => 'Bitte gib eine Zahl ein, zum Beispiel 71,5.',
  WeightKgError.tooManyDecimals =>
    'Bitte gib höchstens eine Nachkommastelle an, zum Beispiel 71,5.',
  WeightKgError.belowMinimum || WeightKgError.aboveMaximum =>
    'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.',
};

/// Result of a successful validation: the draft with a normalised note.
WeightDraft validateWeightDraft(
  WeightDraft draft, {
  required DateTime nowUtc,
  required ClockService clock,
}) {
  final errors = <String, String>{};

  if (draft.weightGrams < minWeightGrams ||
      draft.weightGrams > maxWeightGrams ||
      draft.weightGrams % weightStepGrams != 0) {
    errors[WeightFields.weight] =
        'Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.';
  }

  if (draft.occurredAtUtc.isAfter(nowUtc)) {
    errors[WeightFields.measuredAt] =
        'Der Messzeitpunkt darf nicht in der Zukunft liegen.';
  } else if (clock.localDateOf(draft.occurredAtUtc) < earliestEventDate) {
    errors[WeightFields.measuredAt] =
        'Das Datum darf nicht vor dem 01.01.2000 liegen.';
  }

  final note = draft.note?.trim();
  if (note != null && note.length > maxNoteLength) {
    errors[WeightFields.note] =
        'Die Notiz darf höchstens $maxNoteLength Zeichen lang sein.';
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return WeightDraft(
    weightGrams: draft.weightGrams,
    occurredAtUtc: draft.occurredAtUtc,
    beforeToilet: draft.beforeToilet,
    afterDrinking: draft.afterDrinking,
    afterEating: draft.afterEating,
    note: (note == null || note.isEmpty) ? null : note,
  );
}
