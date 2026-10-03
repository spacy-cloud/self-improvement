import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/shell/plus_entries.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/modules/application/module_providers.dart';
import 'package:self_improvement/features/modules/domain/module_presentation.dart';
import 'package:self_improvement/features/modules/presentation/module_toggle_list.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';

/// Opens the plus menu as a modal sheet over the current tab and returns the
/// route the user picked, or `null` when it was closed (close button, scrim
/// or Android back). The sheet floats [bottomInset] above the screen edge so
/// the navigation bar with its plus button stays visible below it (Figma
/// `2037:18`).
Future<String?> showPlusSheet(
  BuildContext context, {
  required double bottomInset,
}) {
  final colors = context.tokens.colors;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: colors.scrim,
    barrierLabel: 'Schließen',
    constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + AppSpacing.s8),
      child: PlusSheet(
        onClose: () => Navigator.of(sheetContext).pop(),
        onSelected: (route) => Navigator.of(sheetContext).pop(route),
      ),
    ),
  );
}

/// Content of the plus menu: up to eight entries of the active modules in a
/// two-column grid (one column at large text), its own close button, and the
/// module choice when no entry is available (every module off), so the user is
/// never stuck.
class PlusSheet extends ConsumerWidget {
  const PlusSheet({required this.onClose, required this.onSelected, super.key});

  final VoidCallback onClose;

  /// Called with the route of the chosen entry; the caller closes the sheet.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final modules = ref.watch(appModulesProvider);
    final statuses = ref.watch(moduleStatusesProvider).value;
    final focusOpen = ref.watch(openFocusSessionProvider).value ?? false;
    final entries = statuses == null
        ? const <PlusEntry>[]
        : resolvePlusEntries(
            modules: modules,
            statuses: statuses,
            focusSessionOpen: focusOpen,
            labelOf: (action) => action.dynamicLabel?.call(ref) ?? action.label,
          );
    final allOff = statuses != null && allModulesOff(statuses);

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Was möchtest du eintragen?',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppRadii.sheet + 8),
          border: Border.all(color: colors.borderDecorative),
          boxShadow: AppShadows.card(colors.shadow),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            10,
            AppSpacing.s16,
            AppSpacing.s16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: AppSizes.sheetHandleWidth,
                    height: AppSizes.sheetHandleHeight,
                    decoration: BoxDecoration(
                      color: colors.borderInput,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              _Header(onClose: onClose),
              const SizedBox(height: AppSpacing.s16),
              if (statuses == null)
                const SizedBox(height: 96, child: NeutralLoading())
              else if (entries.isEmpty)
                _NoEntries(allOff: allOff, onSelected: onSelected)
              else
                AdaptiveGrid(
                  minCellWidth: 150,
                  children: <Widget>[
                    for (final entry in entries)
                      _PlusTile(
                        key: ValueKey<String>('plus-entry-${entry.id}'),
                        entry: entry,
                        onTap: () => onSelected(entry.route),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final close = AppIconButton(
      icon: AppIcon.close.data,
      semanticLabel: 'Schließen',
      filled: true,
      onPressed: onClose,
    );
    final titles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ExcludeSemantics(
          child: Text(
            'DEIN TAG. DEIN FORTSCHRITT',
            style: AppTextStyles.captionStrong.copyWith(
              color: colors.primaryText,
              letterSpacing: 0.66,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          header: true,
          container: true,
          child: Text(
            'Was möchtest du eintragen?',
            style: AppTextStyles.titleScreen.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
    // Large text: the close button gets its own row so the title can use the
    // full width instead of breaking inside words.
    if (scale > AppSizes.stackTextScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(alignment: Alignment.centerRight, child: close),
          titles,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: titles),
        const SizedBox(width: AppSpacing.s8),
        close,
      ],
    );
  }
}

class _PlusTile extends StatelessWidget {
  const _PlusTile({required this.entry, required this.onTap, super.key});

  final PlusEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      onTap: onTap,
      semanticLabel: entry.label,
      padding: const EdgeInsets.all(10),
      showShadow: false,
      borderColor: colors.borderDecorative,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: <Widget>[
            AppIconTile(
              icon: entry.icon,
              accent: entry.accent,
              size: 40,
              iconSize: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.label,
                style: AppTextStyles.bodyStrong.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No entry available: either every module is off (the module choice follows
/// right here) or the active modules offer nothing to enter.
class _NoEntries extends ConsumerWidget {
  const _NoEntries({required this.allOff, required this.onSelected});

  final bool allOff;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          allOff
              ? 'Alle Module sind ausgeschaltet. Schalte ein Modul ein, um '
                    'Einträge zu erfassen. Deine Daten bleiben erhalten.'
              : 'Mit den aktiven Modulen gibt es gerade nichts zu erfassen. '
                    'Schalte weitere Module ein.',
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s12),
        const ModuleToggleList(),
        const SizedBox(height: AppSpacing.s12),
        SecondaryButton(
          label: 'Module verwalten',
          onPressed: () => onSelected(AppRoutes.modules),
        ),
      ],
    );
  }
}
