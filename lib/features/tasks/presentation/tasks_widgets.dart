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
