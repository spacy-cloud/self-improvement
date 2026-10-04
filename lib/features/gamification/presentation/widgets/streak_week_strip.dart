import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/features/gamification/presentation/gamification_labels.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The last seven days with their concrete dates and their status.
///
/// At normal text size the days share one row: weekday, marker, date. The
/// state is never only a colour: an active day shows a check mark, an inactive
/// day a dash, today's open day a ring and a day before the profile start an
/// empty outline; every day also has a spoken label with the full date and the
/// status in words. On large text (above 130 %) the row would not fit, so the
/// days become a list with the full date and the status as visible text.
class StreakWeekStrip extends StatelessWidget {
  /// Creates the strip for the seven [days] (oldest first, today last).
  const StreakWeekStrip({required this.days, required this.today, super.key});

  /// The seven days, oldest first.
  final List<StreakDay> days;

  /// Today, for the "Heute" label and the year of the spoken dates.
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Letzte sieben Tage',
      child: context.isLargeText
          ? _DayList(days: days, today: today)
          : _DayRow(days: days, today: today),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.days, required this.today});

  final List<StreakDay> days;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final day in days)
          Expanded(
            child: _DayCell(day: day, today: today),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today});

  final StreakDay day;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final isToday = day.date == today;
    final label = isToday ? 'Heute' : weekdayTwoLetters(day.date);
    final muted = day.status == StreakDayStatus.beforeStart;
    return Semantics(
      container: true,
      label: streakDayLabel(day, today),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style:
                  (isToday
                          ? AppTextStyles.captionStrong
                          : AppTextStyles.captionDefault)
                      .copyWith(
                        color: muted ? colors.textTertiary : colors.textPrimary,
                      ),
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) => StreakDayMarker(
              status: day.status,
              size: math.min(36, math.max(24, constraints.maxWidth - 4)),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              streakDayShortDate(day),
              maxLines: 1,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.days, required this.today});

  final List<StreakDay> days;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final day in days)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Semantics(
              container: true,
              label: streakDayLabel(day, today),
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  StreakDayMarker(status: day.status, size: 32),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${day.date == today ? 'Heute – ' : ''}'
                          '${streakDayDate(day, today)}',
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          _capitalized(streakDayStatusText(day)),
                          style: AppTextStyles.bodyRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _capitalized(String text) =>
      text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// The round marker of one day: check mark (active), ring (today, still
/// open), dash (inactive) or empty outline (before the profile start).
///
/// Decorative: the owner of the marker supplies the spoken label.
class StreakDayMarker extends StatelessWidget {
  /// Creates a marker of [size] logical pixels.
  const StreakDayMarker({required this.status, required this.size, super.key});

  /// The status the marker shows.
  final StreakDayStatus status;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final streak = colors.accent(AppAccent.streak);
    final (Color? fill, Border? border, Widget? child) = switch (status) {
      StreakDayStatus.active => (
        streak,
        null,
        Icon(AppIcon.check.data, size: size * 0.58, color: colors.surface),
      ),
      StreakDayStatus.todayOpen => (
        colors.surface,
        Border.all(color: streak, width: 2.5),
        DecoratedBox(
          decoration: BoxDecoration(color: streak, shape: BoxShape.circle),
          child: SizedBox.square(dimension: size * 0.22),
        ),
      ),
      StreakDayStatus.inactive => (
        colors.track,
        null,
        Icon(
          Icons.remove_rounded,
          size: size * 0.5,
          color: colors.textSecondary,
        ),
      ),
      StreakDayStatus.beforeStart => (
        null,
        Border.all(color: colors.borderInput, width: 1.5),
        null,
      ),
    };
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: border,
        ),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}
