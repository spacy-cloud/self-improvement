import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/tap_surface.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/text_scale.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The note when the page shows another day than today: "Nicht heute", the way
/// back ("Zurück zu heute") and, on "Ziele heute", the date.
///
/// Two forms (BS-93): with a [date] it is the note of "Ziele heute" (the design
/// `4114:186`): "Nicht heute" with the line "12. September · nur ansehen". Without
/// one it is the note of Home (`4116:249`): the day navigator right above it
/// already names the date, so the note is one line, "Nicht heute", with the way
/// back. Without [onBackToToday] the note has no action.
class NotTodayBanner extends StatelessWidget {
  /// Creates the note; with [date] it names the day below "Nicht heute".
  const NotTodayBanner({this.date, this.onBackToToday, super.key});

  /// The day shown; `null` is the one-line note of Home.
  final LocalDate? date;

  /// Goes back to today; `null` hides the action.
  final VoidCallback? onBackToToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final date = this.date;
    final compact = date == null;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Nicht heute',
          style: AppTextStyles.bodyStrong.copyWith(color: colors.warningText),
        ),
        if (date != null)
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
          size: compact ? 18 : 20,
          color: colors.warningText,
        ),
        SizedBox(width: compact ? 8 : 10),
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
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, compact ? 4 : 8, 4, compact ? 4 : 8),
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
