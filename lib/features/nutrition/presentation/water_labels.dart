import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/number_format.dart';

/// `1 Eintrag`, `4 Einträge`.
String formatEntryCount(int count) =>
    count == 1 ? '1 Eintrag' : '$count Einträge';

/// Name of a quick add button by its amount (the Figma labels): 250 ml is a
/// "Glas", 500 ml a "Flasche"; any other amount is just shown in ml.
String waterQuickLabel(int amountMl) => switch (amountMl) {
  250 => 'Glas',
  500 => 'Flasche',
  _ => formatWaterMl(amountMl),
};

/// Spoken label of a quick add button.
String waterQuickSemanticLabel(int amountMl) =>
    '${waterQuickLabel(amountMl)}, $amountMl Milliliter hinzufügen';

/// Second line of the goal row on the water screen: what counts today and what
/// applies from tomorrow.
String waterGoalSubtitle(WaterGoalSettings settings) {
  final today = settings.todayTargetMl;
  final tomorrow = settings.tomorrowEnabled
      ? formatWaterLiters(settings.tomorrowTargetMl)
      : null;
  if (!settings.hasPendingChange) {
    return today == null
        ? 'Kein Tagesziel aktiv'
        : '${formatWaterLiters(today)} · Änderungen gelten ab morgen';
  }
  final todayText = today == null
      ? 'Heute kein Tagesziel'
      : 'Heute ${formatWaterLiters(today)}';
  return tomorrow == null
      ? '$todayText, ab morgen kein Tagesziel'
      : '$todayText, ab morgen $tomorrow';
}

/// The hint of the goal sheet: a change never touches today.
String waterGoalApplyHint(WaterGoalSettings settings) {
  final today = settings.todayTargetMl;
  return today == null
      ? 'Die Änderung gilt ab morgen.'
      : 'Die Änderung gilt ab morgen. Heute zählt weiterhin '
            '${formatWaterLiters(today)}.';
}

/// `In 50-ml-Schritten · 250 bis 10.000 ml`.
String waterGoalRangeHint() =>
    'In $waterGoalStepMl-ml-Schritten · $minWaterGoalMl bis '
    '${formatThousands(maxWaterGoalMl)} ml';
