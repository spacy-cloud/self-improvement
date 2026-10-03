import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/router/navigation.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/features/modules/application/module_toggle_controller.dart';
import 'package:self_improvement/features/modules/presentation/module_toggle_list.dart';

/// Shown instead of a screen whose module is switched off. It names the module,
/// says that the data is kept and offers "Modul aktivieren" (the screen
/// replaces itself with the real one once the module is on) and a way to the
/// module manager, so a stale link or an old stack entry is never a dead end.
class ModuleDisabledScreen extends ConsumerWidget {
  const ModuleDisabledScreen({required this.module, super.key});

  final SelfImprovementModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref
        .watch(moduleToggleControllerProvider)
        .contains(module.id);
    return AppScaffold.subpage(
      title: module.title,
      onBack: () => leaveOrHome(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          EmptyState(
            title: '${module.title} ist ausgeschaltet',
            message:
                'Dieser Bereich gehört zum Modul „${module.title}“. Schalte '
                'es wieder ein, um ihn zu nutzen. Deine Daten bleiben '
                'erhalten.',
            actionLabel: 'Modul aktivieren',
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
