import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/internal/ink_surface.dart';
import 'package:self_improvement/core/design/motion/app_motion.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_shadows.dart';
import 'package:self_improvement/core/design/tokens/app_sizes.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// One option of a [PeriodSelector].
class PeriodOption<T> {
  /// Creates an option.
  const PeriodOption({
    required this.value,
    required this.label,
    this.semanticLabel,
  });

  /// The value reported when the option is chosen.
  final T value;

  /// Visible text, for example "7 Tage".
  final String label;

  /// Overrides the spoken label (defaults to [label]).
  final String? semanticLabel;
}

/// Segmented control for a period or a view (for example 7 / 30 / 90 Tage).
///
/// The track is 4 px padded, the selected segment is a raised surface. Each
/// segment is at least 48 high, announces "ausgewählt" when selected and wraps
/// its label on large text.
class PeriodSelector<T> extends StatelessWidget {
  /// Creates a segmented control.
  const PeriodSelector({
    required this.options,
    required this.selected,
    required this.onChanged,
    super.key,
    this.semanticLabel,
  }) : assert(options.length >= 2, 'A selector needs at least two options');

  /// The options in display order.
  final List<PeriodOption<T>> options;

  /// The selected value.
  final T selected;

  /// Called with the value of the tapped segment.
  final ValueChanged<T> onChanged;

  /// Spoken name of the whole control (for example "Zeitraum").
  final String? semanticLabel;

  /// The options 7, 30 and 90 days.
  static const List<PeriodOption<int>> dayOptions = <PeriodOption<int>>[
    PeriodOption<int>(value: 7, label: '7 Tage'),
    PeriodOption<int>(value: 30, label: '30 Tage'),
    PeriodOption<int>(value: 90, label: '90 Tage'),
  ];

  /// A selector for 7, 30 or 90 days.
  static PeriodSelector<int> days({
    required int selectedDays,
    required ValueChanged<int> onChanged,
    Key? key,
  }) {
    return PeriodSelector<int>(
      key: key,
      options: dayOptions,
      selected: selectedDays,
      onChanged: onChanged,
      semanticLabel: 'Zeitraum',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.track,
          borderRadius: BorderRadius.circular(AppRadii.segmentOuter),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < options.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: _Segment(
                      label: options[i].label,
                      semanticLabel: options[i].semanticLabel,
                      selected: options[i].value == selected,
                      duration: motion.fast,
                      onTap: () => onChanged(options[i].value),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    const radius = BorderRadius.all(Radius.circular(AppRadii.segmentInner));
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: radius,
          boxShadow: selected ? AppShadows.segment : null,
        ),
        child: InkSurface(
          onTap: onTap,
          shape: const RoundedRectangleBorder(borderRadius: radius),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style:
                    (selected
                            ? AppTextStyles.bodyStrong
                            : AppTextStyles.bodyDefault)
                        .copyWith(
                          color: selected
                              ? colors.textPrimary
                              : colors.textSecondary,
                        ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
