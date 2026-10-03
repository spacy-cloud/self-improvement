import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/backup/backup_exporter.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/platform/backup_file_gateway.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/settings/application/data_backup_actions.dart';
import 'package:self_improvement/features/settings/application/data_backup_rules.dart';
import 'package:self_improvement/features/settings/presentation/data_sheets.dart';

/// "Daten & Sicherung" (route `/settings/data`): export a backup, restore one
/// after a preview, and reset the app.
///
/// Nothing here runs by itself and nothing leaves the device on its own: the
/// export ends in the system share sheet, the import replaces the data only
/// after the preview was confirmed, and the reset needs the typed word.
class DataScreen extends ConsumerStatefulWidget {
  const DataScreen({super.key});

  @override
  ConsumerState<DataScreen> createState() => _DataScreenState();
}

/// What the screen is busy with. While something runs, every action is
/// disabled, so a second tap cannot start a second operation.
enum _Running { idle, creating, sharing, picking }

class _DataScreenState extends ConsumerState<DataScreen> {
  _Running _running = _Running.idle;

  bool get _idle => _running == _Running.idle;

  // ------------------------------------------------------------- export

  Future<void> _startExport({bool askFirst = true}) async {
    if (!_idle) {
      return;
    }
    if (askFirst) {
      final proceed = await showConfirmationSheet(
        context,
        title: 'Sicherung erstellen?',
        message:
            'Die Sicherung enthält deine persönlichen Einträge, zum Beispiel '
            'Name, Gewicht und Notizen, unverschlüsselt. Die App lädt nichts '
            'hoch: Im Teilen-Menü entscheidest du, wohin die Datei geht.',
        confirmLabel: 'Fortfahren',
        destructive: false,
      );
      if (!proceed || !mounted || !_idle) {
        return;
      }
    }
    final actions = ref.read(dataBackupActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    setState(() => _running = _Running.creating);
    final created = await actions.createBackup();
    switch (created) {
      case ExportCreationFailed():
        if (mounted) {
          setState(() => _running = _Running.idle);
        }
        feedback.showError(
          'Die Sicherung konnte nicht erstellt werden. Deine Daten sind '
          'unverändert.',
          onRetry: () => unawaited(_startExport(askFirst: false)),
        );
      case ExportCreated(:final backup, :final entryCount):
        if (!mounted) {
          await actions.discardExport();
          return;
        }
        await _share(backup, entryCount, actions, feedback);
    }
  }

  Future<void> _share(
    ExportedBackup backup,
    int entryCount,
    DataBackupActions actions,
    FeedbackService feedback,
  ) async {
    if (!backup.isRestorable) {
      // The file exists but this app would refuse it: say so before it leaves.
      setState(() => _running = _Running.idle);
      final problems = backup.importCheck.problems;
      final reason = problems.isEmpty
          ? 'Grund unbekannt'
          : describeImportProblem(problems.first);
      final proceed = await showConfirmationSheet(
        context,
        title: 'Sicherung nicht wiederherstellbar',
        message:
            'Diese App würde die Datei beim Import ablehnen ($reason). Du '
            'kannst sie trotzdem teilen, zum Beispiel zur Fehlersuche.',
        confirmLabel: 'Trotzdem teilen',
        destructive: false,
      );
      if (!proceed || !mounted) {
        await actions.discardExport();
        feedback.showInfo(
          'Teilen abgebrochen. Es wurde nichts weitergegeben, deine Daten '
          'sind unverändert.',
        );
        return;
      }
    }
    setState(() => _running = _Running.sharing);
    final shared = await actions.shareBackup(backup);
    if (mounted) {
      setState(() => _running = _Running.idle);
    }
    switch (shared) {
      case ExportSharingFailed():
        feedback.showError(
          'Die Sicherung konnte nicht geteilt werden. Deine Daten sind '
          'unverändert.',
          onRetry: () => unawaited(_startExport(askFirst: false)),
        );
      case ExportShared(:final status):
        switch (status) {
          case BackupShareStatus.shared:
            feedback.showSaved(
              entryCount == 0
                  ? 'Sicherung erstellt und weitergegeben.'
                  : 'Sicherung mit ${entriesText(entryCount)} erstellt und '
                        'weitergegeben.',
            );
          case BackupShareStatus.dismissed:
            feedback.showInfo(
              'Teilen abgebrochen. Es wurde nichts weitergegeben, deine '
              'Daten sind unverändert.',
            );
          case BackupShareStatus.unknown:
            feedback.showInfo(
              'Sicherung an das Teilen-Menü übergeben. Ob sie angekommen '
              'ist, kann die App nicht prüfen.',
            );
        }
    }
  }

  // ------------------------------------------------------------- import

  Future<void> _startImport() async {
    if (!_idle) {
      return;
    }
    final actions = ref.read(dataBackupActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    setState(() => _running = _Running.picking);
    final ImportPick pick;
    try {
      pick = await actions.pickImportFile();
    } finally {
      if (mounted) {
        setState(() => _running = _Running.idle);
      }
    }
    if (!mounted) {
      return;
    }
    switch (pick) {
      case ImportPickCancelled():
        return; // Nothing was chosen, nothing changed, nothing to say.
      case ImportPickUnreadable():
        feedback.showError(
          'Die Datei konnte nicht gelesen werden. Es wurde nichts verändert.',
        );
      case ImportPickRejected(:final report, :final fileName):
        final another = await showImportRejectedSheet(
          context,
          report: report,
          fileName: fileName,
        );
        if (another && mounted) {
          await _startImport();
        }
      case ImportPickReady(:final prepared, :final fileName):
        final outcome = await showImportPreviewSheet(
          context,
          prepared: prepared,
          fileName: fileName,
        );
        if (outcome != null) {
          _announceImport(feedback, prepared, outcome);
        }
    }
  }

  void _announceImport(
    FeedbackService feedback,
    PreparedImport prepared,
    ImportOutcome outcome,
  ) {
    if (!outcome.followUpSucceeded) {
      feedback.showInfo(
        'Sicherung wiederhergestellt. Einige Folgeschritte (Erinnerungen, '
        'Anzeige) sind fehlgeschlagen. Starte die App neu, damit alles '
        'abgeglichen wird.',
      );
      return;
    }
    final entries = userEntryCount(prepared.preview.counts);
    feedback.showSaved(
      entries == 0
          ? 'Sicherung wiederhergestellt.'
          : 'Sicherung wiederhergestellt: ${entriesText(entries)}.',
    );
  }

  // -------------------------------------------------------------- reset

  Future<void> _startReset() async {
    if (!_idle) {
      return;
    }
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await showResetSheet(context);
    switch (result) {
      case ResetSheetCancelled():
        return;
      case ResetSheetExportFirst():
        if (mounted) {
          await _startExport();
        }
      case ResetSheetDone(:final outcome):
        feedback.showInfo(
          outcome.followUpSucceeded
              ? 'Alle App-Daten wurden gelöscht.'
              : 'Alle App-Daten wurden gelöscht. Einige Folgeschritte '
                    '(Erinnerungen, Zwischenspeicher) sind fehlgeschlagen. '
                    'Starte die App neu, damit alles abgeglichen wird.',
        );
        // The profile is back to "not onboarded": the router sends the user
        // to the setup from the start route.
        router.go('/');
    }
  }

  // -------------------------------------------------------------- build

  Future<void> _back() async {
    final router = GoRouter.of(context);
    final handled = await Navigator.of(context).maybePop();
    if (!handled) {
      router.go('/settings');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppScaffold.subpage(
      title: 'Daten & Sicherung',
      onBack: _back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DataCard(
            tile: _NeutralTile(icon: AppIcon.export.data),
            title: 'Daten exportieren',
            children: <Widget>[
              const _CardText(
                'Speichert alle Einträge, Ziele und Einstellungen als '
                'JSON-Datei. Die Datei enthält deine persönlichen Angaben '
                'unverschlüsselt. Im Teilen-Menü entscheidest du, wohin sie '
                'geht.',
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Jetzt exportieren',
                icon: AppIcon.export.data,
                loading:
                    _running == _Running.creating ||
                    _running == _Running.sharing,
                loadingLabel: _running == _Running.sharing
                    ? 'Teilen-Menü ist geöffnet …'
                    : 'Sicherung wird erstellt …',
                onPressed: _idle ? _startExport : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DataCard(
            tile: _NeutralTile(icon: AppIcon.import.data),
            title: 'Daten importieren',
            children: <Widget>[
              const _CardText(
                'Stellt eine Sicherung wieder her. Vor dem Ersetzen siehst du '
                'eine Vorschau mit dem Inhalt der Datei. Es gibt nur Ersetzen, '
                'kein Zusammenführen.',
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: _running == _Running.picking
                    ? 'Datei wird geprüft …'
                    : 'Sicherung auswählen',
                icon: AppIcon.import.data,
                onPressed: _idle ? _startImport : null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DataCard(
            tile: AppIconTile(
              icon: AppIcon.reset.data,
              accent: AppAccent.error,
            ),
            title: 'Alle Daten zurücksetzen',
            titleColor: colors.error,
            children: <Widget>[
              const _CardText(
                'Löscht dein lokales Profil und alle Einträge dauerhaft. '
                'Exportiere vorher eine Sicherung, wenn du sie behalten '
                'willst.',
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: 'Zurücksetzen …',
                danger: true,
                icon: AppIcon.reset.data,
                onPressed: _idle ? _startReset : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _LocalOnlyNote(),
        ],
      ),
    );
  }
}

/// A card of the screen: tile and title, then the explanation and the action.
class _DataCard extends StatelessWidget {
  const _DataCard({
    required this.tile,
    required this.title,
    required this.children,
    this.titleColor,
  });

  final Widget tile;
  final String title;
  final Color? titleColor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              tile,
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  container: true,
                  header: true,
                  child: Text(
                    title,
                    style: AppTextStyles.titleSection.copyWith(
                      color: titleColor ?? colors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _CardText extends StatelessWidget {
  const _CardText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Text(
      text,
      style: AppTextStyles.bodyRegular.copyWith(color: colors.textSecondary),
    );
  }
}

/// The grey icon tile of the Figma cards (the design system tiles are tinted).
class _NeutralTile extends StatelessWidget {
  const _NeutralTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return ExcludeSemantics(
      child: Container(
        width: AppSizes.iconTile,
        height: AppSizes.iconTile,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.track,
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Icon(icon, size: 20, color: colors.textPrimary),
      ),
    );
  }
}

/// "Nur lokal": the promise behind this screen.
class _LocalOnlyNote extends StatelessWidget {
  const _LocalOnlyNote();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                AppIcon.lock.data,
                size: 16,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Alle Daten bleiben auf diesem Gerät. Die App hat kein Konto '
                'und lädt nichts hoch.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
