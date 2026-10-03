import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The instant used as "start" in the pure timer tests (2026-10-03 08:00Z,
/// 10:00 in Berlin).
final DateTime t0 = DateTime.utc(2026, 10, 3, 8);

/// A synthetic session. A running session without an explicit
/// [segmentStart] starts its segment at [t0].
FocusSession focusSession({
  String id = 'f1',
  FocusCategory category = FocusCategory.learning,
  int planned = 1500,
  int accumulated = 0,
  FocusStatus status = FocusStatus.running,
  DateTime? segmentStart,
  DateTime? endedAt,
  LocalDate? completedDate,
  String timezoneId = 'Europe/Berlin',
  String? note,
  bool eligible = false,
  int rowVersion = 1,
}) => FocusSession(
  id: id,
  category: category,
  plannedSeconds: planned,
  accumulatedSeconds: accumulated,
  status: status,
  segmentStartedAtUtc: status == FocusStatus.running
      ? (segmentStart ?? t0)
      : segmentStart,
  startedAtUtc: t0,
  endedAtUtc: endedAt,
  completedLocalDate: completedDate,
  timezoneId: timezoneId,
  note: note,
  gamificationEligible: eligible,
  rowVersion: rowVersion,
  updatedAtUtc: t0,
);

/// [t0] plus [seconds].
DateTime after(int seconds, {int millis = 0}) =>
    t0.add(Duration(seconds: seconds, milliseconds: millis));
