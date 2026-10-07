import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/tap_surface.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The note above "Ziele heute" when it shows another day than today: "Nicht
/// heute", the date, and the way back ("Zurück zu heute").
///
/// "Ziele heute" is built so that the page that pages through days (BS-93) can
/// show a past day with it; until that exists the page always shows today and
/// never builds this note. Without [onBackToToday] the note has no action.
class NotTodayBanner extends StatelessWidget {
  /// Creates the note for [date].
  const NotTodayBanner({required this.date, this.onBackToToday, super.key});

  /// The day shown.
  final LocalDate date;

  /// Goes back to today; `null` hides the action.
  final VoidCallback? onBackToToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Nicht heute',
          style: AppTextStyles.bodyStrong.copyWith(color: colors.warningText),
        ),
        Text(
          '${date.day}. ${monthLong(date.month)} · nur ansehen',
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.warningText,
          ),
        ),
      ],
    );
    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.calendar_today_outlined,
          size: 20,
          color: colors.warningText,
        ),
        const SizedBox(width: 10),
        Expanded(child: texts),
      ],
    );
    final action = onBackToToday == null
        ? null
        : Semantics(
            container: true,
            button: true,
            label: 'Zurück zu heute',
            onTap: onBackToToday,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.touchMin,
                minWidth: AppSizes.touchMin,
              ),
              child: TapSurface(
                onTap: onBackToToday,
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.controlBorder,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Zurück zu heute',
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: colors.primaryText,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.warningTint,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = context.isLargeText || constraints.maxWidth < 300;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: head,
                  ),
                  ?action,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(child: head),
                ?action,
              ],
            );
          },
        ),
      ),
    );
  }
}
