import 'dart:async';

import 'package:flutter/material.dart';
import 'package:self_improvement/core/design/design.dart';

/// Neutral loading state: empty for a short moment (so quick loads do not
/// flash), then a small progress indicator with a spoken label. It never
/// shows invented content and stops when the content arrives.
class NeutralLoading extends StatefulWidget {
  const NeutralLoading({
    super.key,
    this.delay = const Duration(milliseconds: 300),
    this.label = 'Wird geladen',
  });

  /// How long the area stays empty before the indicator appears.
  final Duration delay;

  /// Spoken label of the indicator.
  final String label;

  @override
  State<NeutralLoading> createState() => _NeutralLoadingState();
}

class _NeutralLoadingState extends State<NeutralLoading> {
  Timer? _timer;
  bool _visible = false;

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
    final colors = context.tokens.colors;
    return Center(
      child: _visible
          ? Semantics(
              liveRegion: true,
              label: widget.label,
              child: SizedBox.square(
                dimension: AppSizes.touchMin,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colors.primaryButton,
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
