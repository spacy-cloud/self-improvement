import 'package:self_improvement/core/analysis/data/analysis_data_source.dart';
import 'package:self_improvement/core/analysis/domain/analysis_period.dart';
import 'package:self_improvement/core/analysis/domain/analysis_report.dart';
import 'package:self_improvement/core/analysis/domain/workout_week.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/database/reactive.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The analysis read model: the report of a period, recomputed from the
/// database whenever a table it depends on changes.
///
/// Nothing is stored; every report is derived from the facts. The streams use
/// `watchComputed`: changes that arrive while a computation runs are coalesced
/// into exactly one follow-up computation, and the computation never runs per
/// widget build. A report is only emitted again when the loaded inputs really
/// changed.
class AnalysisRepository {
  AnalysisRepository({required this._database, required this._source});

  final AppDatabase _database;
  final AnalysisDataSource _source;

  /// The report of [period] now.
  Future<AnalysisReport> compute(AnalysisPeriodSpec period) async =>
      (await _source.load(period)).toReport();

  /// The report of [period], re-emitted when a relevant table changes.
  ///
  /// [period] carries today: the caller (the provider layer) subscribes again
  /// when the day or the selected length changes.
  Stream<AnalysisReport> watch(AnalysisPeriodSpec period) => watchComputed(
    _database,
    _source.tables,
    () => _source.load(period),
  ).distinct().map((inputs) => inputs.toReport());

  /// The workout week card of [today] now (Monday to today against the same
  /// weekdays of the previous week).
  Future<WorkoutWeekCard> computeWorkoutWeek(LocalDate today) async =>
      _workoutWeek(await _source.loadWorkoutWeek(today));

  /// The workout week card of [today], re-emitted when a workout, the weekly
  /// goal or the profile changes.
  Stream<WorkoutWeekCard> watchWorkoutWeek(LocalDate today) => watchComputed(
    _database,
    _source.workoutWeekTables,
    () => _source.loadWorkoutWeek(today),
  ).distinct().map(_workoutWeek);

  WorkoutWeekCard _workoutWeek(WorkoutWeekInputs inputs) =>
      buildWorkoutWeekCard(
        today: inputs.today,
        days: inputs.days,
        usageStart: inputs.usageStart,
        weeklyTarget: inputs.weeklyTarget,
      );
}
