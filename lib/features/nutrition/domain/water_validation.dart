import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';

/// Field keys of the water form (keys of [ValidationFailure.fieldErrors]).
abstract final class WaterFields {
  static const String amount = 'amount';
  static const String occurredAt = 'occurredAt';
  static const String note = 'note';
}

/// Validates a water draft and returns it with a normalised note (trimmed,
/// blank means none). Throws a [ValidationFailure] with ALL field errors:
///
/// - amount: integer, 50 to 2000 ml;
/// - time: not after [nowUtc], not before 2000-01-01 in the device zone;
/// - note: at most 500 characters after trimming.
WaterDraft validateWaterDraft(
  WaterDraft draft, {
  required DateTime nowUtc,
  required ClockService clock,
}) {
  final errors = <String, String>{};

  if (draft.amountMl < minWaterEntryMl || draft.amountMl > maxWaterEntryMl) {
    errors[WaterFields.amount] = waterAmountRangeMessage;
  }

  final timeError = eventTimeError(
    occurredAtUtc: draft.occurredAtUtc,
    nowUtc: nowUtc,
    clock: clock,
  );
  if (timeError != null) {
    errors[WaterFields.occurredAt] = timeError;
  }

  final note = normalizeNote(draft.note);
  if (note.error != null) {
    errors[WaterFields.note] = note.error!;
  }

  if (errors.isNotEmpty) {
    throw ValidationFailure(errors);
  }
  return WaterDraft(
    amountMl: draft.amountMl,
    occurredAtUtc: draft.occurredAtUtc,
    note: note.note,
  );
}
