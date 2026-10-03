/// Pure rules of the goal editor: texts, typed input, stepping and the
/// "today versus from tomorrow" view of every goal.
///
/// The ranges and steps come from [GoalType] (water 250 to 10.000 ml in 50 ml
/// steps, steps 100 to 100.000, focus 5 to 180 minutes, workouts 1 to 14 per
/// week; weight entry and task completion are plain on/off switches). Changes
/// are saved by `GoalsCommands` and take effect from tomorrow.
library;

import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// The order in which goals are listed (editor and profile summary).
const List<GoalType> goalDisplayOrder = <GoalType>[
  GoalType.water,
  GoalType.steps,
  GoalType.focusMinutes,
  GoalType.weightEntry,
  GoalType.taskCompletion,
  GoalType.workoutWeekly,
];

/// Texts and stepping of one goal type.
@immutable
final class GoalEditorSpec {
  const GoalEditorSpec({
    required this.type,
    required this.title,
    required this.caption,
    required this.inputLabel,
    required this.unit,
    required this.stepAmount,
  });

  final GoalType type;

  /// Row title, for example "Wasser".
  final String title;

  /// Line below the title, for example "pro Tag".
  final String caption;

  /// Spoken name of the value field, for example "Wasserziel in Millilitern".
  final String inputLabel;

  /// Short unit shown next to the value field, for example "ml". Empty for
  /// switches and for steps (the title already says what is counted).
  final String unit;

  /// How far the plus and minus buttons move the value (0 for switches).
  final int stepAmount;

  /// Whether the goal is an on/off switch without a value.
  bool get isSwitch => type.isSwitch;
}

/// The editor texts of [type].
GoalEditorSpec goalEditorSpec(GoalType type) {
  return switch (type) {
    GoalType.water => const GoalEditorSpec(
      type: GoalType.water,
      title: 'Wasser',
      caption: 'pro Tag',
      inputLabel: 'Wasserziel in Millilitern',
      unit: 'ml',
      stepAmount: 250,
    ),
    GoalType.steps => const GoalEditorSpec(
      type: GoalType.steps,
      title: 'Schritte',
      caption: 'pro Tag',
      inputLabel: 'Schrittziel pro Tag',
      unit: '',
      stepAmount: 500,
    ),
    GoalType.focusMinutes => const GoalEditorSpec(
      type: GoalType.focusMinutes,
      title: 'Fokus',
      caption: 'pro Tag',
      inputLabel: 'Fokusziel in Minuten',
      unit: 'Min.',
      stepAmount: 5,
    ),
    GoalType.weightEntry => const GoalEditorSpec(
      type: GoalType.weightEntry,
      title: 'Gewicht erfassen',
      caption: 'mindestens ein Eintrag pro Tag',
      inputLabel: 'Gewicht erfassen',
      unit: '',
      stepAmount: 0,
    ),
    GoalType.taskCompletion => const GoalEditorSpec(
      type: GoalType.taskCompletion,
      title: 'Aufgabe erledigen',
      caption: 'mindestens eine pro Tag',
      inputLabel: 'Aufgabe erledigen',
      unit: '',
      stepAmount: 0,
    ),
    GoalType.workoutWeekly => const GoalEditorSpec(
      type: GoalType.workoutWeekly,
      title: 'Workouts',
      caption: 'pro Woche',
      inputLabel: 'Workout-Wochenziel',
      unit: '×',
      stepAmount: 1,
    ),
  };
}

/// The value of a goal as short text: "2,5 l", "10.000", "25 Min.", "3×".
/// Empty for switch goals.
String goalValueText(GoalType type, int target) {
  return switch (type) {
    GoalType.water => '${formatLiters(target)} l',
    GoalType.steps => formatThousands(target),
    GoalType.focusMinutes => '$target Min.',
    GoalType.workoutWeekly => '$target×',
    GoalType.weightEntry || GoalType.taskCompletion => '',
  };
}

/// The goal as one line for lists: "2,5 l pro Tag", "3× pro Woche", "Täglich"
/// for switches that are on and "Aus" for a goal that is switched off.
String goalSummaryText(
  GoalType type, {
  required int target,
  bool enabled = true,
}) {
  if (!enabled) {
    return 'Aus';
  }
  return switch (type) {
    GoalType.water ||
    GoalType.steps ||
    GoalType.focusMinutes => '${goalValueText(type, target)} pro Tag',
    GoalType.workoutWeekly => '${goalValueText(type, target)} pro Woche',
    GoalType.weightEntry || GoalType.taskCompletion => 'Täglich',
  };
}

/// Result of [parseGoalText].
sealed class GoalTextResult {
  const GoalTextResult();
}

/// A typed value that [GoalType.validateTarget] accepts.
final class GoalTextValid extends GoalTextResult {
  const GoalTextValid(this.value);

  final int value;
}

/// A typed value that cannot be saved; [message] is the German hint.
final class GoalTextInvalid extends GoalTextResult {
  const GoalTextInvalid(this.message);

  final String message;
}

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Parses the text typed into the value field of [type].
///
/// Digits only; the range and the step come from [GoalType.validateTarget], so
/// water accepts exactly 250 to 10.000 in steps of 50.
GoalTextResult parseGoalText(GoalType type, String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const GoalTextInvalid('Bitte gib einen Wert ein.');
  }
  if (!_digitsOnly.hasMatch(trimmed)) {
    return const GoalTextInvalid('Bitte gib eine ganze Zahl ein.');
  }
  final significant = trimmed.replaceFirst(RegExp(r'^0+'), '');
  final value = significant.length > 9
      ? type.maxTarget + 1
      : int.parse(trimmed);
  final validation = type.validateTarget(value);
  if (validation.isValid) {
    return GoalTextValid(value);
  }
  return GoalTextInvalid(goalTargetMessage(type, validation));
}

/// German hint for a rejected target of [type].
String goalTargetMessage(GoalType type, GoalTargetValidation validation) {
  final min = formatThousands(type.minTarget);
  final max = formatThousands(type.maxTarget);
  return switch (type) {
    GoalType.water =>
      validation == GoalTargetValidation.notOnStep
          ? 'Bitte gib die Menge in ${type.step}-ml-Schritten an, '
                'zum Beispiel 2500.'
          : 'Bitte gib eine Menge zwischen $min und $max ml ein.',
    GoalType.steps => 'Bitte gib eine Schrittzahl zwischen $min und $max ein.',
    GoalType.focusMinutes =>
      'Bitte gib eine Dauer zwischen $min und $max Minuten ein.',
    GoalType.workoutWeekly =>
      'Bitte gib eine Anzahl zwischen $min und $max Workouts pro Woche ein.',
    GoalType.weightEntry || GoalType.taskCompletion => 'Ungültiger Zielwert.',
  };
}

/// The value after pressing plus ([direction] 1) or minus ([direction] -1).
///
/// Starts from the typed text when it is valid, otherwise from [fallback] (the
/// last saved value). The result is clamped to the range of the type and stays
/// on its step grid. Returns `null` for switch goals.
int? stepGoalTarget({
  required GoalType type,
  required String text,
  required int fallback,
  required int direction,
}) {
  final amount = goalEditorSpec(type).stepAmount;
  if (amount == 0) {
    return null;
  }
  final parsed = parseGoalText(type, text);
  final base = switch (parsed) {
    GoalTextValid(:final value) => value,
    GoalTextInvalid() => fallback,
  };
  final moved = (base + direction * amount).clamp(
    type.minTarget,
    type.maxTarget,
  );
  final steps = (moved - type.minTarget) ~/ type.step;
  return type.minTarget + steps * type.step;
}

/// One goal as stored for a day: the value and the on/off switch.
typedef GoalValue = ({int target, bool enabled});

/// A goal of the editor with what applies today and from tomorrow.
@immutable
final class GoalEditorRow {
  const GoalEditorRow({
    required this.type,
    required this.visible,
    required this.today,
    required this.tomorrow,
  });

  final GoalType type;

  /// Whether the module of the goal is on. Goals of switched-off modules are
  /// hidden and stay stored untouched.
  final bool visible;

  /// The version that applies today.
  final GoalValue today;

  /// The version that applies from tomorrow (includes changes saved earlier
  /// today). This is where the editor starts.
  final GoalValue tomorrow;

  /// Whether a change saved earlier already differs from today's version.
  bool get hasPendingChange => today != tomorrow;

  @override
  bool operator ==(Object other) =>
      other is GoalEditorRow &&
      other.type == type &&
      other.visible == visible &&
      other.today == today &&
      other.tomorrow == tomorrow;

  @override
  int get hashCode => Object.hash(type, visible, today, tomorrow);
}

/// All goals of the editor for one day.
@immutable
final class GoalEditorModel {
  const GoalEditorModel({
    required this.today,
    required this.tomorrow,
    required this.rows,
  });

  /// The local day the model was built for.
  final LocalDate today;

  /// The day on which edits take effect.
  final LocalDate tomorrow;

  /// One row per goal type in [goalDisplayOrder].
  final List<GoalEditorRow> rows;

  /// The row of [type].
  GoalEditorRow rowOf(GoalType type) =>
      rows.singleWhere((row) => row.type == type);

  /// The rows whose module is on.
  List<GoalEditorRow> get visibleRows =>
      rows.where((row) => row.visible).toList(growable: false);

  /// The rows that are hidden because their module is off.
  List<GoalEditorRow> get hiddenRows =>
      rows.where((row) => !row.visible).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      other is GoalEditorModel &&
      other.today == today &&
      listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(today, Object.hashAll(rows));
}

/// Builds the editor model: per goal type the version in effect today and the
/// one in effect tomorrow (the latter includes an edit saved earlier today).
GoalEditorModel buildGoalEditorModel({
  required Iterable<GoalVersion> versions,
  required LocalDate today,
  required Map<ModuleId, bool> modules,
}) {
  final tomorrow = nextEffectiveDate(today);
  GoalValue valueOn(GoalType type, LocalDate day) {
    final version = effectiveGoalOrDefault(versions, type, day);
    return (
      target: type.resolveTarget(version.target),
      enabled: version.enabled,
    );
  }

  return GoalEditorModel(
    today: today,
    tomorrow: tomorrow,
    rows: List.unmodifiable([
      for (final type in goalDisplayOrder)
        GoalEditorRow(
          type: type,
          visible: modules[type.module] ?? true,
          today: valueOn(type, today),
          tomorrow: valueOn(type, tomorrow),
        ),
    ]),
  );
}
