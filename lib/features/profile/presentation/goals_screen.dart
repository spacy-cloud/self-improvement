import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_input.dart';
import 'package:self_improvement/features/profile/application/goals_form_controller.dart';
import 'package:self_improvement/features/profile/application/profile_providers.dart';
import 'package:self_improvement/features/profile/domain/goal_editor.dart';
import 'package:self_improvement/features/profile/domain/profile_formatting.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/profile/presentation/profile_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';

/// "Ziele" (Figma `4043:2`): daily goals and the weekly workout goal, saved
/// through the versioned goal contract and valid from tomorrow, and the target
/// weight, which is a profile value and valid at once. The notice at the top
/// and the group titles say so.
///
/// Deviations from the frame: every quantitative daily goal has its own switch
/// (the specification requires goals to be switchable off), the weekly workout
/// goal moves out of "gelten sofort" because the versioned contract applies it
/// from tomorrow, and values are typed or stepped as plain numbers.
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  /// What the editor opened with. Later emissions of the streams never reset
  /// the open form.
  GoalsFormArgs? _opened;

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(goalEditorModelProvider);
    final profile = ref.watch(profileProvider);
    final modules = ref.watch(moduleStatusesProvider);
    final entries = ref.watch(weightEntriesProvider);
    final modelValue = model.value;
    final profileValue = profile.value;
    final moduleMap = modules.value;
    if (_opened == null &&
        modelValue != null &&
        profileValue != null &&
        moduleMap != null) {
      final bodyVisible = moduleMap[ModuleId.body] ?? true;
      // The latest measurement is only a proposal; wait for it so the form
      // does not change after it opened.
      if (!bodyVisible || entries.hasValue || entries.hasError) {
        _opened = GoalsFormArgs(
          model: modelValue,
          bodyVisible: bodyVisible,
          targetWeightGrams: profileValue.targetWeightGrams,
          startWeightGrams: profileValue.startWeightGrams,
          latestWeightGrams: bodyVisible
              ? ref.read(currentWeightGramsProvider)
              : null,
        );
      }
    }
    final opened = _opened;
    if (opened != null) {
      return _GoalsForm(key: const ValueKey('goals-form'), args: opened);
    }
    final failed =
        model.hasError ||
        profile.hasError ||
        modules.hasError ||
        (profile.hasValue && profileValue == null);
    return AppScaffold.subpage(
      title: 'Ziele',
      onBack: () => leaveScreen(context, fallback: ProfileRoutes.profile),
      body: failed
          ? ErrorState(
              onRetry: () {
                ref
                  ..invalidate(profileProvider)
                  ..invalidate(moduleStatusesProvider)
                  ..invalidate(goalVersionsProvider)
                  ..invalidate(weightEntriesProvider);
              },
            )
          : const SizedBox(height: 120),
    );
  }
}

class _GoalsForm extends ConsumerStatefulWidget {
  const _GoalsForm({required this.args, super.key});

  final GoalsFormArgs args;

  @override
  ConsumerState<_GoalsForm> createState() => _GoalsFormState();
}

class _GoalsFormState extends ConsumerState<_GoalsForm> {
  final Map<GoalType, FocusNode> _focus = {
    for (final type in GoalType.values) type: FocusNode(),
  };
  final FocusNode _targetFocus = FocusNode();

  GoalsFormArgs get _args => widget.args;

  GoalsFormController get _controller =>
      ref.read(goalsFormProvider(_args).notifier);

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    _targetFocus.dispose();
    super.dispose();
  }

  void _focusFirstError(Map<String, String> errors) {
    for (final type in goalDisplayOrder) {
      if (errors.containsKey(type.key)) {
        _focus[type]!.requestFocus();
        return;
      }
    }
    if (errors.containsKey(ProfileFields.targetWeight)) {
      _targetFocus.requestFocus();
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final result = await _controller.submit();
    if (!mounted) {
      return;
    }
    switch (result) {
      case GoalsSaved():
        feedback.showSaved(result.message);
        closeScreen(context, fallback: ProfileRoutes.profile);
      case GoalsUnchanged():
        closeScreen(context, fallback: ProfileRoutes.profile);
      case GoalsRejected(:final goalsSaved):
        final state = ref.read(goalsFormProvider(_args));
        if (state.fieldErrors.isNotEmpty) {
          _focusFirstError(state.fieldErrors);
          return;
        }
        final failure = state.submitFailure;
        if (failure == null) {
          return;
        }
        final saved = goalsSaved
            ? 'Die Tagesziele sind gespeichert, das Zielgewicht nicht. '
            : 'Speichern fehlgeschlagen. ';
        feedback.showError(
          failure is StorageFailure
              ? '${saved}Deine Eingaben bleiben erhalten.'
              : failure.userMessage,
          onRetry: () => fireAndForget(_submit),
        );
    }
  }

  Future<void> _askToDiscard() async {
    final discard = await confirmDiscardChanges(context);
    if (discard && mounted) {
      closeScreen(context, fallback: ProfileRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(goalsFormProvider(_args));
    final tomorrow = ref.watch(todayProvider).addDays(1);
    final model = _args.model;
    final errors = state.fieldErrors;
    final canSubmit = !state.submitting && state.dirty;

    Widget goalRow(GoalType type) {
      final row = model.rowOf(type);
      final draft = state.drafts[type]!;
      if (type.isSwitch) {
        return _SwitchGoalRow(
          spec: goalEditorSpec(type),
          row: row,
          enabled: draft.enabled,
          onChanged: (value) => _controller.setEnabled(type, enabled: value),
        );
      }
      return _ValueGoalRow(
        spec: goalEditorSpec(type),
        row: row,
        draft: draft,
        error: errors[type.key],
        focusNode: _focus[type]!,
        onEnabled: type == GoalType.workoutWeekly
            ? null
            : (value) => _controller.setEnabled(type, enabled: value),
        onText: (text) => _controller.setText(type, text),
        onStep: (direction) => _controller.step(type, direction),
      );
    }

    final dailyRows = [
      for (final type in goalDisplayOrder)
        if (type.isDaily && model.rowOf(type).visible) goalRow(type),
    ];
    final hasHabits = model.rowOf(GoalType.taskCompletion).visible;
    final workoutsVisible = model.rowOf(GoalType.workoutWeekly).visible;
    final hiddenCount = model.hiddenRows.length;

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          fireAndForget(_askToDiscard);
        }
      },
      child: AppScaffold.subpage(
        title: 'Ziele',
        onBack: () => leaveScreen(context, fallback: ProfileRoutes.profile),
        primaryAction: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty) ...[
              const LiveFieldError(text: 'Bitte prüfe die markierten Angaben.'),
              const SizedBox(height: 8),
            ],
            PrimaryButton(
              label: 'Ziele speichern',
              onPressed: canSubmit ? () => fireAndForget(_submit) : null,
              loading: state.submitting,
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InfoNotice(
              text:
                  'Änderungen an Tageszielen und am Wochenziel gelten ab '
                  'morgen (${formatDateShort(tomorrow)}), damit dein '
                  'heutiger Fortschritt fair bleibt.',
            ),
            if (dailyRows.isNotEmpty) ...[
              const SizedBox(height: 12),
              const AppSectionHeader.group(title: 'Tagesziele · ab morgen'),
              const SizedBox(height: 8),
              AppListGroup(children: dailyRows),
            ],
            if (hasHabits) ...[
              const SizedBox(height: 8),
              _Note(
                text: 'Jede aktive Gewohnheit zählt automatisch als Tagesziel.',
              ),
            ],
            if (workoutsVisible) ...[
              const SizedBox(height: 12),
              const AppSectionHeader.group(title: 'Wochenziel · ab morgen'),
              const SizedBox(height: 8),
              AppListGroup(children: [goalRow(GoalType.workoutWeekly)]),
            ],
            if (_args.bodyVisible) ...[
              const SizedBox(height: 12),
              const AppSectionHeader.group(title: 'Körperziel · gilt sofort'),
              const SizedBox(height: 8),
              AppListGroup(
                children: [
                  _TargetWeightRow(
                    text: state.targetWeightText,
                    startGrams: _args.startWeightGrams,
                    acceptedStartGrams: state.acceptedStartGrams,
                    proposal: state.proposal?.grams,
                    error: errors[ProfileFields.targetWeight],
                    focusNode: _targetFocus,
                    canStep:
                        parseWeightKg(state.targetWeightText)
                            is WeightKgParsed ||
                        _args.startWeightGrams != null ||
                        _args.latestWeightGrams != null,
                    onText: _controller.setTargetWeightText,
                    onStep: _controller.stepTargetWeight,
                    onAcceptProposal: _controller.acceptStartWeightProposal,
                    onSubmitted: (_) {
                      if (canSubmit) {
                        fireAndForget(_submit);
                      }
                    },
                  ),
                ],
              ),
            ],
            if (hiddenCount > 0) ...[
              const SizedBox(height: 12),
              _Note(
                text:
                    'Ziele von ausgeschalteten Modulen sind ausgeblendet und '
                    'bleiben gespeichert.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        text,
        style: AppTextStyles.captionDefault.copyWith(
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// The two lines of a goal: title and caption, plus what applies today while
/// a change saved earlier is still waiting for tomorrow.
class _GoalTexts extends StatelessWidget {
  const _GoalTexts({required this.spec, required this.row});

  final GoalEditorSpec spec;
  final GoalEditorRow row;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final today = row.hasPendingChange
        ? 'Heute noch: ${goalSummaryText(spec.type, target: row.today.target, enabled: row.today.enabled)}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spec.title,
          style: AppTextStyles.bodyDefault.copyWith(color: colors.textPrimary),
        ),
        Text(
          spec.caption,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (today != null)
          Text(
            today,
            style: AppTextStyles.captionStrong.copyWith(
              color: colors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// Goal without a value: a switch for "weight entry" and "task completion".
/// The whole row switches; screen readers get one toggle.
class _SwitchGoalRow extends StatelessWidget {
  const _SwitchGoalRow({
    required this.spec,
    required this.row,
    required this.enabled,
    required this.onChanged,
  });

  final GoalEditorSpec spec;
  final GoalEditorRow row;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final today = row.hasPendingChange
        ? ' · Heute noch: ${goalSummaryText(spec.type, target: row.today.target, enabled: row.today.enabled)}'
        : '';
    return EntryListTile.toggle(
      title: spec.title,
      subtitle: '${spec.caption}$today',
      value: enabled,
      onToggle: onChanged,
    );
  }
}

/// Goal with a value: title and (optional) switch on top, the value with plus
/// and minus below. A switched-off goal keeps its value and shows that it does
/// not count.
class _ValueGoalRow extends StatelessWidget {
  const _ValueGoalRow({
    required this.spec,
    required this.row,
    required this.draft,
    required this.error,
    required this.focusNode,
    required this.onEnabled,
    required this.onText,
    required this.onStep,
  });

  final GoalEditorSpec spec;
  final GoalEditorRow row;
  final GoalDraft draft;
  final String? error;
  final FocusNode focusNode;

  /// `null` for goals that cannot be switched off (weekly workouts).
  final ValueChanged<bool>? onEnabled;
  final ValueChanged<String> onText;
  final void Function(int direction) onStep;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final type = spec.type;
    final parsed = parseGoalText(type, draft.text);
    final value = parsed is GoalTextValid ? parsed.value : null;
    final atMinimum = value != null && value <= type.minTarget;
    final atMaximum = value != null && value >= type.maxTarget;
    final amount = spec.stepAmount;
    final stepText = type == GoalType.water
        ? '$amount Milliliter'
        : type == GoalType.focusMinutes
        ? '$amount Minuten'
        : '$amount';
    final enabled = draft.enabled;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _GoalTexts(spec: spec, row: row),
              ),
              if (onEnabled != null) ...[
                const SizedBox(width: 12),
                AppSwitch(
                  value: enabled,
                  onChanged: onEnabled,
                  semanticLabel: '${spec.title}-Ziel',
                ),
              ],
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 4),
            QuantityStepper(
              valueText: draft.text,
              expand: true,
              onDecrease: atMinimum ? null : () => onStep(-1),
              onIncrease: atMaximum ? null : () => onStep(1),
              decreaseLabel: '${spec.title} um $stepText verringern',
              increaseLabel: '${spec.title} um $stepText erhöhen',
              valueWidget: _ValueField(
                text: draft.text,
                unit: spec.unit,
                semanticLabel: spec.inputLabel,
                focusNode: focusNode,
                hasError: error != null,
                formatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(
                    type.maxTarget.toString().length,
                  ),
                ],
                keyboardType: TextInputType.number,
                onChanged: onText,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Align(child: LiveFieldError(text: error!)),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Ausgeschaltet: zählt nicht für den Tagesring.',
              style: AppTextStyles.captionStrong.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The target weight of the profile: value in kilograms with plus and minus,
/// the start weight as context and the proposal of the latest measurement.
class _TargetWeightRow extends StatelessWidget {
  const _TargetWeightRow({
    required this.text,
    required this.startGrams,
    required this.acceptedStartGrams,
    required this.proposal,
    required this.error,
    required this.focusNode,
    required this.canStep,
    required this.onText,
    required this.onStep,
    required this.onAcceptProposal,
    required this.onSubmitted,
  });

  final String text;
  final int? startGrams;
  final int? acceptedStartGrams;
  final int? proposal;
  final String? error;
  final FocusNode focusNode;
  final bool canStep;
  final ValueChanged<String> onText;
  final void Function(int direction) onStep;
  final VoidCallback onAcceptProposal;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final start = startGrams ?? acceptedStartGrams;
    final empty = text.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Zielgewicht',
            style: AppTextStyles.bodyDefault.copyWith(
              color: colors.textPrimary,
            ),
          ),
          Text(
            start == null
                ? 'Startgewicht nicht gesetzt. Leer lassen für kein Ziel.'
                : 'Startgewicht ${formatWeightKg(start)}',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          QuantityStepper(
            valueText: text,
            expand: true,
            onDecrease: canStep ? () => onStep(-1) : null,
            onIncrease: canStep ? () => onStep(1) : null,
            decreaseLabel: 'Zielgewicht um 0,1 Kilogramm verringern',
            increaseLabel: 'Zielgewicht um 0,1 Kilogramm erhöhen',
            valueWidget: _ValueField(
              text: text,
              unit: 'kg',
              semanticLabel: empty
                  ? 'Zielgewicht in Kilogramm, nicht gesetzt'
                  : 'Zielgewicht in Kilogramm',
              hint: '–',
              focusNode: focusNode,
              hasError: error != null,
              formatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                LengthLimitingTextInputFormatter(6),
              ],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: onText,
              onSubmitted: onSubmitted,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Align(child: LiveFieldError(text: error!)),
          ],
          if (proposal != null && acceptedStartGrams == null) ...[
            const SizedBox(height: 10),
            Text(
              'Deine letzte Messung ist ${formatWeightKg(proposal!)}. '
              'Möchtest du sie als Startgewicht übernehmen?',
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Als Startgewicht übernehmen',
              onPressed: onAcceptProposal,
            ),
          ] else if (acceptedStartGrams != null) ...[
            const SizedBox(height: 10),
            Text(
              'Startgewicht ${formatWeightKg(acceptedStartGrams!)} wird mit '
              'dem Zielgewicht gespeichert.',
              style: AppTextStyles.captionStrong.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The editable value in the middle of a stepper. It owns its text controller
/// and takes over the text of the form whenever the form changes it (plus and
/// minus), so typing keeps its cursor.
class _ValueField extends StatefulWidget {
  const _ValueField({
    required this.text,
    required this.unit,
    required this.semanticLabel,
    required this.focusNode,
    required this.hasError,
    required this.formatters,
    required this.keyboardType,
    required this.onChanged,
    this.hint,
    this.onSubmitted,
  });

  final String text;
  final String unit;
  final String semanticLabel;
  final String? hint;
  final FocusNode focusNode;
  final bool hasError;
  final List<TextInputFormatter> formatters;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_ValueField> createState() => _ValueFieldState();
}

class _ValueFieldState extends State<_ValueField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(_ValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final style = AppTextStyles.titleSection.copyWith(
      color: widget.hasError ? colors.error : colors.textPrimary,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        IntrinsicWidth(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64),
            child: Semantics(
              label: widget.semanticLabel,
              textField: true,
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                textAlign: TextAlign.center,
                style: style,
                cursorColor: colors.primaryButton,
                keyboardType: widget.keyboardType,
                textInputAction: TextInputAction.done,
                inputFormatters: widget.formatters,
                decoration: InputDecoration(
                  isDense: true,
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.touchMin,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  hintText: widget.hint,
                  hintStyle: style.copyWith(color: colors.textTertiary),
                ),
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
              ),
            ),
          ),
        ),
        if (widget.unit.isNotEmpty) ...[
          const SizedBox(width: 4),
          ExcludeSemantics(
            child: Text(
              widget.unit,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
