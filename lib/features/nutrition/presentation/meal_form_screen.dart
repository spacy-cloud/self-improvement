import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_form_controller.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/nutrition_delete_controller.dart';
import 'package:self_improvement/features/nutrition/domain/meal_entry.dart';
import 'package:self_improvement/features/nutrition/domain/meal_validation.dart';
import 'package:self_improvement/features/nutrition/domain/nutrition_rules.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_entry_row.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_routes.dart';
import 'package:self_improvement/features/nutrition/presentation/nutrition_widgets.dart';
import 'package:self_improvement/shared/german_date.dart';

/// Key of the name field.
const Key mealNameFieldKey = ValueKey<String>('meal-name-field');

/// Key of the calorie field.
const Key mealKcalFieldKey = ValueKey<String>('meal-kcal-field');

/// Key of the note field.
const Key mealNoteFieldKey = ValueKey<String>('meal-note-field');

/// "Mahlzeit eintragen" (new) and "Mahlzeit bearbeiten" (with [entryId]).
///
/// Name 1 to 80 characters, calories optional (empty means "not given", a
/// deliberate 0 is a value), time and note. Save and delete report after the
/// commit with "Rückgängig"; input is kept on every error.
class MealFormScreen extends ConsumerWidget {
  const MealFormScreen({this.entryId, super.key});

  /// The meal to edit, or null for a new one.
  final String? entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = entryId;
    if (id == null) {
      return const _MealForm(
        key: ValueKey('meal-create'),
        args: MealFormArgs.create(),
      );
    }
    return _EditLoader(entryId: id);
  }
}

/// Loads the meal once; later changes of its row (for example by an undo
/// elsewhere) never reset a form that is open.
class _EditLoader extends ConsumerStatefulWidget {
  const _EditLoader({required this.entryId});

  final String entryId;

  @override
  ConsumerState<_EditLoader> createState() => _EditLoaderState();
}

class _EditLoaderState extends ConsumerState<_EditLoader> {
  MealEntry? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mealEntryProvider(widget.entryId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _MealForm(
        key: ValueKey('meal-edit-${opened.id}'),
        args: MealFormArgs.edit(opened),
      );
    }
    return AppScaffold.subpage(
      title: 'Mahlzeit bearbeiten',
      onBack: () => nutritionBackOrHome(context),
      body: async.when(
        loading: () => const NutritionLoading(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(mealEntryProvider(widget.entryId)),
        ),
        data: (entry) => EmptyState(
          title: 'Mahlzeit nicht gefunden',
          message: 'Diese Mahlzeit gibt es nicht mehr.',
          icon: AppIcon.meal,
          accent: AppAccent.nutrition,
          actionLabel: 'Zur Übersicht',
          onAction: () => context.go(NutritionRoutes.overview),
        ),
      ),
    );
  }
}

class _MealForm extends ConsumerStatefulWidget {
  const _MealForm({required this.args, super.key});

  final MealFormArgs args;

  @override
  ConsumerState<_MealForm> createState() => _MealFormState();
}

class _MealFormState extends ConsumerState<_MealForm> {
  late final TextEditingController _name;
  late final TextEditingController _kcal;
  late final TextEditingController _note;
  final FocusNode _nameFocus = FocusNode();

  MealFormArgs get _args => widget.args;
  bool get _isEdit => _args.entry != null;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(mealFormProvider(_args));
    _name = TextEditingController(text: initial.nameText);
    _kcal = TextEditingController(text: initial.kcalText);
    _note = TextEditingController(text: initial.note);
  }

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _note.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  MealFormController get _controller =>
      ref.read(mealFormProvider(_args).notifier);

  void _leave(GoRouter router, {required String fallback}) {
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(fallback);
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case MealSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        _leave(router, fallback: '/');
      case MealRejected():
        if (!mounted) {
          return;
        }
        final failure = ref.read(mealFormProvider(_args)).submitFailure;
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
    final deleted = await confirmAndDeleteMeal(
      context,
      ref,
      meal: _args.entry!,
    );
    if (deleted && mounted) {
      _leave(router, fallback: NutritionRoutes.overview);
    }
  }

  Future<void> _pickMoment() async {
    final state = ref.read(mealFormProvider(_args));
    final picked = await pickMoment(
      context,
      date: state.date,
      time: state.time,
      today: ref.read(todayProvider),
      dateHelp: 'Datum der Mahlzeit',
      timeHelp: 'Uhrzeit der Mahlzeit',
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller
      ..setDate(picked.date)
      ..setTime(picked.time);
  }

  Future<void> _askToDiscard() async {
    final router = GoRouter.of(context);
    final discard = await confirmDiscard(context);
    if (discard && mounted) {
      _leave(router, fallback: '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mealFormProvider(_args));
    final today = ref.watch(todayProvider);
    final entry = _args.entry;
    final deleting =
        entry != null && ref.watch(nutritionDeleteProvider).contains(entry.id);
    final canSubmit =
        !state.submitting && !deleting && (!_isEdit || state.dirty);
    final nameError = state.fieldErrors[MealFields.name];
    final kcalError = state.fieldErrors[MealFields.kcal];
    final noteError = state.fieldErrors[MealFields.note];
    final timeError = state.fieldErrors[MealFields.occurredAt];

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: _isEdit ? 'Mahlzeit bearbeiten' : 'Mahlzeit eintragen',
        onBack: () => nutritionBackOrHome(context),
        primaryAction: PrimaryButton(
          label: _isEdit ? 'Änderungen speichern' : 'Mahlzeit speichern',
          onPressed: canSubmit ? _submit : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: mealNameFieldKey,
              label: 'Name',
              requirementLabel: 'Pflichtfeld',
              controller: _name,
              focusNode: _nameFocus,
              hint: 'Zum Beispiel: Linsencurry mit Reis',
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              errorText: nameError,
              onChanged: _controller.setName,
            ),
            FieldErrorAnnouncer(text: nameError),
            const SizedBox(height: 14),
            AppListGroup(
              children: [
                EntryListTile.chevron(
                  title: 'Zeitpunkt',
                  subtitle:
                      '${formatRelativeDay(state.date, today)}, '
                      '${state.time.toIso()} Uhr',
                  icon: AppIcon.clock.data,
                  accent: AppAccent.nutrition,
                  onTap: _pickMoment,
                ),
              ],
            ),
            if (timeError != null) ...[
              const SizedBox(height: 8),
              NutritionFieldError(text: timeError),
            ],
            const SizedBox(height: 14),
            AppTextField(
              key: mealKcalFieldKey,
              // The unit is part of the label: a suffix inside the merged
              // field breaks the semantics tree of a scrolling form (the
              // framework asserts while merging the suffix node).
              label: 'Kalorien in kcal',
              requirementLabel: 'optional',
              controller: _kcal,
              hint: 'Zum Beispiel: 450',
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              helperText:
                  'Leer lassen, wenn du es nicht weißt – dann zählt die '
                  'Mahlzeit als „ohne Angabe“. Es wird nichts geschätzt.',
              errorText: kcalError,
              onChanged: _controller.setKcalText,
            ),
            FieldErrorAnnouncer(text: kcalError),
            const SizedBox(height: 14),
            AppTextField(
              key: mealNoteFieldKey,
              label: 'Notiz',
              requirementLabel: 'optional',
              controller: _note,
              hint: 'Zum Beispiel: mit Kokosmilch',
              maxLength: maxNutritionNoteLength,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              errorText: noteError,
              onChanged: _controller.setNote,
            ),
            FieldErrorAnnouncer(text: noteError),
            if (_isEdit) ...[
              const SizedBox(height: 14),
              Center(
                child: SecondaryButton(
                  label: 'Mahlzeit löschen',
                  icon: AppIcon.delete.data,
                  danger: true,
                  expand: false,
                  onPressed: state.submitting || deleting ? null : _delete,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
