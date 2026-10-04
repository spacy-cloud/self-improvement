import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_session_controller.dart';
import 'package:self_improvement/features/focus/application/focus_setup_controller.dart';
import 'package:self_improvement/features/focus/application/focus_ui_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_session_tile.dart';
import 'package:self_improvement/features/focus/presentation/focus_timer_widgets.dart';
import 'package:self_improvement/features/focus/presentation/focus_widgets.dart';

/// "Fokus": choose a category and a duration and start, or - while a session
/// is open - resume it instead of starting a second one. Below: today's focus
/// time and the sessions completed today.
class FocusStartScreen extends ConsumerWidget {
  const FocusStartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(focusSessionProvider);
    return AppScaffold.subpage(
      title: 'Fokus',
      onBack: () => leaveFocusScreen(context),
      body: open.when(
        loading: () => const ScreenLoading(),
        error: (error, stack) =>
            ErrorState(onRetry: () => ref.invalidate(focusSessionProvider)),
        data: (session) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (session == null)
              const _SetupCard()
            else
              _ResumeCard(session: session),
            const SizedBox(height: 12),
            const _TodayCard(),
            const SizedBox(height: 12),
            const _TodaySessions(),
          ],
        ),
      ),
    );
  }
}

/// Duration dial, category chips and the start button.
class _SetupCard extends ConsumerStatefulWidget {
  const _SetupCard();

  @override
  ConsumerState<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends ConsumerState<_SetupCard> {
  FocusSetupController get _controller => ref.read(focusSetupProvider.notifier);

  Future<void> _start() async {
    if (!mounted) {
      return;
    }
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.start();
    switch (result) {
      case FocusActionDone():
        unawaited(router.push<void>(FocusRoutes.session));
      case FocusActionFailed(:final failure):
        if (failure is ValidationFailure) {
          return; // The dial shows the message.
        }
        if (failure is ConflictFailure) {
          // A session is already open; the card switches to "resume" itself.
          feedback.showInfo(failure.userMessage);
          return;
        }
        feedback.showError(
          'Starten fehlgeschlagen. Deine Auswahl bleibt erhalten.',
          onRetry: () => unawaited(_start()),
        );
      case FocusActionIgnored():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(focusSetupProvider);
    final plannedError = setup.fieldErrors[FocusFields.planned];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DurationDial(
            minutes: setup.plannedMinutes,
            onDecrease: setup.canStepDown && !setup.submitting
                ? () => _controller.stepPlannedMinutes(-1)
                : null,
            onIncrease: setup.canStepUp && !setup.submitting
                ? () => _controller.stepPlannedMinutes(1)
                : null,
          ),
          if (plannedError != null) ...[
            const SizedBox(height: 8),
            Align(child: InlineMessage(text: plannedError)),
          ],
          const SizedBox(height: 16),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Kategorie',
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in FocusCategory.values)
                  AppChoiceChip(
                    label: category.label,
                    selected: setup.category == category,
                    onSelected: setup.submitting
                        ? null
                        : (_) => _controller.selectCategory(category),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Fokus starten',
            icon: Icons.play_arrow_rounded,
            loading: setup.submitting,
            loadingLabel: 'Wird gestartet …',
            onPressed: () => unawaited(_start()),
          ),
        ],
      ),
    );
  }
}

/// The planned time in a ring with minus and plus (steps of five minutes,
/// 5 to 180). Next to the ring where there is room; below it on narrow screens
/// and large text, where the buttons would squeeze the ring.
class _DurationDial extends StatelessWidget {
  const _DurationDial({
    required this.minutes,
    required this.onDecrease,
    required this.onIncrease,
  });

  final int minutes;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  static const double _ringSize = 148;
  static const double _buttons = 2 * 48 + 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.6,
    );
    final tint = Color.alphaBlend(
      colors.moduleFocus.withValues(alpha: 0.3),
      colors.surface,
    );
    final ring = FocusRing(
      value: 1,
      color: tint,
      trackColor: tint,
      size: _ringSize,
      strokeWidth: 12,
      semanticLabel: '',
      center: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatCountdown(minutes * 60),
            style: AppTextStyles.displayL.copyWith(color: colors.textPrimary),
          ),
          Text(
            minutes < 60 ? 'Minuten' : '$minutes Minuten',
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    const increaseLabel = 'Dauer um 5 Minuten erhöhen';
    const decreaseLabel = 'Dauer um 5 Minuten verringern';
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= _ringSize * scale + _buttons;
        if (sideBySide) {
          return QuantityStepper(
            valueText: formatCountdown(minutes * 60),
            expand: true,
            onIncrease: onIncrease,
            onDecrease: onDecrease,
            increaseLabel: increaseLabel,
            decreaseLabel: decreaseLabel,
            valueWidget: Semantics(
              container: true,
              liveRegion: true,
              label: 'Dauer: ${plannedMinutesSpoken(minutes)}',
              excludeSemantics: true,
              child: ring,
            ),
          );
        }
        return Column(
          children: [
            ExcludeSemantics(child: ring),
            const SizedBox(height: 8),
            QuantityStepper(
              valueText: '$minutes',
              unit: 'Min.',
              valueSemanticLabel: 'Dauer: ${plannedMinutesSpoken(minutes)}',
              valueStyle: AppTextStyles.titleScreen,
              expand: true,
              onIncrease: onIncrease,
              onDecrease: onDecrease,
              increaseLabel: increaseLabel,
              decreaseLabel: decreaseLabel,
            ),
          ],
        );
      },
    );
  }
}

/// Shown instead of the setup while a session is open: there is never a second
/// one, only the way back to it.
class _ResumeCard extends ConsumerWidget {
  const _ResumeCard({required this.session});

  final FocusSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final minutes = ref.watch(focusRemainingMinutesProvider);
    final status = session.status;
    final remaining = switch (status) {
      FocusStatus.running =>
        minutes == null
            ? session.plannedSeconds - session.accumulatedSeconds
            : minutes * 60,
      FocusStatus.paused => session.plannedSeconds - session.accumulatedSeconds,
      _ => 0,
    };
    final title = switch (status) {
      FocusStatus.running => 'Eine Sitzung läuft',
      FocusStatus.paused => 'Eine Sitzung ist pausiert',
      _ => 'Eine Sitzung wartet auf deine Bestätigung',
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            child: FocusStatusPill(status: status, category: session.category),
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleSection.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            focusOpenCardSubtitle(
              status: status,
              category: session.category,
              remainingSeconds: remaining,
            ),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Es kann immer nur eine Sitzung gleichzeitig offen sein.',
            textAlign: TextAlign.center,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: status == FocusStatus.awaitingConfirmation
                ? 'Sitzung bestätigen'
                : 'Sitzung fortsetzen',
            icon: Icons.play_arrow_rounded,
            onPressed: () => context.push(FocusRoutes.session),
          ),
        ],
      ),
    );
  }
}

/// "Heute": the saved focus time against the daily goal.
class _TodayCard extends ConsumerWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    return ref
        .watch(focusTodaySummaryProvider)
        .when(
          loading: () => const AppCard(child: ScreenLoading()),
          error: (error, stack) => ErrorState(
            onRetry: () {
              ref
                ..invalidate(focusSessionsTodayProvider)
                ..invalidate(goalVersionsProvider);
            },
          ),
          data: (summary) {
            final goal = summary.goalMinutes;
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            'Heute',
                            style: AppTextStyles.titleSection.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text.rich(
                          textAlign: TextAlign.end,
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${summary.completedMinutes}',
                                style: AppTextStyles.titleScreen.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: goal == null ? ' Min.' : ' / $goal Min.',
                                style: AppTextStyles.bodyRegular.copyWith(
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (goal != null) ...[
                    const SizedBox(height: 10),
                    AppProgressBar(
                      value: summary.goalFraction ?? 0,
                      variant: AppProgressVariant.focus,
                      semanticLabel: focusTodaySpoken(summary),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    focusTodayCaption(summary),
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}

/// "Sitzungen heute" with the way to the whole history.
class _TodaySessions extends ConsumerWidget {
  const _TodaySessions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final sessions = ref.watch(focusSessionsTodayProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          title: 'Sitzungen heute',
          actionLabel: 'Verlauf',
          actionSemanticLabel: 'Fokus-Verlauf anzeigen',
          onAction: () => context.push(FocusRoutes.history),
        ),
        const SizedBox(height: 8),
        sessions.when(
          loading: () => const ScreenLoading(),
          error: (error, stack) => ErrorState(
            onRetry: () => ref.invalidate(focusSessionsTodayProvider),
          ),
          data: (entries) => entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    'Noch keine abgeschlossene Sitzung heute.',
                    style: AppTextStyles.bodyRegular.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              : AppListGroup(
                  children: [
                    for (final FocusHistoryEntry entry in entries)
                      FocusSessionTile(entry: entry),
                  ],
                ),
        ),
      ],
    );
  }
}
