import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_session_controller.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';
import 'package:self_improvement/features/focus/presentation/focus_routes.dart';
import 'package:self_improvement/features/focus/presentation/focus_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';

/// A completed session: its facts and the note (editable), and deleting it.
/// Category, planned and saved time are facts and cannot be edited.
class FocusSessionDetailScreen extends ConsumerStatefulWidget {
  const FocusSessionDetailScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  ConsumerState<FocusSessionDetailScreen> createState() =>
      _FocusSessionDetailScreenState();
}

/// Loads the session once; later changes of its row (for example by an undo
/// elsewhere) never reset a note that is being edited.
class _FocusSessionDetailScreenState
    extends ConsumerState<FocusSessionDetailScreen> {
  FocusSession? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(focusSessionByIdProvider(widget.sessionId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _DetailForm(key: ValueKey('focus-${opened.id}'), session: opened);
    }
    return AppScaffold.subpage(
      title: 'Sitzung bearbeiten',
      onBack: () => backOrHome(context),
      body: async.when(
        loading: () => const ScreenLoading(),
        error: (error, stack) => ErrorState(
          onRetry: () =>
              ref.invalidate(focusSessionByIdProvider(widget.sessionId)),
        ),
        data: (session) => EmptyState(
          title: 'Sitzung nicht gefunden',
          message: 'Diese Sitzung gibt es nicht mehr.',
          actionLabel: 'Zum Verlauf',
          onAction: () => context.go(FocusRoutes.history),
          icon: AppIcon.focus,
          accent: AppAccent.focus,
        ),
      ),
    );
  }
}

class _DetailForm extends ConsumerStatefulWidget {
  const _DetailForm({required this.session, super.key});

  final FocusSession session;

  @override
  ConsumerState<_DetailForm> createState() => _DetailFormState();
}

class _DetailFormState extends ConsumerState<_DetailForm> {
  late final TextEditingController _note;
  late final String _initialNote;
  String? _noteError;

  FocusSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _initialNote = _session.note ?? '';
    _note = TextEditingController(text: _initialNote);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  FocusSessionController get _controller =>
      ref.read(focusSessionControllerProvider.notifier);

  bool get _dirty => _note.text.trim() != _initialNote.trim();

  Future<void> _save() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.updateNote(
      _session.id,
      _note.text,
      expectedRowVersion: _session.rowVersion,
    );
    switch (result) {
      case FocusActionDone():
        feedback.showSaved(result.message, undo: result.undo);
        if (mounted) {
          _leave(router, FocusRoutes.history);
        }
      case FocusActionFailed(:final failure):
        if (failure is ValidationFailure && mounted) {
          setState(() => _noteError = failure.fieldErrors[FocusFields.note]);
        } else if (failure is StorageFailure) {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Notiz bleibt erhalten.',
            onRetry: () => unawaited(_save()),
          );
        } else if (failure is ConflictFailure) {
          feedback.showError(
            'Die Sitzung wurde inzwischen geändert. Bitte öffne sie erneut.',
          );
        } else {
          feedback.showError(failure.userMessage);
        }
      case FocusActionIgnored():
        break;
    }
  }

  Future<void> _confirmDelete() async {
    final clock = ref.read(clockProvider);
    final entry = FocusHistoryEntry.fromSession(_session, clock);
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final confirmed = await showConfirmationSheet(
      context,
      title: 'Sitzung vom ${formatDayMonth(entry.date)} löschen?',
      message:
          '${entry.actualDurationText} ${entry.categoryLabel} wird entfernt. '
          'Du kannst es direkt danach rückgängig machen.',
      confirmLabel: 'Löschen',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final result = await _controller.delete(_session.id);
    switch (result) {
      case FocusActionDone():
        feedback.showSaved(result.message, undo: result.undo);
        if (mounted) {
          _leave(router, FocusRoutes.history);
        }
      case FocusActionFailed(:final failure):
        feedback.showError(
          failure is StorageFailure
              ? 'Löschen fehlgeschlagen. Die Sitzung ist unverändert.'
              : failure.userMessage,
        );
      case FocusActionIgnored():
        break;
    }
  }

  void _leave(GoRouter router, String fallback) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }

  Future<void> _askToDiscard() async {
    final discard = await showConfirmationSheet(
      context,
      title: 'Änderungen verwerfen?',
      message: 'Deine Änderungen sind noch nicht gespeichert.',
      confirmLabel: 'Verwerfen',
      cancelLabel: 'Weiter bearbeiten',
    );
    if (discard && mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final busy = ref.watch(
      focusSessionControllerProvider.select((state) => state.busy),
    );
    final today = ref.watch(todayProvider);
    final entry = FocusHistoryEntry.fromSession(
      _session,
      ref.watch(clockProvider),
    );
    return ListenableBuilder(
      listenable: _note,
      builder: (context, _) {
        final dirty = _dirty;
        return PopScope(
          canPop: !dirty,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              unawaited(_askToDiscard());
            }
          },
          child: AppScaffold.subpage(
            title: 'Sitzung bearbeiten',
            onBack: () => backOrHome(context),
            primaryAction: PrimaryButton(
              label: 'Änderungen speichern',
              loading: busy,
              onPressed: dirty && !busy ? () => unawaited(_save()) : null,
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CardHeading(
                        icon: AppIcon.focus.data,
                        title: entry.categoryLabel,
                        accent: AppAccent.focus,
                        trailing: entry.status.label,
                      ),
                      const SizedBox(height: 8),
                      _FactRow(
                        label: 'Gespeicherte Zeit',
                        value: entry.actualDurationText,
                      ),
                      _FactRow(
                        label: 'Geplant',
                        value: formatFocusDuration(_session.plannedSeconds),
                      ),
                      _FactRow(
                        label: 'Bestätigt',
                        value:
                            '${formatRelativeDay(entry.date, today)}, '
                            '${entry.endedLocalTime.toIso()} Uhr',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Notiz',
                  requirementLabel: 'optional',
                  controller: _note,
                  hint: 'Zum Beispiel: Kapitel 3 gelesen',
                  maxLength: maxFocusNoteLength,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  errorText: _noteError,
                  onChanged: (_) {
                    if (_noteError != null) {
                      setState(() => _noteError = null);
                    }
                  },
                ),
                const SizedBox(height: 14),
                Center(
                  child: SecondaryButton(
                    label: 'Sitzung löschen',
                    icon: AppIcon.delete.data,
                    danger: true,
                    expand: false,
                    onPressed: busy ? null : () => unawaited(_confirmDelete()),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nur die Notiz lässt sich ändern. Kategorie und Zeit sind '
                  'Fakten der Sitzung.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.captionDefault.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One fact of the session: label left, value right.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.bodyRegular.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
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
