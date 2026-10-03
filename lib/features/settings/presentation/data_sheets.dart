import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:self_improvement/core/backup/backup_format.dart';
import 'package:self_improvement/core/backup/import_preview.dart';
import 'package:self_improvement/core/backup/import_validation_report.dart';
import 'package:self_improvement/core/backup/reset_service.dart';
import 'package:self_improvement/core/config/app_config.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/reminders/presentation/sheet_frame.dart';
import 'package:self_improvement/features/settings/application/data_backup_actions.dart';
import 'package:self_improvement/features/settings/application/data_backup_rules.dart';
import 'package:self_improvement/shared/german_date.dart';
import 'package:self_improvement/shared/number_format.dart';

// ---------------------------------------------------------------------------
// Import preview (Figma 4055:160)
// ---------------------------------------------------------------------------

/// Shows the preview of a validated backup and, after the explicit
/// confirmation, replaces all data. Returns the outcome when the data was
/// replaced and `null` when the user cancelled (nothing changed).
Future<ImportOutcome?> showImportPreviewSheet(
  BuildContext context, {
  required PreparedImport prepared,
  required String fileName,
}) => showAppModalSheet<ImportOutcome>(
  context,
  builder: (_) => ImportPreviewSheet(prepared: prepared, fileName: fileName),
);

/// Content of the import preview sheet: what the file contains, what will be
/// replaced and the confirmation. The sheet stays open when replacing fails
/// and says so; the existing data is intact in that case.
class ImportPreviewSheet extends ConsumerStatefulWidget {
  const ImportPreviewSheet({
    required this.prepared,
    required this.fileName,
    super.key,
  });

  final PreparedImport prepared;
  final String fileName;

  @override
  ConsumerState<ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends ConsumerState<ImportPreviewSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(dataBackupActionsProvider)
        .confirmImport(widget.prepared);
    if (!mounted) {
      return;
    }
    switch (result) {
      case ImportCommitted(:final outcome):
        Navigator.of(context).pop(outcome);
      case ImportCommitFailed():
        setState(() {
          _busy = false;
          _error =
              'Das Wiederherstellen ist fehlgeschlagen. Deine bisherigen '
              'Daten sind unverändert. Du kannst es erneut versuchen.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.prepared.preview;
    final clock = ref.watch(clockProvider);
    final created = clock.toLocal(preview.exportedAtUtc);
    final areas = areaCounts(preview.counts);
    final warnings = importWarnings(
      widget.prepared,
      currentAppVersion: AppConfig.appVersion,
    );
    final current = ref.watch(currentEntryCountProvider).value;
    final replaceText = current == null || current == 0
        ? 'Vorhandene App-Daten werden vollständig ersetzt. Das lässt sich '
              'nicht rückgängig machen.'
        : 'Vorhandene App-Daten (${entriesText(current)}) werden '
              'vollständig ersetzt. Das lässt sich nicht rückgängig machen.';

    final footer = <Widget>[
      SheetMessage(text: replaceText, tone: SheetMessageTone.warning),
      if (_error != null) ...<Widget>[
        const SizedBox(height: 8),
        SheetMessage(text: _error!, tone: SheetMessageTone.error),
      ],
      const SizedBox(height: 16),
      PrimaryButton(
        label: 'Ersetzen und wiederherstellen',
        loading: _busy,
        loadingLabel: 'Wird wiederhergestellt …',
        onPressed: _busy ? null : _confirm,
      ),
      const SizedBox(height: 12),
      SecondaryButton(
        label: 'Abbrechen',
        autofocus: true,
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
      ),
    ];

    return PopScope(
      canPop: !_busy,
      child: AppSheetFrame(
        title: 'Sicherung wiederherstellen?',
        onClose: _busy ? null : () => Navigator.of(context).pop(),
        footer: footer,
        children: <Widget>[
          _InfoCard(
            rows: <_InfoRowData>[
              _InfoRowData('Datei', widget.fileName),
              _InfoRowData(
                'Erstellt am',
                '${formatDayMonth(created.date)} ${created.date.year}, '
                    '${created.time.toIso()} Uhr',
              ),
              _InfoRowData('Profil', preview.profileName),
              _InfoRowData(
                'Einträge',
                formatThousands(userEntryCount(preview.counts)),
              ),
              _InfoRowData('App-Version', preview.appVersion),
              const _InfoRowData(
                'Format',
                'Version ${BackupFormat.schemaVersion}',
              ),
            ],
          ),
          if (areas.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _AreaList(areas: areas),
          ],
          for (final warning in warnings) ...<Widget>[
            const SizedBox(height: 8),
            SheetMessage(text: warning),
          ],
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData(this.label, this.value);

  final String label;
  final String value;
}

/// Label and value pairs on the muted surface. At large text the value moves
/// below its label instead of being squeezed next to it.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < rows.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(height: 8),
              _InfoRow(label: rows[i].label, value: rows[i].value),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final labelText = Text(
      label,
      style: AppTextStyles.bodyRegular.copyWith(color: colors.textSecondary),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    Text valueText(TextAlign align) => Text(
      value,
      textAlign: align,
      style: AppTextStyles.bodyStrong.copyWith(color: colors.textPrimary),
    );
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[labelText, valueText(TextAlign.start)],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                labelText,
                const SizedBox(width: 12),
                Expanded(child: valueText(TextAlign.end)),
              ],
            ),
    );
  }
}

/// "Inhalt": the number of records per area, entries first.
class _AreaList extends StatelessWidget {
  const _AreaList({required this.areas});

  final List<AreaCount> areas;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderDecorative),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              container: true,
              header: true,
              child: Text(
                'Inhalt nach Bereichen',
                style: AppTextStyles.bodyStrong.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final area in areas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Semantics(
                  container: true,
                  label: '${area.label}: ${area.count}',
                  excludeSemantics: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          area.label,
                          style: AppTextStyles.bodyRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatThousands(area.count),
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Import rejected (Figma 4055:244)
// ---------------------------------------------------------------------------

/// Tells that the file was rejected and why. Returns `true` when the user
/// wants to choose another file.
Future<bool> showImportRejectedSheet(
  BuildContext context, {
  required ImportValidationReport report,
  required String fileName,
}) async {
  final another = await showAppModalSheet<bool>(
    context,
    builder: (_) => ImportRejectedSheet(report: report, fileName: fileName),
  );
  return another ?? false;
}

/// Content of the "Import nicht möglich" sheet.
class ImportRejectedSheet extends StatelessWidget {
  const ImportRejectedSheet({
    required this.report,
    required this.fileName,
    super.key,
  });

  final ImportValidationReport report;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final rejection = describeRejection(report);
    final footer = <Widget>[
      PrimaryButton(
        label: 'Andere Datei wählen',
        onPressed: () => Navigator.of(context).pop(true),
      ),
      const SizedBox(height: 12),
      SecondaryButton(
        label: 'Schließen',
        autofocus: true,
        onPressed: () => Navigator.of(context).pop(false),
      ),
    ];

    return AppSheetFrame(
      title: 'Import nicht möglich',
      onClose: () => Navigator.of(context).pop(false),
      footer: footer,
      children: <Widget>[
        SheetBadge(icon: AppIcon.close.data, accent: AppAccent.error),
        const SizedBox(height: 12),
        Text(
          'Die Datei „$fileName“ ist keine gültige Sicherung dieser App. '
          'Deine vorhandenen Daten wurden nicht verändert.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
        if (rejection.reasons.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Semantics(
            container: true,
            header: true,
            child: Text(
              rejection.reasons.length == 1 ? 'Grund' : 'Gründe',
              style: AppTextStyles.bodyStrong.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final reason in rejection.reasons)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ExcludeSemantics(
                    child: Text(
                      '•',
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: AppTextStyles.bodyRegular.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (rejection.moreNote != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              rejection.moreNote!,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Reset confirmation (Figma 4044:117)
// ---------------------------------------------------------------------------

/// What the user decided in the reset sheet.
sealed class ResetSheetResult {
  const ResetSheetResult();
}

/// The user backed out; nothing changed.
final class ResetSheetCancelled extends ResetSheetResult {
  const ResetSheetCancelled();
}

/// The user wants a backup first; nothing changed.
final class ResetSheetExportFirst extends ResetSheetResult {
  const ResetSheetExportFirst();
}

/// All data was deleted.
final class ResetSheetDone extends ResetSheetResult {
  const ResetSheetDone(this.outcome);

  final ResetOutcome outcome;
}

/// What the user is told after a completed reset.
String resetDoneMessage(ResetOutcome outcome) => outcome.followUpSucceeded
    ? 'Alle App-Daten wurden gelöscht.'
    : 'Alle App-Daten wurden gelöscht. Einige Folgeschritte '
          '(Erinnerungen, Zwischenspeicher) sind fehlgeschlagen. '
          'Starte die App neu, damit alles abgeglichen wird.';

/// Asks for the typed confirmation and, when it matches exactly, deletes all
/// app data.
Future<ResetSheetResult> showResetSheet(BuildContext context) async {
  final result = await showAppModalSheet<ResetSheetResult>(
    context,
    builder: (_) => const ResetSheet(),
  );
  return result ?? const ResetSheetCancelled();
}

/// Content of the reset confirmation: consequences, the typed word and three
/// ways out ("Alles löschen" only with the exact word).
class ResetSheet extends ConsumerStatefulWidget {
  const ResetSheet({super.key});

  @override
  ConsumerState<ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends ConsumerState<ResetSheet> {
  final TextEditingController _typed = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_busy || !ResetPhrase.matches(_typed.text)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final feedback = ref.read(feedbackServiceProvider);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final result = await ref
        .read(dataBackupActionsProvider)
        .resetAll(_typed.text);
    switch (result) {
      case ResetDone(:final outcome):
        // The reset removes the profile, so the router may already have
        // replaced the screens (and this sheet) with the onboarding by now.
        // The message therefore does not depend on the sheet still being there,
        // and the sheet only closes itself while it is still the top route.
        feedback.showInfo(resetDoneMessage(outcome));
        if (mounted && (route?.isCurrent ?? false)) {
          navigator.pop(ResetSheetDone(outcome));
        }
      case ResetFailed():
        if (!mounted) {
          return;
        }
        setState(() {
          _busy = false;
          _error =
              'Das Zurücksetzen ist fehlgeschlagen. Deine Daten sind '
              'unverändert. Du kannst es erneut versuchen.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final typed = _typed.text;
    final matches = ResetPhrase.matches(typed);
    final current = ref.watch(currentEntryCountProvider).value;
    final what = current == null || current == 0
        ? 'Dein Profil, deine Ziele und Einstellungen'
        : 'Dein Profil, ${entriesText(current)}, deine Ziele und '
              'Einstellungen';

    return PopScope(
      canPop: !_busy,
      child: AppSheetFrame(
        title: 'Wirklich alles zurücksetzen?',
        onClose: _busy ? null : () => Navigator.of(context).pop(),
        children: <Widget>[
          const SheetBadge(
            icon: Icons.priority_high_rounded,
            accent: AppAccent.error,
          ),
          const SizedBox(height: 12),
          Text(
            '$what werden dauerhaft von diesem Gerät gelöscht. Geplante '
            'Erinnerungen werden entfernt, danach startet die App wie nach '
            'der Installation. Das kann nicht rückgängig gemacht werden.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyRegular.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Zur Bestätigung „${ResetPhrase.text}“ eingeben',
            controller: _typed,
            hint: ResetPhrase.text,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            helperText:
                'Schreibe das Wort genau so: Großbuchstaben, ohne Leerzeichen.',
            errorText: ResetPhrase.isNearMiss(typed)
                ? 'Fast richtig: Bitte genau „${ResetPhrase.text}“ eingeben '
                      '(Großbuchstaben, ohne Leerzeichen).'
                : null,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _reset(),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            SheetMessage(text: _error!, tone: SheetMessageTone.error),
          ],
          const SizedBox(height: 16),
          _DangerButton(
            label: 'Alles löschen',
            loading: _busy,
            loadingLabel: 'Wird gelöscht …',
            onPressed: matches && !_busy ? _reset : null,
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Erst Sicherung exportieren',
            onPressed: _busy
                ? null
                : () =>
                      Navigator.of(context).pop(const ResetSheetExportFirst()),
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            label: 'Abbrechen',
            autofocus: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// The final, irreversible action: filled in the error colour (Figma
/// 4044:117), grey while the typed word does not match. The design system has
/// the outlined danger button only.
class _DangerButton extends StatelessWidget {
  const _DangerButton({
    required this.label,
    required this.onPressed,
    required this.loading,
    required this.loadingLabel,
  });

  final String label;
  final String loadingLabel;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final enabled = onPressed != null && !loading;
    final text = loading ? loadingLabel : label;
    final background = enabled || loading ? colors.error : colors.track;
    final foreground = enabled || loading
        ? colors.onError
        : colors.textTertiary;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      liveRegion: loading,
      label: text,
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.buttonHeight),
        child: Material(
          color: background,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.buttonBorder,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelButton.copyWith(color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
