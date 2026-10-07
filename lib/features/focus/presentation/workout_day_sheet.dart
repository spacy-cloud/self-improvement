import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/domain/workout_day_mark_kind.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';

/// What the user answered to "Wie war dein Tag?".
enum WorkoutDayChoice {
  /// A workout: the form opens.
  training,

  /// A rest day.
  rest,

  /// The workout of the day is skipped.
  skipped,
}

/// Glyph of a rest day (Figma `icon/moon`; the icon set of the design system
/// has no equivalent, like the glyphs of the onboarding options).
const IconData workoutRestIcon = Icons.bedtime_rounded;

/// Glyph of a skipped day (Figma `icon/skip`).
const IconData workoutSkipIcon = Icons.skip_next_rounded;

/// Shows [WorkoutDaySheet] ("Wie war dein Tag?", Figma `4117:473`) as a modal
/// bottom sheet and returns the choice, or `null` when it was closed (close
/// button, barrier, system back). The sheet covers the navigation bar too, so
/// the whole screen behind it is inert.
Future<WorkoutDayChoice?> showWorkoutDaySheet(BuildContext context) {
  final colors = context.tokens.colors;
  return showModalBottomSheet<WorkoutDayChoice>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, AppSpacing.s16),
      child: WorkoutDaySheet(
        onChoose: (choice) => Navigator.of(sheetContext).pop(choice),
        onClose: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

/// Asks "Wie war dein Tag?" and does what the answer says: a workout opens the
/// form, a rest day or a skipped day is marked for today (with the message and
/// "Rückgängig" after the commit, or the reason it failed).
///
/// Everything the future needs is read before the sheet opens, so the caller
/// may disappear while the sheet is shown.
Future<void> askHowTheDayWas(BuildContext context, WidgetRef ref) async {
  final router = GoRouter.of(context);
  final actions = ref.read(workoutDayActionsProvider.notifier);
  final feedback = ref.read(feedbackServiceProvider);
  final choice = await showWorkoutDaySheet(context);
  switch (choice) {
    case null:
      return;
    case WorkoutDayChoice.training:
      unawaited(router.push<Object?>(WorkoutRoutes.create));
    case WorkoutDayChoice.rest:
      await markWorkoutDay(actions, feedback, WorkoutDayMarkKind.rest);
    case WorkoutDayChoice.skipped:
      await markWorkoutDay(actions, feedback, WorkoutDayMarkKind.skipped);
  }
}

/// The content of the sheet: handle, "WORKOUT HEUTE" and "Wie war dein Tag?",
/// its own close button, the three answers (training, rest day, skip) and the
/// note that the weekly goal stays separate.
class WorkoutDaySheet extends StatelessWidget {
  const WorkoutDaySheet({
    required this.onChoose,
    required this.onClose,
    super.key,
  });

  /// Called with the answer; the caller closes the sheet.
  final ValueChanged<WorkoutDayChoice> onChoose;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Wie war dein Tag?',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadii.sheet + 8),
          border: Border.all(color: colors.borderDecorative),
          boxShadow: AppShadows.card(colors.shadow),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            10,
            AppSpacing.s16,
            AppSpacing.s16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: AppSizes.sheetHandleWidth,
                    height: AppSizes.sheetHandleHeight,
                    decoration: BoxDecoration(
                      color: colors.borderInput,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              _Header(onClose: onClose),
              const SizedBox(height: AppSpacing.s16),
              _Option(
                key: const ValueKey<String>('workout-day-training'),
                title: 'Training eintragen',
                subtitle: 'Workout erfassen',
                highlighted: true,
                leading: const AppIconTile(
                  icon: Icons.fitness_center_rounded,
                  accent: AppAccent.workout,
                  size: 42,
                  iconSize: 22,
                ),
                onTap: () => onChoose(WorkoutDayChoice.training),
              ),
              const SizedBox(height: 10),
              _Option(
                key: const ValueKey<String>('workout-day-rest'),
                title: 'Ruhetag',
                subtitle: 'Zählt als erreicht, keine XP',
                leading: const _NeutralTile(icon: workoutRestIcon),
                onTap: () => onChoose(WorkoutDayChoice.rest),
              ),
              const SizedBox(height: 10),
              _Option(
                key: const ValueKey<String>('workout-day-skipped'),
                title: 'Heute überspringen',
                subtitle: 'Zählt als erreicht, keine XP',
                leading: const _NeutralTile(icon: workoutSkipIcon),
                onTap: () => onChoose(WorkoutDayChoice.skipped),
              ),
              const SizedBox(height: AppSpacing.s12),
              Text(
                'Das Wochenziel bleibt getrennt und zählt nur echte Workouts.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final close = AppIconButton(
      icon: AppIcon.close.data,
      semanticLabel: 'Schließen',
      filled: true,
      onPressed: onClose,
    );
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'WORKOUT HEUTE',
            style: AppTextStyles.captionStrong.copyWith(
              color: colors.primaryText,
              letterSpacing: 0.66,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Wie war dein Tag?',
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
    // Large text: the close button gets its own row so the title can use the
    // full width instead of breaking inside words.
    if (scale > AppSizes.stackTextScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(alignment: Alignment.centerRight, child: close),
          titles,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: titles),
        const SizedBox(width: AppSpacing.s8),
        close,
      ],
    );
  }
}

/// One answer: an icon tile, a title and a line of explanation on a card that
/// is at least 64 high and grows with large text. The first answer is drawn
/// with the green tint and border of the main action.
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.subtitle,
    required this.leading,
    required this.onTap,
    super.key,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final Widget leading;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: BorderSide(
        color: highlighted ? colors.primary : colors.borderDecorative,
        width: highlighted ? 1.5 : 1,
      ),
    );
    return Semantics(
      container: true,
      button: true,
      label: '$title, $subtitle',
      onTap: onTap,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Material(
          color: highlighted ? colors.primaryTint : colors.surface,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            customBorder: shape,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: <Widget>[
                  leading,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: AppTextStyles.bodyStrong.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: AppTextStyles.captionDefault.copyWith(
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
        ),
      ),
    );
  }
}

/// The icon tile of an answer that is not a workout: the neutral tint of the
/// secondary text colour (Figma: `text-secondary` at 14 %).
class _NeutralTile extends StatelessWidget {
  const _NeutralTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Icon(icon, size: 22, color: colors.textSecondary),
      ),
    );
  }
}
