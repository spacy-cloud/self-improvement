import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/settings/app_settings_value.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/profile/presentation/profile_widgets.dart';
import 'package:self_improvement/features/reminders/presentation/reminders_section.dart';
import 'package:self_improvement/features/settings/application/about_info.dart';
import 'package:self_improvement/features/settings/application/settings_actions.dart';
import 'package:self_improvement/features/settings/application/settings_providers.dart';
import 'package:self_improvement/features/settings/presentation/neutral_icon_tile.dart';

/// "Einstellungen" (Figma `4024:2`, reminders block `4055:416`, version row
/// `4119:254`): profile entry, theme, reduced motion, haptics, the reminders
/// block (owned by the reminders feature), modules, data and backup, version
/// (opens "Über die App") and licences.
///
/// Every row does something; there are no account or cloud switches. Deviation
/// from the frame: export, import and reset are one entry "Daten & Sicherung",
/// because the data screen holds all three and the destructive reset stays
/// behind its own confirmation there.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final profile = ref.watch(profileProvider);
    final modules = ref.watch(moduleStatusesProvider);
    final settingsValue = settings.value;
    final profileValue = profile.value;
    final moduleMap = modules.value;
    final failed =
        settings.hasError ||
        profile.hasError ||
        modules.hasError ||
        (settings.hasValue && settingsValue == null) ||
        (profile.hasValue && profileValue == null);
    final Widget body;
    if (failed) {
      body = ErrorState(
        onRetry: () {
          ref
            ..invalidate(appSettingsProvider)
            ..invalidate(profileProvider)
            ..invalidate(moduleStatusesProvider);
        },
      );
    } else if (settingsValue == null ||
        profileValue == null ||
        moduleMap == null) {
      body = const SizedBox(height: 160);
    } else {
      body = _SettingsContent(
        settings: settingsValue,
        profile: profileValue,
        modules: moduleMap,
      );
    }
    return AppScaffold.subpage(
      title: 'Einstellungen',
      onBack: () => leaveScreen(context, fallback: ProfileRoutes.profile),
      body: body,
    );
  }
}

/// Texts of the theme choices, in the order of the choice sheet.
const Map<AppThemeMode, (String, String)> _themeTexts = {
  AppThemeMode.system: ('System', 'Folgt deinem Gerät: Hell oder Dunkel'),
  AppThemeMode.light: ('Hell', 'Heller Hintergrund'),
  AppThemeMode.dark: ('Dunkel', 'Dunkler Hintergrund'),
  AppThemeMode.oled: ('OLED', 'Reines Schwarz als Hintergrund'),
};

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({
    required this.settings,
    required this.profile,
    required this.modules,
  });

  final AppSettingsValue settings;
  final UserProfile profile;
  final Map<ModuleId, bool> modules;

  /// Runs one settings change. A failed write keeps the old value on screen
  /// (the switches show the stored state) and offers a retry. The retry only
  /// needs the two services, so it still works after the user left the page.
  Future<void> _apply(
    FeedbackService feedback,
    SettingsActions actions,
    Future<SettingsResult> Function(SettingsActions actions) change,
  ) async {
    final result = await change(actions);
    if (result is SettingsFailed) {
      final failure = result.failure;
      feedback.showError(
        failure is StorageFailure
            ? 'Die Einstellung konnte nicht gespeichert werden. '
                  'Der bisherige Wert bleibt aktiv.'
            : failure.userMessage,
        onRetry: () => fireAndForget(() => _apply(feedback, actions, change)),
      );
    }
  }

  Future<void> _run(
    WidgetRef ref,
    Future<SettingsResult> Function(SettingsActions actions) change,
  ) {
    return _apply(
      ref.read(feedbackServiceProvider),
      ref.read(settingsActionsProvider),
      change,
    );
  }

  Future<void> _chooseTheme(BuildContext context, WidgetRef ref) async {
    final current = AppThemeMode.tryParse(settings.themeModeKey);
    final chosen = await showModalBottomSheet<AppThemeMode>(
      context: context,
      sheetAnimationStyle: AppMotion.surfaceStyleOf(context),
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: context.tokens.colors.scrim,
      barrierLabel: 'Schließen',
      constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: _ThemeSheet(current: current ?? AppThemeMode.system),
      ),
    );
    if (chosen == null || chosen == current) {
      return;
    }
    await _run(ref, (actions) => actions.setThemeMode(chosen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    final theme = AppThemeMode.tryParse(settings.themeModeKey);
    final themeLabel = _themeTexts[theme ?? AppThemeMode.system]!.$1;
    // With large text a value next to the title would leave the title no room;
    // it moves into the second line.
    final large =
        MediaQuery.textScalerOf(context).scale(1) > AppSizes.stackTextScale;
    final enabledModules = modules.values.where((on) => on).length;
    final systemReducesMotion = MediaQuery.disableAnimationsOf(context);
    final bodyOn = modules[ModuleId.body] ?? true;

    Widget neutralTile(AppIcon icon) => NeutralIconTile(icon.data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppSectionHeader.group(title: 'Profil'),
        const SizedBox(height: 8),
        AppCard(
          onTap: () => context.push(ProfileRoutes.edit),
          semanticLabel:
              '${profile.effectiveName}, '
              '${bodyOn ? 'Name und Körperdaten' : 'Name'} bearbeiten, '
              'nur lokal gespeichert',
          child: Row(
            children: [
              ProfileAvatar(initials: profile.initials, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.effectiveName,
                      style: AppTextStyles.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      bodyOn ? 'Name und Körperdaten' : 'Name',
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppBadge(label: 'Nur lokal', icon: AppIcon.lock.data),
                  ],
                ),
              ),
              Icon(
                AppIcon.chevronRight.data,
                size: 20,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const AppSectionHeader.group(title: 'Darstellung'),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            if (large)
              EntryListTile.chevron(
                title: 'Design',
                subtitle: 'Aktuell: $themeLabel',
                icon: AppIcon.theme.data,
                accent: AppAccent.focus,
                semanticLabel: 'Design, $themeLabel, ändern',
                onTap: () => fireAndForget(() => _chooseTheme(context, ref)),
              )
            else
              EntryListTile.value(
                title: 'Design',
                subtitle: 'Hell · Dunkel · OLED · System',
                value: themeLabel,
                showChevron: true,
                icon: AppIcon.theme.data,
                accent: AppAccent.focus,
                semanticLabel: 'Design, $themeLabel, ändern',
                onTap: () => fireAndForget(() => _chooseTheme(context, ref)),
              ),
            EntryListTile.toggle(
              title: 'Reduzierte Bewegung',
              subtitle: systemReducesMotion
                  ? 'Animationen abschalten. Das System fordert sie bereits '
                        'an.'
                  : 'Animationen abschalten',
              leading: neutralTile(AppIcon.reducedMotion),
              value: settings.reduceMotion,
              onToggle: (value) => fireAndForget(
                () => _run(
                  ref,
                  (actions) => actions.setReduceMotion(value: value),
                ),
              ),
            ),
            EntryListTile.toggle(
              title: 'Haptisches Feedback',
              subtitle: 'Vibration beim Abhaken',
              leading: neutralTile(AppIcon.haptics),
              value: settings.haptics,
              onToggle: (value) => fireAndForget(() async {
                await _run(ref, (actions) => actions.setHaptics(value: value));
                if (value) {
                  await ref.read(appHapticsProvider).confirm(force: true);
                }
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const RemindersSection(),
        const SizedBox(height: 16),
        const AppSectionHeader.group(title: 'Module'),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            if (large)
              EntryListTile.chevron(
                title: 'Module verwalten',
                subtitle: '$enabledModules von ${ModuleId.values.length} aktiv',
                icon: AppIcon.modules.data,
                accent: AppAccent.workout,
                onTap: () => context.push(SettingsRoutes.modules),
              )
            else
              EntryListTile.value(
                title: 'Module verwalten',
                subtitle: 'Bereiche ein- und ausblenden',
                value: '$enabledModules von ${ModuleId.values.length}',
                showChevron: true,
                icon: AppIcon.modules.data,
                accent: AppAccent.workout,
                onTap: () => context.push(SettingsRoutes.modules),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const AppSectionHeader.group(title: 'Daten'),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            EntryListTile.chevron(
              title: 'Daten & Sicherung',
              subtitle: 'Exportieren, importieren, zurücksetzen',
              leading: neutralTile(AppIcon.export),
              onTap: () => context.push(SettingsRoutes.data),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const AppSectionHeader.group(title: 'Über die App'),
        const SizedBox(height: 8),
        AppListGroup(
          children: [
            if (large)
              EntryListTile.chevron(
                title: 'Version',
                subtitle: AppConfig.appVersion,
                leading: neutralTile(AppIcon.info),
                semanticLabel: AboutInfo.versionRowLabel(),
                onTap: () => context.push(SettingsRoutes.about),
              )
            else
              EntryListTile.value(
                title: 'Version',
                value: AppConfig.appVersion,
                showChevron: true,
                leading: neutralTile(AppIcon.info),
                semanticLabel: AboutInfo.versionRowLabel(),
                onTap: () => context.push(SettingsRoutes.about),
              ),
            EntryListTile.chevron(
              title: 'Lizenzen',
              subtitle: 'Schrift, Flutter und Pakete',
              leading: neutralTile(AppIcon.licenses),
              onTap: () => context.push(SettingsRoutes.licenses),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            'Alle Daten bleiben auf diesem Gerät. Es gibt kein Konto und '
            'keine Cloud.',
            style: AppTextStyles.captionDefault.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet with the four theme choices. Choosing one closes the sheet and
/// returns it; "Schließen", the barrier and Android back return nothing.
class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.current});

  final AppThemeMode current;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Design wählen',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.sheetBorder,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 12),
              Semantics(
                container: true,
                header: true,
                child: Text(
                  'Design wählen',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.titleSection.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final mode in AppThemeMode.values)
                _ThemeOption(
                  mode: mode,
                  selected: mode == current,
                  onTap: () => Navigator.of(context).pop(mode),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SecondaryButton(
                  label: 'Schließen',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final (title, subtitle) = _themeTexts[mode]!;
    return EntryListTile(
      title: title,
      subtitle: subtitle,
      semanticLabel: selected
          ? '$title, $subtitle, ausgewählt'
          : '$title, $subtitle',
      onTap: onTap,
      trailing: selected
          ? Icon(AppIcon.check.data, size: 24, color: colors.primaryText)
          : const SizedBox.square(dimension: 24),
    );
  }
}
