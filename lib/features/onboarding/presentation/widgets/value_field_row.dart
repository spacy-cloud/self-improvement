import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/presentation/widgets/field_error_text.dart';

/// A voluntary personal value in the look of the design: a muted card with the
/// label on the left and the typed value, big and bold, on the right.
///
/// The card turns green while the field has focus (thicker border and tint) and
/// red with an error text and icon below when [errorText] is set, so no state
/// is carried by colour alone. Tapping anywhere on the card focuses the field.
///
/// With [stacked] set, with large text or in a narrow column the label sits
/// above the value instead of beside it, so nothing clips. Screen readers hear
/// [semanticLabel] ("Alter in Jahren, optional") on the text field and the
/// error as a live region; the visible label and unit are not read twice.
class ValueFieldRow extends StatelessWidget {
  const ValueFieldRow({
    required this.label,
    required this.semanticLabel,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    super.key,
    this.unit,
    this.hint = 'optional',
    this.errorText,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.onSubmitted,
    this.stacked = false,
    this.valueStyle,
  });

  /// Visible label ("Alter").
  final String label;

  /// Spoken name of the field including the unit and "optional".
  final String semanticLabel;

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  /// Unit behind the value ("Jahre", "cm", "kg"); shown once a value is typed.
  final String? unit;

  /// Shown while the field is empty.
  final String hint;

  /// German hint below the card; also switches the border to the error style.
  final String? errorText;

  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onSubmitted;

  /// Always put the label above the value (for the free text name).
  final bool stacked;

  /// Text style of the typed value; the bold section title by default.
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final motion = AppMotion.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final error = errorText;
    final hasError = error != null && error.isNotEmpty;
    final style = (valueStyle ?? AppTextStyles.titleSection).copyWith(
      color: colors.textPrimary,
    );
    final labelText = ExcludeSemantics(
      child: Text(
        label,
        style: AppTextStyles.bodyDefault.copyWith(color: colors.textPrimary),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListenableBuilder(
          listenable: Listenable.merge(<Listenable>[focusNode, controller]),
          builder: (context, _) {
            final focused = focusNode.hasFocus;
            final hasText = controller.text.isNotEmpty;
            final unitText = unit;
            final unitWidget = unitText != null && hasText
                ? Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: ExcludeSemantics(
                      child: Text(
                        unitText,
                        style: AppTextStyles.captionDefault.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : null;
            final field = Semantics(
              label: semanticLabel,
              textField: true,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                keyboardType: keyboardType,
                inputFormatters: inputFormatters,
                textInputAction: textInputAction,
                textCapitalization: textCapitalization,
                textAlign: stacked ? TextAlign.start : TextAlign.end,
                style: style,
                cursorColor: colors.primaryButton,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: style.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w400,
                    fontSize: AppTextStyles.bodyDefault.fontSize,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            );
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: focusNode.requestFocus,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: motion.curve,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: focused && !hasError
                      ? colors.primaryTint
                      : colors.surfaceMuted,
                  borderRadius: AppRadii.cardBorder,
                  border: Border.all(
                    color: hasError
                        ? colors.error
                        : (focused
                              ? colors.primaryButton
                              : colors.borderDecorative),
                    width: hasError || focused ? 2 : 1,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        stacked || constraints.maxWidth < 240 * scale;
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: labelText,
                          ),
                          Row(
                            children: <Widget>[
                              Expanded(child: field),
                              ?unitWidget,
                            ],
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(flex: 5, child: labelText),
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          flex: 4,
                          child: Row(
                            children: <Widget>[
                              Expanded(child: field),
                              ?unitWidget,
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (hasError) FieldErrorText(text: error),
      ],
    );
  }
}
