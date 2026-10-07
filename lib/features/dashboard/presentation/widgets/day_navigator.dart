import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/domain/day_browser.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/shared/german_date.dart';

/// The row above the day on Home (BS-93): the arrow to the previous day, the
/// date of the day shown, the arrow to the next day.
///
/// The arrows are the way to page through the days without a swipe, for people
/// who cannot or do not want to use the gesture and for screen readers (whose
/// own swipes never reach the page). Each is a 48 x 48 button with a label that
/// names the day it leads to ("Vorheriger Tag, Freitag, 11. September"). At the
/// ends of the reachable days an arrow is disabled and keeps its place and its
/// label, so the layout does not jump and the focus of a screen reader stays on
/// it (the oldest day has no previous one, today has no next one).
///
/// The date is a heading and a live region: when the day changes, a screen
/// reader announces it with its distance to today ("Montag, 5. Oktober, vor 2
/// Tagen"). [dateFocusNode] lets the page put the focus there, for example after
/// "Zurück zu heute", when the button that had it is gone. With large text the
/// arrows take a row of their own above the date, so a long weekday never breaks
/// inside a word.
class DayNavigator extends StatelessWidget {
  /// Creates the navigator for [day].
  const DayNavigator({
    required this.day,
    required this.onPrevious,
    required this.onNext,
    this.dateFocusNode,
    super.key,
  });

  /// The day shown and the days around it.
  final BrowsedDay day;

  /// Goes to the day before ([BrowsedDay.canGoBack]).
  final VoidCallback onPrevious;

  /// Goes to the day after ([BrowsedDay.canGoForward]).
  final VoidCallback onNext;

  /// The focus node of the date, for a page that moves the focus there.
  final FocusNode? dateFocusNode;

  @override
  Widget build(BuildContext context) {
    final previous = day.previous;
    final next = day.next;
    final back = AppIconButton(
      icon: AppIcon.back.data,
      iconSize: 22,
      filled: true,
      semanticLabel: previous == null
          ? 'Vorheriger Tag'
          : 'Vorheriger Tag, ${formatDateLong(previous)}',
      onPressed: day.canGoBack ? onPrevious : null,
    );
    final forward = AppIconButton(
      icon: AppIcon.chevronRight.data,
      iconSize: 22,
      filled: true,
      semanticLabel: next == null
          ? 'Nächster Tag'
          : 'Nächster Tag, ${formatDateLong(next)}',
      onPressed: day.canGoForward ? onNext : null,
    );
    final date = _DateText(day: day, focusNode: dateFocusNode);
    if (context.isLargeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(children: <Widget>[back, const Spacer(), forward]),
          date,
          const SizedBox(height: AppSpacing.s4),
        ],
      );
    }
    return Row(
      children: <Widget>[
        back,
        Expanded(child: date),
        forward,
      ],
    );
  }
}

class _DateText extends StatelessWidget {
  const _DateText({required this.day, required this.focusNode});

  final BrowsedDay day;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    // The `Focus` adds no semantics of its own: the node below carries the
    // focus flags together with the heading and the label, so the date is ONE
    // element for a screen reader.
    return Focus(
      focusNode: focusNode,
      skipTraversal: true,
      includeSemantics: false,
      child: Builder(
        builder: (context) => Semantics(
          container: true,
          header: true,
          liveRegion: true,
          focusable: true,
          focused: Focus.of(context).hasFocus,
          label: day.spoken,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: Text(
              day.dateText,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleCard.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
