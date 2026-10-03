import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/nutrition/application/water_goal_controller.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/features/nutrition/presentation/water_labels.dart';

/// Key of the editable target field.
const Key waterGoalFieldKey = ValueKey<String>('water-goal-field');

/// Opens the sheet that changes the daily water target (250 to 10000 ml in
/// 50 ml steps). A change applies from tomorrow.
Future<void> showWaterGoalSheet(
  BuildContext context,
  WaterGoalSettings settings,
) => showFormSheet<void>(
  context,
  builder: (_) => WaterGoalSheet(settings: settings),
);

/// The goal form: stepper in 50 ml steps, the explicit hint that the change
/// applies from tomorrow (today keeps its frozen threshold) and the save
/// button.
class WaterGoalSheet extends ConsumerStatefulWidget {
  const WaterGoalSheet({required this.settings, super.key});

  final WaterGoalSettings settings;

  @override
  ConsumerState<WaterGoalSheet> createState() => _WaterGoalSheetState();
}

class _WaterGoalSheetState extends ConsumerState<WaterGoalSheet> {
  late final TextEditingController _target;
  final FocusNode _focus = FocusNode();

  int get _initial => widget.settings.tomorrowTargetMl;

  @override
  void initState() {
    super.initState();
    _target = TextEditingController(
      text: ref.read(waterGoalControllerProvider(_initial)).targetText,
    );
  }

  @override
  void dispose() {
    _target.dispose();
    _focus.dispose();
    super.dispose();
  }

  WaterGoalController get _controller =>
      ref.read(waterGoalControllerProvider(_initial).notifier);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final navigator = Navigator.of(context);
    final result = await _controller.submit();
    switch (result) {
      case WaterGoalSaved():
        navigator.pop();
        feedback.showSaved(result.message, undo: result.outcome.undo);
      case WaterGoalRejected():
        // The sheet shows the reason and keeps the input; the invalid field
        // takes the focus, so a screen reader reads its label with the hint.
        if (mounted &&
            ref.read(waterGoalControllerProvider(_initial)).fieldError !=
                null) {
          _focus.requestFocus();
        }
    }
  }

  Future<void> _close() async {
    final navigator = Navigator.of(context);
    if (!ref.read(waterGoalControllerProvider(_initial)).dirty) {
      navigator.pop();
      return;
    }
    final discard = await confirmDiscard(context);
    if (discard && mounted) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(waterGoalControllerProvider(_initial));
    ref.listen(
      waterGoalControllerProvider(_initial).select((s) => s.targetText),
      (previous, next) {
        if (_target.text != next) {
          _target.value = TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          );
        }
      },
    );
    final colors = context.tokens.colors;
    final typed = switch (parseWaterGoalMl(state.targetText)) {
      WaterGoalParsed(:final ml) => ml,
      WaterGoalInvalid() => null,
    };
    final failure = state.submitFailure;
    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_close());
        }
      },
      child: FormSheetFrame(
        title: 'Tagesziel ändern',
        onClose: _close,
        action: PrimaryButton(
          label: 'Tagesziel speichern',
          loading: state.submitting,
          onPressed: state.submitting ? null : _submit,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            QuantityStepper(
              valueText: state.targetText,
              expand: true,
              onIncrease: typed != null && typed >= maxWaterGoalMl
                  ? null
                  : () => _controller.step(1),
              onDecrease: typed != null && typed <= minWaterGoalMl
                  ? null
                  : () => _controller.step(-1),
              increaseLabel: 'um $waterGoalStepMl Milliliter erhöhen',
              decreaseLabel: 'um $waterGoalStepMl Milliliter verringern',
              valueWidget: NumberDisplayField(
                fieldKey: waterGoalFieldKey,
                controller: _target,
                focusNode: _focus,
                semanticLabel: 'Tagesziel in Millilitern',
                unit: 'ml',
                hint: '$defaultWaterGoalMl',
                hasError: state.fieldError != null,
                onChanged: _controller.setTargetText,
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ),
            const SizedBox(height: 8),
            if (state.fieldError != null)
              Align(child: NutritionFieldError(text: state.fieldError!))
            else
              Text(
                waterGoalRangeHint(),
                textAlign: TextAlign.center,
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            const SizedBox(height: 12),
            MergeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      AppIcon.info.data,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      waterGoalApplyHint(widget.settings),
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: 12),
              SubmitFailureNotice(
                message: failure is ConflictFailure
                    ? failure.userMessage
                    : 'Speichern fehlgeschlagen. Deine Eingabe bleibt '
                          'erhalten.',
                onRetry: failure is ConflictFailure ? null : _submit,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
