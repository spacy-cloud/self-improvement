import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_controller.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_navigation.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';
import 'package:self_improvement/features/onboarding/presentation/steps/body_step.dart';
import 'package:self_improvement/features/onboarding/presentation/steps/daily_goals_step.dart';
import 'package:self_improvement/features/onboarding/presentation/steps/goals_step.dart';
import 'package:self_improvement/features/onboarding/presentation/steps/modules_step.dart';
import 'package:self_improvement/features/onboarding/presentation/steps/welcome_step.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/onboarding_top_bar.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_page.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/step_progress.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/submit_error_banner.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/text_action_button.dart';

/// The first-start flow: a welcome screen and four numbered steps (goals,
/// modules, body data, daily goals), registered once as the route
/// `/onboarding`. The steps are internal: this widget switches between them and
/// no further global routes exist.
///
/// * Nothing is stored before the end. "Fertig" and "Überspringen" run ONE
///   atomic command; the profile counts as onboarded only after its commit.
///   Then the flow leaves for the dashboard (see [onboardingExitProvider]).
/// * A failed save keeps the flow open with all input, an error and a retry.
/// * Android back goes to the previous step. On the first screen it leaves the
///   app like on any root screen of Android; when something was already typed
///   it asks first, because the unsaved input would be lost.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  OnboardingController get _controller =>
      ref.read(onboardingControllerProvider.notifier);

  void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  void _next() {
    _unfocus();
    _controller.next();
  }

  void _back() {
    _unfocus();
    _controller.back();
  }

  /// Runs finish, skip or retry and leaves for the dashboard once the command
  /// committed. On failure the controller state shows the banner.
  Future<void> _complete(
    Future<OnboardingSubmitResult> Function() action,
  ) async {
    _unfocus();
    final result = await action();
    if (!mounted || result is! OnboardingCompleted) {
      return;
    }
    ref.read(onboardingExitProvider)(context);
  }

  Future<void> _skip() async {
    final state = ref.read(onboardingControllerProvider);
    if (state.busy) {
      return;
    }
    if (state.hasUserInput) {
      final confirmed = await showConfirmationSheet(
        context,
        title: 'Einrichtung überspringen?',
        message:
            'Deine bisherigen Eingaben werden nicht gespeichert. Es gelten '
            'die Standardwerte: alle Bereiche und die vorgeschlagenen Ziele.',
        confirmLabel: 'Überspringen',
        cancelLabel: 'Weiter einrichten',
        destructive: false,
      );
      if (!confirmed || !mounted) {
        return;
      }
    }
    await _complete(_controller.skip);
  }

  /// Android back (button or gesture), after [PopScope] held it back.
  Future<void> _onSystemBack() async {
    final state = ref.read(onboardingControllerProvider);
    if (state.busy) {
      return;
    }
    if (!state.step.isFirst) {
      _back();
      return;
    }
    // Only reached when something was typed: ask before the input is lost.
    final leave = await showConfirmationSheet(
      context,
      title: 'Einrichtung abbrechen?',
      message:
          'Deine Eingaben sind noch nicht gespeichert. Beim nächsten Start '
          'beginnt die Einrichtung von vorn.',
      confirmLabel: 'App schließen',
      cancelLabel: 'Weiter einrichten',
    );
    if (leave) {
      await SystemNavigator.pop();
    }
  }

  static String _failureMessage(
    AppFailure failure,
    OnboardingSubmitKind? kind,
  ) {
    if (failure is StorageFailure) {
      return kind == OnboardingSubmitKind.skip
          ? 'Die Einrichtung konnte nicht gespeichert werden. Bitte versuche '
                'es erneut.'
          : 'Die Einrichtung konnte nicht gespeichert werden. Deine Eingaben '
                'bleiben erhalten.';
    }
    return failure.userMessage;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final tokens = context.tokens;
    final colors = tokens.colors;
    final motion = AppMotion.of(context);
    final step = state.step;
    final busy = state.busy;
    final failure = state.submitFailure;
    final overlay = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: tokens.isDark
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: tokens.isDark ? Brightness.dark : Brightness.light,
    );
    final margin = onboardingPageMargin(context);

    return PopScope(
      canPop: step.isFirst && !state.hasUserInput && !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_onSystemBack());
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: colors.surface,
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: step.isFirst ? 1 : 0,
                  duration: motion.standard,
                  curve: motion.curve,
                  child: const HeroBackdrop(),
                ),
              ),
              SafeArea(
                child: MaxContentWidth(
                  child: Column(
                    children: <Widget>[
                      if (step.number case final number?)
                        OnboardingTopBar(
                          current: number,
                          total: OnboardingStep.numberedStepCount,
                          onBack: busy ? null : _back,
                          onSkip: busy ? null : () => unawaited(_skip()),
                        ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: motion.standard,
                          switchInCurve: motion.curve,
                          switchOutCurve: motion.curve,
                          transitionBuilder: (child, animation) {
                            // A short push in the direction of travel, 6 % of
                            // the width, together with the fade.
                            final incoming =
                                child.key == ValueKey<OnboardingStep>(step);
                            final sign =
                                (state.movedBackward ? -1.0 : 1.0) *
                                (incoming ? 1.0 : -1.0);
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(0.06 * sign, 0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey<OnboardingStep>(step),
                            child: switch (step) {
                              OnboardingStep.welcome => const WelcomeStep(),
                              OnboardingStep.goals => const GoalsStep(),
                              OnboardingStep.modules => const ModulesStep(),
                              OnboardingStep.body => const BodyStep(),
                              OnboardingStep.dailyGoals =>
                                const DailyGoalsStep(),
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          margin,
                          AppSpacing.s8,
                          margin,
                          AppSpacing.s16,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (failure != null) ...<Widget>[
                              SubmitErrorBanner(
                                message: _failureMessage(
                                  failure,
                                  state.failedSubmit,
                                ),
                                onRetry: busy
                                    ? null
                                    : () => unawaited(
                                        _complete(_controller.retry),
                                      ),
                              ),
                              const SizedBox(height: AppSpacing.s12),
                            ],
                            if (step.isFirst) ...<Widget>[
                              const PageDots(),
                              const SizedBox(height: AppSpacing.s16),
                            ],
                            PrimaryButton(
                              label: switch (step) {
                                OnboardingStep.welcome => 'Los geht’s',
                                OnboardingStep.dailyGoals =>
                                  'Fertig – los geht’s',
                                _ => 'Weiter',
                              },
                              loading: state.submitting,
                              onPressed: busy
                                  ? null
                                  : (step.isLast
                                        ? () => unawaited(
                                            _complete(_controller.finish),
                                          )
                                        : _next),
                            ),
                            if (step.isFirst)
                              Center(
                                child: TextActionButton(
                                  label: 'Überspringen',
                                  hint:
                                      'Schließt die Einrichtung mit '
                                      'Standardwerten ab',
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(_skip()),
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
          ),
        ),
      ),
    );
  }
}
