import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/features/tasks/application/habit_form_controller.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/habit.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/features/tasks/domain/habit_validation.dart';
import 'package:self_improvement/features/tasks/presentation/habit_dialogs.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';
import 'package:self_improvement/shared/local_time.dart';

/// "Neue Gewohnheit" (new) and "Gewohnheit bearbeiten" (with [habitId]).
///
/// V1 habits are daily: there is deliberately no choice of weekdays or time of
/// day. The symbol is one of six, each coupled to an accent of the design.
class HabitFormScreen extends ConsumerWidget {
  const HabitFormScreen({this.habitId, super.key});

  /// The habit to edit, or null for a new one.
  final String? habitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = habitId;
    if (id == null) {
      return const _HabitForm(
        key: ValueKey('habit-create'),
        args: HabitFormArgs.create(),
      );
    }
    return _EditLoader(habitId: id);
  }
}

/// Loads the habit once; later changes of its row never reset a form that is
/// open.
class _EditLoader extends ConsumerStatefulWidget {
  const _EditLoader({required this.habitId});

  final String habitId;

  @override
  ConsumerState<_EditLoader> createState() => _EditLoaderState();
}

class _EditLoaderState extends ConsumerState<_EditLoader> {
  Habit? _opened;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(habitProvider(widget.habitId));
    _opened ??= async.value;
    final opened = _opened;
    if (opened != null) {
      return _HabitForm(
        key: ValueKey('habit-edit-${opened.id}'),
        args: HabitFormArgs.edit(opened),
      );
    }
    return AppScaffold.subpage(
      title: 'Gewohnheit bearbeiten',
      onBack: () => backOrHome(context),
      body: async.when(
        loading: () => const TasksLoadingPlaceholder(),
        error: (error, stack) => ErrorState(
          onRetry: () => ref.invalidate(habitProvider(widget.habitId)),
        ),
        data: (habit) => EmptyState(
          title: 'Gewohnheit nicht gefunden',
          message: 'Diese Gewohnheit gibt es nicht mehr.',
          actionLabel: 'Zu den Gewohnheiten',
          onAction: () => context.go(HabitRoutes.tab),
        ),
      ),
    );
  }
}

class _HabitForm extends ConsumerStatefulWidget {
  const _HabitForm({required this.args, super.key});

  final HabitFormArgs args;

  @override
  ConsumerState<_HabitForm> createState() => _HabitFormState();
}

class _HabitFormState extends ConsumerState<_HabitForm> {
  late final TextEditingController _title;
  final FocusNode _titleFocus = FocusNode();

  HabitFormArgs get _args => widget.args;
  bool get _isEdit => _args.habit != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: ref.read(habitFormProvider(_args)).title,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  HabitFormController get _controller =>
      ref.read(habitFormProvider(_args).notifier);

  Future<void> _submit() async {
    if (!mounted) {
      return;
    }
    FocusScope.of(context).unfocus();
    final feedback = ref.read(feedbackServiceProvider);
    final router = GoRouter.of(context);
    final result = await _controller.submit();
    switch (result) {
      case HabitSaved():
        feedback.showSaved(result.message, undo: result.outcome.undo);
        if (router.canPop()) {
          router.pop();
        } else {
          router.go(HabitRoutes.tab);
        }
      case HabitRejected():
        if (!mounted) {
          return;
        }
        final state = ref.read(habitFormProvider(_args));
        if (state.fieldErrors.containsKey(HabitFields.title)) {
          _titleFocus.requestFocus();
        }
        final failure = state.submitFailure;
        if (failure == null) {
          return;
        }
        if (failure is ConflictFailure || failure is NotFoundFailure) {
          feedback.showError(failure.userMessage);
        } else {
          feedback.showError(
            'Speichern fehlgeschlagen. Deine Eingabe bleibt erhalten.',
            onRetry: () => unawaited(_submit()),
          );
        }
    }
  }

  Future<void> _delete() async {
    final deleted = await confirmAndDeleteHabit(context, _args.habit!);
    if (deleted && mounted) {
      context.go(HabitRoutes.tab);
    }
  }

  Future<void> _pickTime() async {
    final current = ref.read(habitFormProvider(_args)).reminderTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Uhrzeit der Erinnerung',
    );
    if (picked == null || !mounted) {
      return;
    }
    _controller.setReminderTime(LocalTime(picked.hour, picked.minute));
  }

  Future<void> _askToDiscard() async {
    final discard = await showConfirmationSheet(
      context,
      title: 'Änderungen verwerfen?',
      message: 'Deine Eingaben sind noch nicht gespeichert.',
      confirmLabel: 'Verwerfen',
      cancelLabel: 'Weiter bearbeiten',
    );
    if (discard && mounted) {
      leaveTo(context, fallback: HabitRoutes.tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final state = ref.watch(habitFormProvider(_args));
    final canSubmit = !state.submitting && (!_isEdit || state.dirty);
    final time = '${state.reminderTime.toIso()} Uhr';

    return PopScope(
      canPop: !state.dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_askToDiscard());
        }
      },
      child: AppScaffold.subpage(
        title: _isEdit ? 'Gewohnheit bearbeiten' : 'Neue Gewohnheit',
        onBack: () => backOrHome(context),
        primaryAction: PrimaryButton(
          label: _isEdit ? 'Änderungen speichern' : 'Gewohnheit speichern',
          onPressed: canSubmit ? () => unawaited(_submit()) : null,
          loading: state.submitting,
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppTextField(
              label: 'Name',
              requirementLabel: 'Pflichtfeld',
              controller: _title,
              focusNode: _titleFocus,
              hint: 'Zum Beispiel: 10 Minuten lesen',
              maxLength: maxHabitTitleLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              errorText: state.fieldErrors[HabitFields.title],
              onChanged: _controller.setTitle,
            ),
            const SizedBox(height: 16),
            const FieldLabel(label: 'Symbol'),
            const SizedBox(height: 8),
            _IconPicker(selected: state.icon, onSelected: _controller.setIcon),
            if (state.fieldErrors[HabitFields.icon] != null) ...<Widget>[
              const SizedBox(height: 8),
              FieldMessage(text: state.fieldErrors[HabitFields.icon]!),
            ],
            const SizedBox(height: 16),
            const FieldLabel(label: 'Wann?'),
            const SizedBox(height: 8),
            const _DailyOnly(),
            const SizedBox(height: 16),
            const FieldLabel(label: 'Erinnerung', requirement: 'optional'),
            const SizedBox(height: 8),
            AppListGroup(
              children: <Widget>[
                EntryListTile.toggle(
                  title: 'Tägliche Erinnerung',
                  subtitle: state.reminderEnabled ? 'Täglich um $time' : 'Aus',
                  icon: AppIcon.reminder.data,
                  accent: AppAccent.habits,
                  value: state.reminderEnabled,
                  onToggle: _controller.setReminderEnabled,
                ),
                if (state.reminderEnabled)
                  EntryListTile.chevron(
                    title: 'Uhrzeit',
                    subtitle: time,
                    icon: AppIcon.clock.data,
                    accent: AppAccent.habits,
                    onTap: () => unawaited(_pickTime()),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Lokale Benachrichtigung. Benachrichtigungen erlaubst du in '
                'den Einstellungen.',
                style: AppTextStyles.captionDefault.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _isEdit
                    ? 'Der Verlauf bleibt erhalten, wenn du Name, Symbol oder '
                          'Erinnerung änderst.'
                    : 'Neue Gewohnheiten zählen ab heute für deinen '
                          'Tagesring.',
                style: AppTextStyles.bodyRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (_isEdit) ...<Widget>[
              const SizedBox(height: 24),
              Center(
                child: SecondaryButton(
                  label: 'Gewohnheit löschen',
                  icon: AppIcon.delete.data,
                  danger: true,
                  expand: false,
                  onPressed: state.submitting
                      ? null
                      : () => unawaited(_delete()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The six symbols. The selected one has a thick border and a check mark (not
/// colour alone); each symbol brings its accent colour with it.
class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.selected, required this.onSelected});

  final HabitIcon selected;
  final ValueChanged<HabitIcon> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Symbol',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final icon in HabitIcon.values)
            _IconChoice(
              icon: icon,
              selected: icon == selected,
              onTap: () => onSelected(icon),
            ),
        ],
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final HabitIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final visual = habitVisual(icon);
    final accent = colors.accent(visual.accent);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: 'Symbol: ${icon.label}',
      onTap: onTap,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: AppSizes.touchMin,
        child: Material(
          color: colors.accentTint(visual.accent),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.tile),
            side: selected
                ? BorderSide(color: accent, width: 2.5)
                : BorderSide(color: colors.borderDecorative),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            focusColor: colors.focus.withValues(alpha: 0.2),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(visual.glyph, size: 24, color: accent),
                if (selected)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.check_rounded,
                          size: 10,
                          color: colors.surface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// V1: habits are daily. The only frequency is shown as a fixed, selected
/// choice, so the screen says what the habit does without offering anything
/// that is not built.
class _DailyOnly extends StatelessWidget {
  const _DailyOnly();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        container: true,
        label: 'Häufigkeit: täglich',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.touchMin),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.primaryTint,
              shape: StadiumBorder(
                side: BorderSide(color: colors.primaryButton, width: 1.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: colors.primaryText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Täglich',
                    style: AppTextStyles.bodyStrong.copyWith(
                      color: colors.primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
