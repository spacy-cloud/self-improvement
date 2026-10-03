import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_countdown.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/presentation/focus_labels.dart';

/// Pill with the state of the open session ("Läuft · Lernen", "Pausiert ·
/// Lernen", "Geschafft!"). The state is told by text AND icon, never by colour
/// alone, and the pill is a live region: a change of state (paused, resumed,
/// time over) is announced once. The countdown itself is NOT announced, so
/// screen reader users hear nothing every second.
class FocusStatusPill extends StatelessWidget {
  const FocusStatusPill({
    required this.status,
    required this.category,
    super.key,
  });

  final FocusStatus status;
  final FocusCategory category;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final paused = status == FocusStatus.paused;
    final background = paused ? colors.warningTint : colors.primaryTint;
    final foreground = paused ? colors.warningText : colors.primaryText;
    final icon = status == FocusStatus.awaitingConfirmation
        ? Icons.check_rounded
        : Icons.circle;
    final text = focusStatusText(status, category);
    return Semantics(
      container: true,
      liveRegion: true,
      label: text,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: icon == Icons.circle ? 8 : 14,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyStrong.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ring that never grows wider than its parent: the design system ring grows
/// with the text size, so the size is reduced here until the grown ring fits
/// the available width. The content inside is scaled down by the ring itself.
class FocusRing extends StatelessWidget {
  const FocusRing({
    required this.value,
    required this.color,
    required this.center,
    required this.semanticLabel,
    super.key,
    this.size = 236,
    this.strokeWidth = 16,
    this.trackColor,
  });

  /// Progress from 0 to 1.
  final double value;
  final Color color;
  final Color? trackColor;

  /// Content in the middle (visual only; [semanticLabel] speaks for it).
  final Widget center;
  final String semanticLabel;

  /// Diameter at normal text size when there is room.
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
      1.0,
      1.6,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.hasBoundedWidth
            ? constraints.maxWidth / scale
            : size;
        return ProgressRing(
          value: value,
          semanticLabel: semanticLabel,
          size: math.min(size, room),
          strokeWidth: strokeWidth,
          color: color,
          trackColor: trackColor,
          center: center,
        );
      },
    );
  }
}

/// The ring of the running, paused and awaiting states with its time texts.
///
/// The arc shows the elapsed share of the planned time; while the session
/// waits for confirmation it is full and green.
class FocusTimerRing extends StatelessWidget {
  const FocusTimerRing({required this.countdown, super.key, this.pausedFor});

  final FocusCountdown countdown;

  /// How long a paused session has been paused (text of the paused state).
  final Duration? pausedFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final status = countdown.status;
    final category = countdown.session.category;
    final awaiting = status == FocusStatus.awaitingConfirmation;
    final paused = status == FocusStatus.paused;
    final ringColor = awaiting
        ? colors.primaryButton
        : paused
        ? colors.textTertiary
        : colors.moduleFocus;
    final pausedText = pausedSinceText(pausedFor ?? Duration.zero);
    final secondary = AppTextStyles.bodyRegular.copyWith(
      color: colors.textSecondary,
    );
    final time = AppTextStyles.displayXl.copyWith(color: colors.textPrimary);
    final center = awaiting
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    AppIcon.check.data,
                    size: 20,
                    color: colors.primaryText,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(countdown.plannedText, style: time),
              Text('${category.label} abgeschlossen', style: secondary),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(countdown.remainingText, style: time),
              Text(
                paused
                    ? pausedText
                    : 'verbleibend von ${countdown.plannedText}',
                style: secondary,
              ),
            ],
          );
    return FocusRing(
      value: awaiting ? 1 : countdown.progress,
      color: ringColor,
      center: center,
      semanticLabel: focusRingSpoken(
        status: status,
        category: category,
        remainingSeconds: countdown.remainingSeconds,
        plannedSeconds: countdown.plannedSeconds,
        pausedText: paused ? pausedText : null,
      ),
    );
  }
}

/// Rebuilds [builder] about every fifteen seconds with the time the session has
/// been paused. Display only (wall clock, minute granularity); nothing is
/// persisted and the timer stops with the widget.
class PausedForBuilder extends ConsumerStatefulWidget {
  const PausedForBuilder({
    required this.pausedAtUtc,
    required this.builder,
    super.key,
  });

  final DateTime pausedAtUtc;
  final Widget Function(BuildContext context, Duration pausedFor) builder;

  @override
  ConsumerState<PausedForBuilder> createState() => _PausedForBuilderState();
}

class _PausedForBuilderState extends ConsumerState<PausedForBuilder> {
  Timer? _timer;
  late Duration _pausedFor;

  Duration _compute() =>
      ref.read(clockProvider).nowUtc().difference(widget.pausedAtUtc);

  @override
  void initState() {
    super.initState();
    _pausedFor = _compute();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      final next = _compute();
      if (next.inMinutes != _pausedFor.inMinutes && mounted) {
        setState(() => _pausedFor = next);
      }
    });
  }

  @override
  void didUpdateWidget(PausedForBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pausedAtUtc != widget.pausedAtUtc) {
      _pausedFor = _compute();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _pausedFor);
}
