import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_form_controller.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/features/nutrition/domain/water_input.dart';
import 'package:self_improvement/features/nutrition/domain/water_validation.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/number_format.dart';

/// Key of the editable amount field (tests and focus handling).
const Key waterAmountFieldKey = ValueKey<String>('water-amount-field');

/// The fields of a water entry: the amount with minus and plus, the time and
/// the note. Used by the "Eigene Menge" sheet and by the edit screen; the
/// state lives in [waterFormProvider] for [args].
class WaterFormBody extends ConsumerStatefulWidget {
  const WaterFormBody({
    required this.args,
    required this.onSubmit,
    this.framed = false,
    this.inlineFailure = false,
    super.key,
  });

  final WaterFormArgs args;

  /// Called when the keyboard action is pressed or "Erneut versuchen" is tapped.
  final VoidCallback onSubmit;

  /// Draws the amount inside a card with the error border (screen) instead of
  /// directly on the surface (sheet).
  final bool framed;

  /// Shows a failed save inside the form (a sheet covers the snack bar).
  final bool inlineFailure;

  @override
  ConsumerState<WaterFormBody> createState() => _WaterFormBodyState();
}

class _WaterFormBodyState extends ConsumerState<WaterFormBody> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  final FocusNode _amountFocus = FocusNode();

  WaterFormArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(waterFormProvider(_args));
    _amount = TextEditingController(text: initial.amountText);
    _note = TextEditingController(text: initial.note);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  WaterFormController get _controller =>
      ref.read(waterFormProvider(_args).notifier);

  Future<void> _pickMoment() async {
    final state = ref.read(waterFormProvider(_args));
    final picked = await pickMoment(
      context,
      date: state.date,
      time: state.time,
      today: ref.read(todayProvider),
      dateHelp: 'Datum der Trinkmenge',
      timeHelp: 'Uhrzeit der Trinkmenge',
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller
      ..setDate(picked.date)
      ..setTime(picked.time);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(waterFormProvider(_args));
    ref.listen(waterFormProvider(_args).select((s) => s.amountText), (
      previous,
      next,
    ) {
      if (_amount.text != next) {
        _amount.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final colors = context.tokens.colors;
    final today = ref.watch(todayProvider);
    final amountError = state.fieldErrors[WaterFields.amount];
    final typed = switch (parseWaterMl(state.amountText)) {
      WaterMlParsed(:final ml) => ml,
      WaterMlInvalid() => null,
    };
    final failure = state.submitFailure;

    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuantityStepper(
          valueText: state.amountText,
          expand: true,
          onIncrease: typed != null && typed >= maxWaterEntryMl
              ? null
              : () => _controller.step(1),
          onDecrease: typed != null && typed <= minWaterEntryMl
              ? null
              : () => _controller.step(-1),
          increaseLabel: 'um $waterAmountStepMl Milliliter erhöhen',
          decreaseLabel: 'um $waterAmountStepMl Milliliter verringern',
          valueWidget: NumberDisplayField(
            fieldKey: waterAmountFieldKey,
            controller: _amount,
            focusNode: _amountFocus,
            semanticLabel: 'Menge in Millilitern',
            unit: 'ml',
            hint: '$waterAmountStartMl',
            hasError: amountError != null,
            onChanged: _controller.setAmountText,
            onSubmitted: (_) => widget.onSubmit(),
          ),
        ),
        const SizedBox(height: 8),
        if (amountError != null)
          Align(child: NutritionFieldError(text: amountError))
        else
          Text(
            'In $waterAmountStepMl-ml-Schritten · $minWaterEntryMl bis '
            '${formatThousands(maxWaterEntryMl)} ml',
            textAlign: TextAlign.center,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.framed)
          AppCard(
            borderColor: amountError == null ? null : colors.error,
            borderWidth: amountError == null ? 1 : 2,
            child: amount,
          )
        else
          amount,
        const SizedBox(height: 16),
        AppListGroup(
          children: [
            EntryListTile.chevron(
              title: 'Zeitpunkt',
              subtitle:
                  '${formatRelativeDay(state.date, today)}, '
                  '${state.time.toIso()} Uhr',
              icon: AppIcon.clock.data,
              accent: AppAccent.water,
              onTap: _pickMoment,
            ),
          ],
        ),
        if (state.fieldErrors[WaterFields.occurredAt] != null) ...[
          const SizedBox(height: 8),
          NutritionFieldError(text: state.fieldErrors[WaterFields.occurredAt]!),
        ],
        const SizedBox(height: 16),
        AppTextField(
          label: 'Notiz',
          requirementLabel: 'optional',
          controller: _note,
          hint: 'Zum Beispiel: nach dem Training',
          maxLength: maxNutritionNoteLength,
          minLines: 1,
          maxLines: 3,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          errorText: state.fieldErrors[WaterFields.note],
          onChanged: _controller.setNote,
        ),
        FieldErrorAnnouncer(text: state.fieldErrors[WaterFields.note]),
        if (widget.inlineFailure && failure != null) ...[
          const SizedBox(height: 12),
          SubmitFailureNotice(
            message: failure is ConflictFailure
                ? failure.userMessage
                : 'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: failure is ConflictFailure ? null : widget.onSubmit,
          ),
        ],
      ],
    );
  }
}
