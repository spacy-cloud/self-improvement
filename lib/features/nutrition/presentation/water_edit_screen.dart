import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/nutrition_delete_controller.dart';
import 'package:self_improvement/features/nutrition/application/water_form_controller.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/features/nutrition/presentation/water_entry_row.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';
import 'package:self_improvement/shared/german_date.dart';

/// "Eintrag bearbeiten" for one water entry (`/water/:id`): the same fields as
/// "Eigene Menge", save with undo, delete with confirmation and undo (the
/// weight pattern).
class WaterEditScreen extends ConsumerStatefulWidget {
  const WaterEditScreen({required this.entryId, super.key});

  final String entryId;

  @override
  ConsumerState<WaterEditScreen> createState() => _WaterEditScreenState();
}

class _WaterEditScreenState extends ConsumerState<WaterEditScreen> {
  /// The entry as it was when the screen opened; later changes of its row (for
  /// example by an undo elsewhere) never reset a form that is open.
  WaterEntry? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(waterEntryProvider(widget.entryId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _WaterEditForm(
        key: ValueKey('water-edit-${opened.id}'),
        entry: opened,
      );
    }
    return AppScaffold.subpage(
      title: 'Eintrag bearbeiten',
      onBack: () => nutritionBackOrHome(context),
      body: async.when(
        loading: () => const NutritionLoading(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(waterEntryProvider(widget.entryId)),
        ),
        data: (entry) => EmptyState(
          title: 'Eintrag nicht gefunden',
          message: 'Diesen Wassereintrag gibt es nicht mehr.',
          icon: AppIcon.water,
          accent: AppAccent.water,
          actionLabel: 'Zur Übersicht',
          onAction: () => context.go(WaterRoutes.screen),
        ),
      ),
    );
  }
}

class _WaterEditForm extends ConsumerStatefulWidget {
  const _WaterEditForm({required this.entry, super.key});

  final WaterEntry entry;

  @override
  ConsumerState<_WaterEditForm> createState() => _WaterEditFormState();
}

class _WaterEditFormState extends ConsumerState<_WaterEditForm> {
  WaterFormArgs get _args => WaterFormArgs.edit(widget.entry);

  void _leave(GoRouter router) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(WaterRoutes.screen);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await ref.read(waterFormProvider(_args).notifier).submit();
    switch (result) {
      case WaterSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        _leave(router);
      case WaterRejected():
        if (!mounted) {
          return;
        }
        final failure = ref.read(waterFormProvider(_args)).submitFailure;
        if (failure == null) {
          return;
        }
        if (failure is ConflictFailure) {
          feedback.showError(failure.userMessage);
        } else {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: _submit,
          );
        }
    }
  }

  Future<void> _delete() async {
    final router = GoRouter.of(context);
    final entry = widget.entry;
    final clock = ref.read(clockProvider);
    final time = entryTime(clock, entry.occurredAtUtc, entry.timezoneId);
    final deleted = await confirmAndDeleteWater(
      context,
      ref,
      entry: entry,
      when: '${formatDayMonth(entry.localDate)}, $time Uhr',
    );
    if (deleted && mounted) {
      _leave(router);
    }
  }

  Future<void> _askToDiscard() async {
    final router = GoRouter.of(context);
    final discard = await confirmDiscard(context);
    if (discard && mounted) {
      _leave(router);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(waterFormProvider(_args));
    final deleting = ref
        .watch(nutritionDeleteProvider)
        .contains(widget.entry.id);
    final canSubmit = !state.submitting && !deleting && state.dirty;
    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: 'Eintrag bearbeiten',
        onBack: () => nutritionBackOrHome(context),
        primaryAction: PrimaryButton(
          label: 'Änderungen speichern',
          onPressed: canSubmit ? _submit : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WaterFormBody(args: _args, onSubmit: _submit, framed: true),
            const SizedBox(height: 16),
            Center(
              child: SecondaryButton(
                label: 'Eintrag löschen',
                icon: AppIcon.delete.data,
                danger: true,
                expand: false,
                onPressed: state.submitting || deleting ? null : _delete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
