import 'package:flutter/foundation.dart';

/// Where the total of a step day comes from (`step_days.source`).
enum StepSource {
  /// Typed in by the user.
  manual('manual'),

  /// Taken from the health interface of the phone (BS-97).
  health('health');

  const StepSource(this.key);

  /// The stored key, one of `SchemaKeys.stepSources`.
  final String key;

  /// The source of a stored [key], or null for an unknown key.
  static StepSource? tryParse(String? key) {
    for (final source in values) {
      if (source.key == key) {
        return source;
      }
    }
    return null;
  }
}

/// What the comparison with the health interface does with one local day.
enum HealthDayAction {
  /// The day has no value: the total of the health interface becomes one
  /// (source `health`).
  create,

  /// The day has a value from the health interface that differs from the new
  /// total: the value is updated (source stays `health`).
  update,

  /// The day already has exactly this value from the health interface.
  unchanged,

  /// The day has a value the user typed in: it has priority and is never
  /// touched.
  keepManual,

  /// The health interface has no data for the day: nothing is created, and an
  /// earlier value is never removed or lowered by "no data".
  noData,
}

/// The conflict rule of the comparison, for one local day (decision D-032).
///
/// 1. A value the user typed in ([StepSource.manual]) always wins and is never
///    overwritten, whatever the health interface reports.
/// 2. The health interface fills only days without a value and updates only
///    values it wrote itself ([StepSource.health]).
/// 3. "No data" ([healthSteps] null) changes nothing: it creates no value and
///    removes none. A reported 0 is a value like any other.
///
/// [existingSource] and [existingSteps] describe the active value of the day
/// (both null when the day has none); [healthSteps] is the total the interface
/// reports for the day (already limited to the range of the app).
HealthDayAction decideHealthDay({
  required StepSource? existingSource,
  required int? existingSteps,
  required int? healthSteps,
}) {
  if (existingSource == StepSource.manual) {
    return HealthDayAction.keepManual;
  }
  if (healthSteps == null) {
    return HealthDayAction.noData;
  }
  if (existingSource == null) {
    return HealthDayAction.create;
  }
  return existingSteps == healthSteps
      ? HealthDayAction.unchanged
      : HealthDayAction.update;
}

/// What one comparison wrote: the number of days per [HealthDayAction].
@immutable
final class HealthApplyResult {
  const HealthApplyResult({
    this.created = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.keptManual = 0,
    this.noData = 0,
  });

  /// Nothing happened (no day looked at).
  static const HealthApplyResult none = HealthApplyResult();

  final int created;
  final int updated;
  final int unchanged;
  final int keptManual;
  final int noData;

  /// Days that got a new value or a changed one.
  int get changed => created + updated;

  /// All days that were looked at.
  int get total => changed + unchanged + keptManual + noData;

  /// The result with one more day of [action].
  HealthApplyResult plus(HealthDayAction action) => HealthApplyResult(
    created: created + (action == HealthDayAction.create ? 1 : 0),
    updated: updated + (action == HealthDayAction.update ? 1 : 0),
    unchanged: unchanged + (action == HealthDayAction.unchanged ? 1 : 0),
    keptManual: keptManual + (action == HealthDayAction.keepManual ? 1 : 0),
    noData: noData + (action == HealthDayAction.noData ? 1 : 0),
  );

  @override
  bool operator ==(Object other) =>
      other is HealthApplyResult &&
      other.created == created &&
      other.updated == updated &&
      other.unchanged == unchanged &&
      other.keptManual == keptManual &&
      other.noData == noData;

  @override
  int get hashCode =>
      Object.hash(created, updated, unchanged, keptManual, noData);

  @override
  String toString() =>
      'HealthApplyResult(created: $created, updated: $updated, '
      'unchanged: $unchanged, keptManual: $keptManual, noData: $noData)';
}
