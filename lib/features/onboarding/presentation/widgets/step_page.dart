import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Horizontal page margin of the onboarding: 24 like the design, 16 on very
/// narrow screens.
double onboardingPageMargin(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 360 ? AppSpacing.s24 : AppSpacing.s16;

/// The scrolling body of one step: a single column that scrolls when the
/// content (large text, keyboard) does not fit.
class StepPage extends StatelessWidget {
  const StepPage({
    required this.children,
    super.key,
    this.topPadding = AppSpacing.s16,
  });

  final List<Widget> children;

  /// Space above the first child.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    final margin = onboardingPageMargin(context);
    return SingleChildScrollView(
      // The two pages of a step change must not share the primary controller.
      primary: false,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(margin, topPadding, margin, AppSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
