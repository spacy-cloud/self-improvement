import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/module_toggle_controller.dart';
import 'package:self_improvement/features/modules/presentation/module_toggle_list.dart';

/// Gates a core tab whose content belongs to a module.
///
/// The tab stays a navigation target (spec: the Habits tab is a core
/// destination), but while its module is switched off it shows
/// [ModuleDisabledTab] instead of the content: no data, no write action, and
/// the one way back, "<label> aktivieren". The data is untouched. While the
/// module statuses are not known yet the content is shown (the app reads them
/// before the first frame, so this is only a safety net).
class ModuleTabGate extends ConsumerWidget {
  const ModuleTabGate({
    required this.module,
    required this.tabTitle,
    required this.activateLabel,
    required this.child,
    super.key,
  });

  /// The module the tab belongs to.
  final SelfImprovementModule module;

  /// Title of the tab page (the same as the real tab shows).
  final String tabTitle;

  /// Name of the area in the activation action, e.g.
  /// "Aufgaben und Gewohnheiten" gives "Aufgaben und Gewohnheiten aktivieren".
  final String activateLabel;

  /// The real tab content.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(moduleStatusesProvider).value?[module.id] ?? true;
    if (enabled) {
      return child;
    }
    return ModuleDisabledTab(
      module: module,
      tabTitle: tabTitle,
      activateLabel: activateLabel,
    );
  }
}

/// The off state of a gated tab (see [ModuleTabGate]).
class ModuleDisabledTab extends ConsumerWidget {
  const ModuleDisabledTab({
    required this.module,
    required this.tabTitle,
    required this.activateLabel,
    super.key,
  });

  final SelfImprovementModule module;
  final String tabTitle;
  final String activateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref
        .watch(moduleToggleControllerProvider)
        .contains(module.id);
    return AppScaffold(
      title: tabTitle,
      safeAreaBottom: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          EmptyState(
            title: '$activateLabel sind ausgeschaltet',
            message:
                'Deine Einträge bleiben erhalten. Schalte den Bereich wieder '
                'ein, um sie zu sehen und weiterzuführen.',
            actionLabel: '$activateLabel aktivieren',
            onAction: pending
                ? null
                : () => unawaited(
                    toggleModule(context, ref, module, enabled: true),
                  ),
            icon: AppIcon.modules,
          ),
          const SizedBox(height: AppSpacing.s12),
          SecondaryButton(
            label: 'Module verwalten',
            onPressed: () => unawaited(context.push<void>(AppRoutes.modules)),
          ),
        ],
      ),
    );
  }
}
