/// German display texts for water: amounts, progress and the success
/// messages shown with the undo snackbar. Pure functions without locale data.
library;

import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/number_format.dart';

/// An entry amount in ml: `250 ml`, `1.250 ml`.
String formatWaterMl(int ml) => '${formatThousands(ml)} ml';

/// A total in litres with up to two decimals and no unnecessary zeros:
/// `1,25 l`, `2,5 l`, `2 l`. A remainder below 10 ml is not shown (`1255` is
/// `1,25 l`); the exact amount is available through [formatWaterMl].
String formatWaterLiters(int ml) => '${formatLiters(ml)} l';

/// A real percentage, also above 100: `75 %`, `112 %`.
String formatWaterPercent(int percent) => '$percent %';

/// Snackbar text after a quick add or a saved custom amount.
String waterAddedMessage(int amountMl) =>
    '${formatWaterMl(amountMl)} hinzugefügt';

/// Snackbar text after an edit.
const String waterUpdatedMessage = 'Eintrag aktualisiert';

/// Snackbar text after a delete.
const String waterDeletedMessage = 'Eintrag gelöscht';

/// Success text after the daily target was saved; it always says that the
/// change applies from tomorrow.
String waterGoalSavedMessage(int targetMl) =>
    'Tagesziel auf ${formatWaterLiters(targetMl)} gesetzt. '
    'Es gilt ab morgen.';

/// Label of the progress display for screen readers and as visible text: the
/// state is never conveyed by colour alone.
///
/// - without a target: `Wasser heute: 1,25 l, kein Tagesziel aktiv.`
/// - below the target: `Wasser heute: 1,25 l von 2,5 l, 50 Prozent erreicht.`
/// - at or above: `Wasser heute: 2,8 l von 2,5 l, 112 Prozent erreicht,
///   Tagesziel erreicht.`
String waterProgressLabel(WaterToday today) {
  final total = formatWaterLiters(today.totalMl);
  final target = today.targetMl;
  final percent = today.percent;
  if (target == null || percent == null) {
    return 'Wasser heute: $total, kein Tagesziel aktiv.';
  }
  final base =
      'Wasser heute: $total von ${formatWaterLiters(target)}, '
      '$percent Prozent erreicht';
  return today.goalReached ? '$base, Tagesziel erreicht.' : '$base.';
}
