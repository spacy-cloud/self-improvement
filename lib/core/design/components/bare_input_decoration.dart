import 'package:flutter/material.dart';

/// Decoration for an input that is drawn without any box of its own, for
/// example the big value of a quantity stepper or a value inside a card that
/// already has a border.
///
/// The app theme draws outlines for every enabled, focused and error state, so
/// `InputDecoration.collapsed` alone would still show a frame; this switches
/// all of them off. [contentPadding] enlarges the tappable and spoken area
/// (a field must stay at least 48 logical pixels high).
InputDecoration bareInputDecoration({
  String? hintText,
  TextStyle? hintStyle,
  EdgeInsetsGeometry contentPadding = EdgeInsets.zero,
}) {
  return InputDecoration(
    isCollapsed: true,
    filled: false,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    contentPadding: contentPadding,
    hintText: hintText,
    hintStyle: hintStyle,
  );
}
