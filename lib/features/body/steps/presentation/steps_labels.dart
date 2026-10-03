/// German texts of the steps screens that are derived from data (pure Dart).
library;

import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/body/steps/application/steps_stats.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// `7.450`.
String stepsText(int steps) => formatThousands(steps);

/// `/ 10.000`, or null without an applicable goal.
String? stepsTargetText(StepsProgress progress) =>
    progress.target == null ? null : '/ ${formatThousands(progress.target!)}';

/// `75 % vom Tagesziel`; without a goal the honest statement that none applies.
String stepsPercentText(StepsProgress progress) => progress.percent == null
    ? 'Kein Tagesziel aktiv'
    : '${progress.percent} % vom Tagesziel';

/// The remaining steps, `Ziel erreicht`, or null without a goal.
String? stepsRemainingText(StepsProgress progress) {
  final target = progress.target;
  if (target == null) {
    return null;
  }
  return progress.reached
      ? 'Ziel erreicht'
      : 'Noch ${formatThousands(target - progress.steps)}';
}

/// `Heute, 14. September`, `Gestern, 13. September`, otherwise the long date
/// (with the year when it differs from today's).
String stepsDateHeading(LocalDate date, LocalDate today) {
  final daysAgo = date.daysUntil(today);
  final day = '${date.day}. ${monthLong(date.month)}';
  if (daysAgo == 0) {
    return 'Heute, $day';
  }
  if (daysAgo == 1) {
    return 'Gestern, $day';
  }
  final long = formatDateLong(date);
  return date.year == today.year ? long : '$long ${date.year}';
}

/// How the day is named inside a sentence: `heute`, `gestern` or a short date.
String stepsDateInSentence(LocalDate date, LocalDate today) {
  final daysAgo = date.daysUntil(today);
  if (daysAgo == 0) {
    return 'heute';
  }
  if (daysAgo == 1) {
    return 'gestern';
  }
  return formatDateShort(date, contextYear: today.year);
}

/// `Bester Tag (Sa)` for the week, `Bester Tag (14. Sep.)` for longer windows.
String stepsBestDayLabel(StepsStats stats) {
  final date = stats.bestDate;
  if (date == null) {
    return 'Bester Tag';
  }
  final text = stats.windowDays <= 7
      ? weekdayTwoLetters(date)
      : formatDayMonth(date);
  return 'Bester Tag ($text)';
}

/// The state of one history day for text and table.
String stepsDayStatus(StepsHistoryDay day) {
  if (!day.recorded) {
    return 'Nicht erfasst';
  }
  if (day.progress.target == null) {
    return 'Kein Tagesziel';
  }
  return day.progress.reached ? 'Ziel erreicht' : 'Ziel nicht erreicht';
}

/// One sentence that tells what the chart shows (its text alternative).
String stepsChartSummary(StepsStats stats) {
  if (stats.isEmpty) {
    return 'In den letzten ${stats.windowDays} Tagen sind keine Schritte '
        'erfasst.';
  }
  final buffer = StringBuffer(
    '${stats.recordedDays} von ${stats.windowDays} Tagen erfasst, im '
    'Schnitt ${stepsText(stats.averageSteps!)} Schritte pro Tag, bester Tag '
    '${stepsText(stats.bestSteps!)} Schritte.',
  );
  if (stats.hasTarget) {
    buffer.write(
      ' Das Tagesziel wurde an ${stats.reachedDays} '
      '${stats.reachedDays == 1 ? 'Tag' : 'Tagen'} erreicht.',
    );
  }
  return buffer.toString();
}

/// Title of the chart period buttons: `7 T`, `30 T`, `3 M` for 90 days.
String stepsPeriodLabel(int days) => switch (days) {
  7 => '7 T',
  30 => '30 T',
  90 => '3 M',
  _ => '$days T',
};

/// Spoken name of a chart period.
String stepsPeriodSpoken(int days) => switch (days) {
  7 => '7 Tage',
  30 => '30 Tage',
  90 => '3 Monate, 90 Tage',
  _ => '$days Tage',
};
