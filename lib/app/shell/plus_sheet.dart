import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/app/shell/plus_entries.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
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

/// Content of the plus menu: up to eight entries in a two-column grid (one
/// column at large text), its own close button, and a way forward when no entry
/// is available, so the user is never stuck.
///
/// An entry is offered when its module is on (BS-53) and, if it belongs to a
/// goal of "Meine Ziele", when that goal is on (BS-117). Both follow the data
/// live, without a restart. When goals hid entries, a hint says where to change
/// that; when they hid every entry, the empty state leads to "Meine Ziele".
/// When no module offers anything (every module off) the module choice follows.
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
    final goalVersions = ref.watch(goalVersionsProvider);
    final today = ref.watch(todayProvider);
    // The menu waits for the goals like it waits for the module states, so no
    // entry shows up that is hidden a moment later. A failed read of the goals
    // must not leave the user without a menu: then the goals filter nothing.
    final activeGoals = goalVersions.hasValue
        ? activeGoalTypes(goalVersions.requireValue, today)
        : null;
    final goalsReady = goalVersions.hasValue || goalVersions.hasError;
    final candidates = statuses == null || !goalsReady
        ? const <PlusEntry>[]
        : resolvePlusEntries(
            modules: modules,
            statuses: statuses,
            focusSessionOpen: focusOpen,
            labelOf: (action) => action.dynamicLabel?.call(ref) ?? action.label,
          );
    final entries = activeGoals == null
        ? candidates
        : filterPlusEntriesByGoals(candidates, activeGoals);
    final hiddenByGoals = candidates.length - entries.length;
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
              if (statuses == null || !goalsReady)
                const SizedBox(height: 96, child: NeutralLoading())
              else if (entries.isNotEmpty) ...<Widget>[
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
                if (hiddenByGoals > 0) ...<Widget>[
                  const SizedBox(height: AppSpacing.s12),
                  const _HiddenByGoalsHint(),
                ],
              ] else if (hiddenByGoals > 0)
                _NoGoalEntries(onSelected: onSelected)
              else
                _NoEntries(allOff: allOff, onSelected: onSelected),
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

/// Under the entries when goals of "Meine Ziele" hide some of them (Figma
/// `4118:3643`): where to change that. Plain text, like the frame; the hidden
/// entries stay reachable through their modules.
class _HiddenByGoalsHint extends StatelessWidget {
  const _HiddenByGoalsHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Text(
      'Nicht dabei? Unter Profil · Meine Ziele legst du fest, was hier '
      'erscheint.',
      style: AppTextStyles.captionDefault.copyWith(color: colors.textSecondary),
    );
  }
}

/// Every entry of the active modules belongs to a goal that is off: the empty
/// state with the way to "Meine Ziele" (Figma `4118:4444`). No data is lost,
/// the entries are still reachable through their modules and screens.
class _NoGoalEntries extends StatelessWidget {
  const _NoGoalEntries({required this.onSelected});

  final ValueChanged<String> onSelected;

  static const String _title = 'Noch nichts zum Eintragen';
  static const String _message =
      'Lege unter Profil · Meine Ziele fest, was du hier eintragen möchtest. '
      'Deine bisherigen Daten bleiben erhalten.';

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentTint(AppAccent.primary),
                shape: BoxShape.circle,
              ),
              child: Icon(
                AppIcon.target.data,
                size: 30,
                color: colors.accent(AppAccent.primary),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Title and explanation are read as one block, like every empty state.
        Semantics(
          container: true,
          label: '$_title. $_message',
          excludeSemantics: true,
          child: Column(
            children: <Widget>[
              Text(
                _title,
                textAlign: TextAlign.center,
                style: AppTextStyles.titleSection.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          label: 'Meine Ziele öffnen',
          onPressed: () => onSelected(AppRoutes.goals),
        ),
      ],
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
