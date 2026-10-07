import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:self_improvement/core/design/icons/app_icons.dart';
import 'package:self_improvement/core/design/tokens/app_radii.dart';
import 'package:self_improvement/core/design/tokens/app_text_styles.dart';
import 'package:self_improvement/core/design/tokens/app_tokens.dart';

/// Closes the keyboard when a pointer goes down outside the text field that
/// has the focus. Every text input of the app passes it as `onTapOutside`
/// ([AppTextField] does it itself).
///
/// Flutter does nothing here on a touch screen: Android closes the keyboard
/// with the Back gesture, but iOS has no such gesture and its number pad has
/// no Return key, so without this a form on an iPhone keeps the keyboard open
/// (BS-112, D-018). The callback unfocuses on every platform and for every
/// pointer kind.
///
/// Why it does not get in the way:
///
/// - It only looks at the pointer going down and takes no part in the gesture
///   arena, so a button under the finger still gets its tap, the first time.
/// - A tap on another text field is not "outside": all text fields share one
///   tap region group. Moving from field to field never hides the keyboard on
///   the way. A control that should count as part of a field (a row that
///   focuses its field when tapped) is wrapped in a [TextFieldTapRegion].
/// - It only runs for the field that has the focus, so it never steals the
///   focus from anything else.
void dismissKeyboardOnTapOutside(PointerDownEvent event) {
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Text field with a permanent label above the box (never a floating label),
/// an optional requirement hint ("Pflichtfeld", "optional") on the right and
/// the error text directly below the field.
///
/// Border: 1.5 px input grey, 2 px button green when focused, 2 px error red
/// with an error text and icon (never colour only). Put the unit into the
/// label ("Gewicht in kg") or into [suffixText]. Label, hint and error are
/// read together with the field by screen readers.
///
/// A tap outside the field closes the keyboard ([dismissKeyboardOnTapOutside]).
class AppTextField extends StatelessWidget {
  /// Creates a text field.
  const AppTextField({
    required this.label,
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.requirementLabel,
    this.helperText,
    this.errorText,
    this.suffixText,
    this.keyboardType,
    this.numeric = false,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
  });

  /// Permanent label, for example "Gewicht in kg".
  final String label;

  /// Text controller.
  final TextEditingController? controller;

  /// Focus node.
  final FocusNode? focusNode;

  /// Placeholder inside the field.
  final String? hint;

  /// Small text right of the label, for example "Pflichtfeld".
  final String? requirementLabel;

  /// Help text below the field (hidden while [errorText] is shown).
  final String? helperText;

  /// Error text below the field; also switches the border to the error style.
  final String? errorText;

  /// Unit or suffix inside the field.
  final String? suffixText;

  /// Keyboard type (ignored when [numeric] is true).
  final TextInputType? keyboardType;

  /// Shows the numeric keyboard with decimal separator and only accepts digits
  /// and a decimal separator (comma or dot) unless [inputFormatters] is set.
  final bool numeric;

  /// Keyboard action button.
  final TextInputAction? textInputAction;

  /// Capitalisation behaviour.
  final TextCapitalization textCapitalization;

  /// Input formatters (override the numeric default).
  final List<TextInputFormatter>? inputFormatters;

  /// Called on every change.
  final ValueChanged<String>? onChanged;

  /// Called when the keyboard action is pressed.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field accepts input.
  final bool enabled;

  /// Whether the field is read only.
  final bool readOnly;

  /// Whether the field takes the initial focus.
  final bool autofocus;

  /// Maximum length (the counter is not shown).
  final int? maxLength;

  /// Maximum number of lines.
  final int? maxLines;

  /// Minimum number of lines.
  final int? minLines;

  /// Text alignment inside the field.
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final effectiveKeyboard = numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : keyboardType;
    final effectiveFormatters =
        inputFormatters ??
        (numeric
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
              ]
            : null);

    final labelRow = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
          ),
        ),
        if (requirementLabel != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            requirementLabel!,
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );

    final errorBorder = OutlineInputBorder(
      borderRadius: AppRadii.controlBorder,
      borderSide: BorderSide(color: colors.error, width: 2),
    );

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      keyboardType: effectiveKeyboard,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: effectiveFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTapOutside: dismissKeyboardOnTapOutside,
      maxLength: maxLength,
      maxLines: maxLines,
      minLines: minLines,
      textAlign: textAlign,
      style: AppTextStyles.bodyDefault.copyWith(color: colors.textPrimary),
      cursorColor: colors.primaryButton,
      buildCounter: (
        context, {
        required currentLength,
        required isFocused,
        required maxLength,
      }) => null,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffixText,
        suffixStyle: AppTextStyles.bodyDefault.copyWith(
          color: colors.textSecondary,
        ),
        border: hasError ? errorBorder : null,
        enabledBorder: hasError ? errorBorder : null,
        focusedBorder: hasError ? errorBorder : null,
        disabledBorder: hasError ? errorBorder : null,
      ),
    );

    final feedback = hasError
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    AppIcon.error.data,
                    size: 14,
                    color: colors.error,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errorText!,
                    style: AppTextStyles.captionStrong.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
          )
        : (helperText != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    helperText!,
                    style: AppTextStyles.captionDefault.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                )
              : null);

    // Not a MergeSemantics: merging a label, a text field and a unit suffix
    // makes the framework assert inside scrolling forms. The label names the
    // field itself; the helper text or the error is its hint, so the visible
    // feedback row stays out of the semantics tree (nothing is read twice).
    final semanticLabel = requirementLabel == null
        ? label
        : '$label, $requirementLabel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(child: labelRow),
        const SizedBox(height: 6),
        Semantics(
          label: semanticLabel,
          hint: hasError ? errorText : helperText,
          child: field,
        ),
        if (feedback != null) ExcludeSemantics(child: feedback),
      ],
    );
  }
}
