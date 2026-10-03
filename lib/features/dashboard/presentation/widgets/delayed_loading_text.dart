import 'dart:async';

import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Neutral loading hint: a still line of text that appears only when loading
/// takes longer than a moment, so a fast database read never flashes it.
///
/// No spinner and no animation: nothing here loops. It is announced to screen
/// readers when it appears.
class DelayedLoadingText extends StatefulWidget {
  /// Creates the hint.
  const DelayedLoadingText({
    super.key,
    this.text = 'Daten werden geladen …',
    this.delay = const Duration(milliseconds: 300),
  });

  /// The German hint.
  final String text;

  /// How long loading may take before the hint appears.
  final Duration delay;

  @override
  State<DelayedLoadingText> createState() => _DelayedLoadingTextState();
}

class _DelayedLoadingTextState extends State<DelayedLoadingText> {
  Timer? _timer;
  var _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) {
        setState(() => _visible = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) {
      return const SizedBox.shrink();
    }
    final colors = context.tokens.colors;
    return Semantics(
      container: true,
      liveRegion: true,
      label: widget.text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s24),
        child: Center(
          child: Text(
            widget.text,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
