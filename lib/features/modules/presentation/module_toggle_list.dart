import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';
import 'package:self_improvement/features/modules/application/module_toggle_controller.dart';
import 'package:self_improvement/features/modules/domain/module_presentation.dart';

/// The route that resolves a blocked deactivation, if the module has one.
/// Only the focus module can block (its open session is resolved on the
/// session screen: save or discard there).
String? resolveRouteFor(ModuleId module) =>
    module == ModuleId.focus ? NotificationRoutes.focusSession : null;

/// Switches [module] on or off and tells the user what happened: success only
/// after the commit, a blocked deactivation with the resolution action, a
/// failed save with a retry. Used by the module manager and by the plus menu's
/// "no module" state.
Future<void> toggleModule(
  BuildContext context,
  WidgetRef ref,
  SelfImprovementModule module, {
  required bool enabled,
}) async {
  final feedback = ref.read(feedbackServiceProvider);
  final result = await ref
      .read(moduleToggleControllerProvider.notifier)
      .setEnabled(module.id, enabled: enabled);
  switch (result) {
    case ModuleToggled():
      feedback.showSaved(
        enabled
            ? '${module.title} eingeschaltet.'
            : '${module.title} ausgeschaltet. Deine Daten bleiben erhalten.',
      );
    case ModuleToggleBlocked(:final check):
      if (!context.mounted) {
        return;
      }
      final resolve = await showConfirmationSheet(
        context,
        title: 'Ausschalten nicht möglich',
        message: check.message,
        confirmLabel: check.resolveLabel,
        destructive: false,
      );
      final route = resolveRouteFor(module.id);
      if (resolve && route != null && context.mounted) {
        unawaited(context.push<void>(route));
      }
    case ModuleToggleFailed(:final failure):
      feedback.showError(
        failure.userMessage,
        onRetry: () {
          if (context.mounted) {
            unawaited(toggleModule(context, ref, module, enabled: enabled));
          }
        },
      );
    case ModuleToggleBusy():
      break;
  }
}

/// Switches every module that is off back on and reports a failure.
Future<void> enableAllModules(BuildContext context, WidgetRef ref) async {
  final feedback = ref.read(feedbackServiceProvider);
  final results = await ref
      .read(moduleToggleControllerProvider.notifier)
      .enableAll();
  final failed = results.whereType<ModuleToggleFailed>().firstOrNull;
  if (failed != null) {
    feedback.showError(
      failed.failure.userMessage,
      onRetry: () {
        if (context.mounted) {
          unawaited(enableAllModules(context, ref));
        }
      },
    );
  } else if (results.isNotEmpty) {
    feedback.showSaved('Alle Module eingeschaltet.');
  }
}

/// One toggle row per module in a grouped card (Figma "Module verwalten").
/// Off modules say that their data is kept. A toggle is locked while its
/// change is running.
class ModuleToggleList extends ConsumerWidget {
  const ModuleToggleList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(appModulesProvider);
    final statuses =
        ref.watch(moduleStatusesProvider).value ?? const <ModuleId, bool>{};
    final pending = ref.watch(moduleToggleControllerProvider);
    return AppListGroup(
      children: <Widget>[
        for (final module in modules)
          EntryListTile.toggle(
            key: ValueKey<String>('module-toggle-${module.id.key}'),
            title: module.title,
            subtitle: (statuses[module.id] ?? true)
                ? module.description
                : 'Ausgeschaltet. Deine Daten bleiben erhalten.',
            icon: module.icon,
            accent: managerAccentFor(module.id),
            value: statuses[module.id] ?? true,
            onToggle: pending.contains(module.id)
                ? null
                : (enabled) => unawaited(
                    toggleModule(context, ref, module, enabled: enabled),
                  ),
          ),
      ],
    );
  }
}
