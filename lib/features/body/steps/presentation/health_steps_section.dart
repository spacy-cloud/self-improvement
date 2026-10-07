import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_actions.dart';
import 'package:self_improvement/features/body/steps/application/health_steps_controller.dart';
import 'package:self_improvement/features/body/steps/domain/health_steps_status.dart';
import 'package:self_improvement/features/body/steps/presentation/health_explanation_sheet.dart';
import 'package:self_improvement/features/body/steps/presentation/health_notice_card.dart';
import 'package:self_improvement/features/body/steps/presentation/health_steps_labels.dart';

/// The group "Schritte" of the settings (design frame `4122:314`): the switch
/// "Schritte aus Health übernehmen" with the honest state of the comparison
/// and, when the values of Health do not arrive, the notice with its way out.
///
/// Self-contained like the reminders block: the settings screen embeds it and
/// the steps feature owns the whole flow. The switch is off by default; when it
/// goes on, the explanation appears first and only then the system dialog.
/// The group is not shown on a device without a health interface and not while
/// the module "Gewicht & Körper" is off.
class HealthStepsSection extends ConsumerStatefulWidget {
  const HealthStepsSection({super.key});

  @override
  ConsumerState<HealthStepsSection> createState() => _HealthStepsSectionState();
}

class _HealthStepsSectionState extends ConsumerState<HealthStepsSection> {
  /// A change is running (switch or notice): the controls are disabled so a
  /// second tap cannot start a second change.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // What the device says about the interface decides whether the group is
    // shown at all. With the switch off nothing asks the device before this.
    unawaited(
      Future<void>.microtask(
        () => ref.read(healthStepsControllerProvider.notifier).ensureStatus(),
      ),
    );
  }

  Future<void> _onToggle(bool turnOn) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final actions = ref.read(healthStepsActionsProvider);
      if (turnOn) {
        final status = ref.read(healthStepsStatusProvider);
        final proceed = await showHealthExplanationSheet(
          context,
          sourceName: status.sourceName,
          availability: status.availability,
        );
        if (!proceed || !mounted) {
          return;
        }
        await actions.enable();
      } else {
        await actions.disable();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _onNotice(HealthNoticeAction action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(healthStepsActionsProvider).perform(action);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(healthStepsStatusProvider);
    if (!status.visible) {
      return const SizedBox.shrink();
    }
    final clock = ref.watch(clockProvider);
    final notice = HealthNotice.of(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const AppSectionHeader.group(title: 'Schritte'),
        const SizedBox(height: 8),
        AppListGroup(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                EntryListTile.toggle(
                  title: 'Schritte aus Health übernehmen',
                  subtitle: healthSettingsSubtitle(status, clock),
                  // At very large text the title needs the width of the icon
                  // tile, or it would break inside the word.
                  icon: MediaQuery.textScalerOf(context).scale(1) > 1.5
                      ? null
                      : AppIcon.heart.data,
                  accent: AppAccent.steps,
                  value: status.enabled,
                  onToggle: _busy
                      ? null
                      : (value) => unawaited(_onToggle(value)),
                ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: HealthNoticeCard(
                      notice: notice,
                      busy: _busy || status.syncing,
                      onAction: (action) => unawaited(_onNotice(action)),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
