import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/nutrition/application/water_form_controller.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';

/// Opens the "Eigene Menge" sheet of the water screen: an amount of 50 to
/// 2000 ml with time and note, saved as one real entry.
Future<void> showWaterCustomSheet(BuildContext context) =>
    showFormSheet<void>(context, builder: (_) => const WaterCustomSheet());

/// The "Eigene Menge" form (Figma 4055:25): amount stepper, time, note and the
/// button that names the amount ("330 ml hinzufügen").
class WaterCustomSheet extends ConsumerStatefulWidget {
  const WaterCustomSheet({super.key});

  @override
  ConsumerState<WaterCustomSheet> createState() => _WaterCustomSheetState();
}

class _WaterCustomSheetState extends ConsumerState<WaterCustomSheet> {
  static const WaterFormArgs _args = WaterFormArgs.create();

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final navigator = Navigator.of(context);
    final result = await ref.read(waterFormProvider(_args).notifier).submit();
    switch (result) {
      case WaterSaved():
        navigator.pop();
        feedback.showSaved(result.message, undo: result.outcome.undo);
      case WaterRejected():
        break; // Field errors and failures are shown inside the form.
    }
  }

  Future<void> _close() async {
    final navigator = Navigator.of(context);
    if (!ref.read(waterFormProvider(_args)).dirty) {
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
    final state = ref.watch(waterFormProvider(_args));
    final typed = switch (parseWaterMl(state.amountText)) {
      WaterMlParsed(:final ml) => ml,
      WaterMlInvalid() => null,
    };
    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_close());
        }
      },
      child: FormSheetFrame(
        title: 'Eigene Menge',
        onClose: _close,
        action: PrimaryButton(
          label: typed == null
              ? 'Menge hinzufügen'
              : '${formatWaterMl(typed)} hinzufügen',
          loading: state.submitting,
          onPressed: state.submitting ? null : _submit,
        ),
        child: WaterFormBody(
          args: _args,
          onSubmit: _submit,
          inlineFailure: true,
        ),
      ),
    );
  }
}
