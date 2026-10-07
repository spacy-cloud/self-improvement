import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';

/// The day overview: the ring with "x von y" in the middle, the title of the day
/// (one of the three neutral texts of the stand of the goals) and a factual
/// sentence about today's goals.
///
/// Only for a day with at least one applicable goal; without one the dashboard
/// shows "Noch keine Tagesziele" instead, never a 0/0 ring. The ring is a
/// picture of the same numbers that the text says, and it has its own spoken
/// label. Its arc colour follows the stand (grey, yellow, green) and is chosen
/// by `ProgressRing.goals`, not here, so that every day ring looks the same.
///
/// On a day that is not today ([isToday] false, BS-93) the card carries no title
/// and its sentence speaks of "diesem Tag" ("An diesem Tag hast du 3 von 5 Zielen
/// erreicht."); the ring and its colour follow the stand as ever.
///
/// With [onTap] the whole card is one button that opens "Ziele heute" (BS-104):
/// a chevron shows it, while it is pressed the card takes the green tint and
/// border of the design, and a screen reader hears one element ("Ziele heute,
/// 2 von 4 erreicht, Details öffnen") instead of the ring, the title and the
/// sentence one after the other. Without [onTap] it only shows.
class DayOverviewCard extends StatefulWidget {
  /// Creates the card for [fulfilled] of [applicable] goals (applicable >= 1).
  const DayOverviewCard({
    required this.fulfilled,
    required this.applicable,
    this.motivation,
    this.onTap,
    this.isToday = true,
    super.key,
  }) : assert(applicable >= 1, 'The ring needs at least one applicable goal');

  /// Goals reached today.
  final int fulfilled;

  /// Goals that apply today.
  final int applicable;

  /// The title of the day (`motivationTextFor`), or `null` for no title: the
  /// texts speak of "today", so a past day shows only the factual sentence.
  final String? motivation;

  /// Opens "Ziele heute"; `null` makes the card a plain display.
  final VoidCallback? onTap;

  /// Whether the card shows today. The sentence and the spoken text of a day
  /// that is not today say "an diesem Tag" instead of "heute".
  final bool isToday;

  /// The spoken text of the ring.
  String get ringLabel => applicable == 1
      ? '$fulfilled von 1 Ziel erreicht'
      : '$fulfilled von $applicable Zielen erreicht';

  /// The spoken text of the whole card as a button (BS-104). It replaces the
  /// texts inside, so nothing is read twice.
  String get tapLabel => isToday
      ? 'Ziele heute, $fulfilled von $applicable erreicht, Details öffnen'
      : 'Ziele dieses Tages, $fulfilled von $applicable erreicht, '
            'Details öffnen';

  /// The factual sentence next to the ring.
  String get summary {
    if (!isToday) {
      if (fulfilled >= applicable) {
        return applicable == 1
            ? 'An diesem Tag hast du dein Tagesziel erreicht.'
            : 'An diesem Tag hast du alle Tagesziele erreicht.';
      }
      if (fulfilled == 0) {
        return 'An diesem Tag hast du kein Ziel erreicht.';
      }
      return 'An diesem Tag hast du $fulfilled von $applicable Zielen '
          'erreicht.';
    }
    if (fulfilled >= applicable) {
      return applicable == 1
          ? 'Du hast heute dein Tagesziel erreicht.'
          : 'Du hast heute alle Tagesziele erreicht.';
    }
    if (fulfilled == 0) {
      return 'Du hast heute noch kein Ziel erreicht.';
    }
    return 'Du hast heute $fulfilled von $applicable Zielen erreicht.';
  }

  @override
  State<DayOverviewCard> createState() => _DayOverviewCardState();
}

class _DayOverviewCardState extends State<DayOverviewCard> {
  /// Whether a finger is down on the card (the pressed look of the design).
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final tappable = widget.onTap != null;
    final ring = ProgressRing.goals(
      fulfilled: widget.fulfilled,
      applicable: widget.applicable,
      semanticLabel: widget.ringLabel,
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${widget.fulfilled} von ${widget.applicable}',
            maxLines: 1,
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
          Text(
            widget.applicable == 1 ? 'Ziel' : 'Zielen',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final title = widget.motivation;
    // The chevron sits in the top right corner; the first line of text keeps
    // clear of it.
    final firstLineInset = EdgeInsets.only(right: tappable ? 28 : 0);
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (title != null) ...<Widget>[
          Padding(
            padding: firstLineInset,
            child: Text(
              title,
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
        Padding(
          padding: title == null ? firstLineInset : EdgeInsets.zero,
          child: Text(
            widget.summary,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
    final content = LayoutBuilder(
      builder: (context, constraints) {
        final stacked = context.isLargeText || constraints.maxWidth < 280;
        final Widget layout = stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Center(child: ring),
                  const SizedBox(height: AppSpacing.s16),
                  texts,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  ring,
                  const SizedBox(width: AppSpacing.s24),
                  Expanded(child: texts),
                ],
              );
        if (!tappable) {
          return layout;
        }
        return Stack(
          children: <Widget>[
            layout,
            Positioned(
              top: 0,
              right: 0,
              child: Icon(
                AppIcon.chevronRight.data,
                size: 20,
                color: colors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
    if (!tappable) {
      return AppCard(padding: const EdgeInsets.all(20), child: content);
    }
    return AppCard(
      padding: EdgeInsets.zero,
      borderColor: _pressed ? colors.primary : null,
      borderWidth: _pressed ? 1.5 : 1,
      child: Semantics(
        container: true,
        button: true,
        label: widget.tapLabel,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: Material(
          color: _pressed ? colors.primaryTint : Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) {
              if (mounted) {
                setState(() => _pressed = pressed);
              }
            },
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Padding(padding: const EdgeInsets.all(20), child: content),
          ),
        ),
      ),
    );
  }
}
