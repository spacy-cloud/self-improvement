import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/core/design/icons/habit_icon.dart' as design;
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';

/// Glyph and accent of a habit symbol. The symbol's key is stored; the accent
/// colour is NOT stored, it comes from the design tokens (coupled to the
/// symbol, there is no free colour editor).
({IconData glyph, AppAccent accent}) habitVisual(HabitIcon icon) {
  final visual = design.HabitIcon.tryParse(icon.key) ?? design.HabitIcon.book;
  return (glyph: visual.icon, accent: visual.accent);
}

/// Whether the system text scale is large enough that a row puts its controls
/// above the text instead of beside it (the threshold of the design system),
/// so long words keep the full card width instead of breaking.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14 > AppSizes.stackTextScale;

/// The priority of a task as a small pill: flag and the word, never colour
/// alone. Decorative for screen readers: the row's label already says it.
class PriorityPill extends StatelessWidget {
  const PriorityPill({required this.priority, super.key});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final (background, foreground) = switch (priority) {
      TaskPriority.high => (colors.errorTint, colors.error),
      TaskPriority.normal => (colors.warningTint, colors.warningText),
      TaskPriority.low => (colors.track, colors.textSecondary),
    };
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.flag_rounded, size: 12, color: foreground),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  priority.label,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Label of a form block (like the label of `AppTextField`): the name and, on
/// the right, "optional".
class FieldLabel extends StatelessWidget {
  const FieldLabel({required this.label, this.requirement, super.key});

  final String label;
  final String? requirement;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: AppTextStyles.bodyStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        if (requirement != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            requirement!,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Error message directly at a field: icon and text on the error tint, never
/// colour alone. Announced when it appears.
class FieldMessage extends StatelessWidget {
  const FieldMessage({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(AppIcon.error.data, size: 14, color: colors.error),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: AppTextStyles.captionStrong.copyWith(
                    color: colors.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One option of a [SegmentedChoice].
class SegmentOption<T> {
  const SegmentOption({
    required this.value,
    required this.label,
    this.badge,
    this.semanticLabel,
  });

  final T value;

  /// Visible text, e.g. "Aufgaben".
  final String label;

  /// Small count next to the label, e.g. "4 offen".
  final String? badge;

  /// Overrides the spoken label (default: label and badge).
  final String? semanticLabel;
}

/// A segmented control like the design system's `PeriodSelector`, but with
/// large text the segments are stacked instead of squeezed next to each other,
/// so no label breaks inside a word (a task priority or a view name at 200 %
/// on a 320 px phone). Every segment is at least 48 high and announces
/// "ausgewählt" when selected.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  }) : assert(options.length >= 2, 'A segmented control needs two options');

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Spoken name of the whole control, e.g. "Priorität".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final segments = <Widget>[
      for (final option in options)
        _Segment(
          label: option.label,
          badge: option.badge,
          semanticLabel:
              option.semanticLabel ??
              (option.badge == null
                  ? option.label
                  : '${option.label}, ${option.badge}'),
          selected: option.value == selected,
          onTap: () => onChanged(option.value),
        ),
    ];
    final stacked = isLargeText(context);
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
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < segments.length; i++) ...<Widget>[
                      if (i > 0) const SizedBox(height: 4),
                      segments[i],
                    ],
                  ],
                )
              : IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (var i = 0; i < segments.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(child: segments[i]),
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
    required this.badge,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? badge;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    const radius = BorderRadius.all(Radius.circular(AppRadii.segmentInner));
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: motion.fast,
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: radius,
          boxShadow: selected ? AppShadows.segment : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: <Widget>[
                    Text(
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
                    if (badge != null)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? colors.primaryTint
                              : colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          child: Text(
                            badge!,
                            style: AppTextStyles.captionStrong.copyWith(
                              color: selected
                                  ? colors.primaryText
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tappable body of a list row next to its own controls (checkbox, menu).
/// Unlike `EntryListTile` it does not swallow the semantics of siblings: the
/// row is several focus targets, each with its own German label.
class TappableBody extends StatelessWidget {
  const TappableBody({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
    this.semanticHint,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;

  /// Complete spoken description of the row.
  final String semanticLabel;

  /// What activating does, e.g. "Öffnet die Aufgabe".
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      hint: semanticHint,
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Neutral loading placeholder of a list: no spinner, no invented numbers.
class TasksLoadingPlaceholder extends StatelessWidget {
  const TasksLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: 120);
}
