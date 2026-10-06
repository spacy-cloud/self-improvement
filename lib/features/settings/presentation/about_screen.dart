import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';
import 'package:self_improvement/features/settings/application/about_actions.dart';
import 'package:self_improvement/features/settings/application/about_info.dart';
import 'package:self_improvement/features/settings/application/own_license.dart';
import 'package:self_improvement/features/settings/presentation/neutral_icon_tile.dart';

/// "Über die App" (Figma `4119:418`, dark `4119:512`, OLED `4119:606`): the app
/// symbol, name and version with build number, then author, website, privacy
/// note and the technical versions in one group, the way to the licences of the
/// packages in a second one, and at the very end the full licence text of the
/// own code. It opens from the "Version" row of the settings and is built like
/// the page "Lizenzen": a sub page with a scrolling body, so the page also
/// scrolls at 200 % text, down to the last line of the licence.
///
/// Version, build number and the schema versions are read from the constants
/// (see [AboutInfo]), the licence text from the file `LICENSE` (see
/// [ownLicenseAsset]). The app itself never loads anything from the network:
/// the website row hands the address to the browser of the system, and only
/// after a tap.
///
/// Deviations from the frames, with reasons, are listed in
/// `docs/screens/profile-settings.md` (section 3).
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  /// Space between the blocks of the page (the frame's gap).
  static const double _gap = 12;

  /// The group heading of the frame: the same label as in the settings, with
  /// the frame's top space of 6.
  static const EdgeInsets _headingPadding = EdgeInsets.only(left: 8, top: 6);

  /// Taps on "Website". Both services are read before the first `await`, so
  /// the answer still reaches the user when they leave the page while the
  /// browser opens.
  Future<void> _openWebsite(WidgetRef ref) async {
    final actions = ref.read(aboutActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    final outcome = await actions.openWebsite();
    switch (outcome) {
      case WebsiteOutcome.opened:
      case WebsiteOutcome.busy:
        break;
      case WebsiteOutcome.copied:
        feedback.showInfo(
          'Kein Browser gefunden. Die Adresse ${AboutInfo.websiteLabel} wurde '
          'kopiert.',
        );
      case WebsiteOutcome.failed:
        feedback.showInfo(
          'Die Adresse konnte nicht geöffnet werden: '
          '${AboutInfo.websiteLabel}',
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.tokens.colors;
    return AppScaffold.subpage(
      title: 'Über die App',
      onBack: () => leaveScreen(context, fallback: SettingsRoutes.settings),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _AppHead(),
          const SizedBox(height: _gap),
          const AppSectionHeader.group(
            title: 'Über die App',
            padding: _headingPadding,
          ),
          const SizedBox(height: _gap),
          AppListGroup(
            dividerIndent: 0,
            children: [
              EntryListTile(
                title: 'Autor',
                subtitle: AboutInfo.author,
                leading: NeutralIconTile(AppIcon.profile.data),
              ),
              EntryListTile(
                title: 'Website',
                subtitle: AboutInfo.websiteLabel,
                leading: const NeutralIconTile(Icons.language_rounded),
                trailing: Icon(
                  Icons.open_in_new_rounded,
                  size: 20,
                  color: colors.textSecondary,
                ),
                semanticLabel:
                    'Website, ${AboutInfo.websiteLabel}, öffnet im Browser',
                onTap: () => fireAndForget(() => _openWebsite(ref)),
              ),
              const EntryListTile(
                title: 'Datenschutz',
                subtitle: AboutInfo.privacy,
                leading: NeutralIconTile(Icons.shield_outlined),
              ),
              EntryListTile(
                title: 'Technische Angaben',
                subtitle: AboutInfo.technicalLine(),
                leading: const NeutralIconTile(Icons.storage_rounded),
                semanticLabel:
                    'Technische Angaben, ${AboutInfo.technicalSpoken()}',
              ),
            ],
          ),
          const SizedBox(height: _gap),
          AppListGroup(
            dividerIndent: 0,
            children: [
              EntryListTile.chevron(
                title: 'Lizenzen',
                subtitle: 'Lizenzen der verwendeten Pakete',
                leading: NeutralIconTile(AppIcon.licenses.data),
                // The visible title is part of the subtitle, so one phrase
                // carries both without saying "Lizenzen" twice.
                semanticLabel: 'Lizenzen der verwendeten Pakete',
                onTap: () => context.push(SettingsRoutes.licenses),
              ),
            ],
          ),
          const SizedBox(height: _gap),
          const AppSectionHeader.group(
            title: 'Lizenz',
            padding: _headingPadding,
          ),
          const SizedBox(height: _gap),
          const _OwnLicense(),
        ],
      ),
    );
  }
}

/// The licence of the own code, read from the file `LICENSE` (see
/// [ownLicenseAsset]): a card with the name of the licence and its paragraphs,
/// or a short note while it loads, or an error state with a retry. The asset is
/// part of the app, so nothing here touches the network.
class _OwnLicense extends ConsumerWidget {
  const _OwnLicense();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(ownLicenseProvider)
        .when(
          loading: () => const _LicenseLoading(),
          error: (error, stack) => ErrorState(
            title: 'Lizenztext konnte nicht geladen werden',
            message:
                'Der Lizenztext ist Teil der App. Versuche es noch einmal.',
            onRetry: () => ref.invalidate(ownLicenseProvider),
          ),
          data: (text) => _LicenseCard(text: text),
        );
  }
}

class _LicenseLoading extends StatelessWidget {
  const _LicenseLoading();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AppCard(
        child: Text(
          'Lizenztext wird geladen …',
          textAlign: TextAlign.center,
          style: AppTextStyles.captionDefault.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The text of the licence as in the file: the name in the strong style, then
/// each paragraph in the small style of the draft (12 px, secondary colour),
/// 10 px apart. The text is the English original; it is marked as English so a
/// screen reader can switch to the right voice. The card grows with the text
/// size and the page scrolls, so nothing is cut off at 200 %.
class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.text});

  final OwnLicenseText text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Semantics(
      localeForSubtree: const Locale('en'),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.title,
              style: AppTextStyles.bodyStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
            for (final paragraph in text.paragraphs) ...[
              const SizedBox(height: 10),
              Text(
                paragraph,
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The head of the page: the app symbol, the app name and the version line.
class _AppHead extends StatelessWidget {
  const _AppHead();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _AppMark(),
          const SizedBox(height: 6),
          Semantics(
            header: true,
            child: Text(
              AppConfig.appName,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleScreen.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AboutInfo.versionLine(),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// The app symbol: the green rounded square with the rising arrow of the
/// onboarding (the same mark, drawn with the design tokens), 96 px. Decorative.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: 96,
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            colors: <Color>[colors.primary, colors.primaryButton],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(
          Icons.trending_up_rounded,
          size: 52,
          color: colors.onPrimary,
        ),
      ),
    );
  }
}
