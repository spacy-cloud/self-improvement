import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/reminders/application/reminder_actions.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_labels.dart';
import 'package:self_improvement/features/tasks/domain/task_reminder.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_routes.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_widgets.dart';

/// The block "Erinnerung" of the task form (Figma 4121:314 without, 4121:414
/// with a reminder, 4121:517 editing, 4121:621 notifications not allowed).
///
/// Quick choices ("Heute 18:00" while that is still ahead, "Morgen 09:00", "Aus"),
/// the chosen moment as a field that opens the date and time pickers, a
/// removal in edit mode, and below it one line that says honestly what will
/// happen: no reminder, no notification for a completed task, a reminder that
/// has passed, or a notice when the system, the settings of the app or the
/// planning stand in the way. The reminder is saved in every case; only the
/// notification depends on the state, and the notice says so.
class TaskReminderField extends ConsumerWidget {
  const TaskReminderField({
    required this.reminderAtUtc,
    required this.completed,
    required this.isEdit,
    required this.errorText,
    required this.onChoose,
    required this.onPick,
    super.key,
  });

  /// The reminder of the form (UTC); null means none.
  final DateTime? reminderAtUtc;

  /// Whether the task is completed (a completed task delivers nothing).
  final bool completed;

  /// Editing an existing task: "Erinnerung entfernen" is offered.
  final bool isEdit;

  /// The hint of a refused reminder (a moment in the past, a time that does
  /// not exist); null without one.
  final String? errorText;

  /// A quick choice or "Aus" (null) was tapped.
  final ValueChanged<DateTime?> onChoose;

  /// The field was tapped: the screen opens the pickers.
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final today = ref.watch(todayProvider);
    final now = clock.nowUtc();
    final reminder = reminderAtUtc;
    final choices = quickReminderChoices(clock: clock, nowUtc: now);

    final Widget notice;
    if (reminder == null) {
      notice = const _Caption('Ohne Erinnerung kommt keine Benachrichtigung.');
    } else if (completed) {
      notice = const _Caption(
        'Die Aufgabe ist erledigt, deshalb kommt keine Benachrichtigung.',
      );
    } else if (!reminder.isAfter(now)) {
      notice = const _Caption(
        'Dieser Zeitpunkt ist vorbei. Wähle einen neuen Zeitpunkt oder '
        'entferne die Erinnerung.',
      );
    } else {
      notice = const _DeliveryNotice();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const FieldLabel(label: 'Erinnerung', requirement: 'optional'),
        const SizedBox(height: 8),
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Erinnerung',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final choice in choices)
                AppChoiceChip(
                  label: choice.label,
                  semanticLabel: choice.spokenLabel,
                  selected:
                      reminder != null &&
                      reminder.isAtSameMomentAs(choice.atUtc),
                  onSelected: (_) => onChoose(choice.atUtc),
                ),
              AppChoiceChip(
                label: 'Aus',
                semanticLabel: 'Keine Erinnerung',
                selected: reminder == null,
                onSelected: (_) => onChoose(null),
              ),
            ],
          ),
        ),
        if (reminder != null) ...<Widget>[
          const SizedBox(height: 8),
          PickerField(
            text: taskReminderText(clock.toLocal(reminder), today),
            icon: AppIcon.clock.data,
            semanticLabel:
                'Zeitpunkt der Erinnerung wählen, '
                '${taskReminderSpokenText(clock.toLocal(reminder), today)}',
            onTap: onPick,
          ),
        ],
        if (errorText != null) ...<Widget>[
          const SizedBox(height: 8),
          FieldMessage(text: errorText!),
        ],
        const SizedBox(height: 8),
        notice,
        if (isEdit && reminder != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextActionButton(
              label: 'Erinnerung entfernen',
              danger: true,
              onPressed: () => onChoose(null),
            ),
          ),
      ],
    );
  }
}

/// A line of the reminder block under the field, like the helper text of the
/// other fields.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: AppTextStyles.captionDefault.copyWith(
          color: context.tokens.colors.textSecondary,
        ),
      ),
    );
  }
}

/// What the app can say about the delivery of a reminder that lies ahead: the
/// honest state of the reminders. While the state is not known yet, or when
/// nothing stands in the way, the quiet line; otherwise a notice with the way
/// out. The notice follows the state live, so it disappears when the user
/// comes back from the settings after allowing notifications.
class _DeliveryNotice extends ConsumerWidget {
  const _DeliveryNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(reminderStatusProvider).value;
    final notice = status == null ? null : ReminderLabels.taskNotice(status);
    if (notice != null) {
      return _NoticeBanner(
        notice: notice,
        onAction: () => unawaited(_run(context, ref, notice.action)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _Caption(
          'Du bekommst ungefähr zu dieser Zeit eine Benachrichtigung.',
        ),
        if (status?.planLimitReached ?? false) ...<Widget>[
          const SizedBox(height: 6),
          const _Caption(ReminderTexts.limitNotice),
        ],
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    ReminderNoticeAction action,
  ) async {
    final actions = ref.read(reminderActionsProvider);
    switch (action) {
      case ReminderNoticeAction.openAppSettings:
        unawaited(context.push<void>(TaskRoutes.settings));
      case ReminderNoticeAction.openSystemSettings:
        final feedback = ref.read(feedbackServiceProvider);
        final opened = await actions.openSystemSettings();
        if (!opened) {
          feedback.showInfo(ReminderLabels.settingsNotOpened);
        }
      case ReminderNoticeAction.retry:
        await actions.refresh();
    }
  }
}

/// The notice of Figma 4121:621: warning tint, icon and title, the sentence,
/// and the one action as text. Title and sentence are read as one message; the
/// box is a live region, so the notice is announced when it appears.
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.notice, required this.onAction});

  final ReminderNotice notice;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final background = notice.error ? colors.errorTint : colors.warningTint;
    final foreground = notice.error ? colors.error : colors.warningText;
    return Semantics(
      container: true,
      liveRegion: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadii.controlBorder,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                container: true,
                label: '${notice.title}. ${notice.text}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            AppIcon.error.data,
                            size: 18,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notice.title,
                            style: AppTextStyles.bodyStrong.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notice.text,
                      style: AppTextStyles.captionDefault.copyWith(
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextActionButton(
                  label: notice.actionLabel,
                  semanticLabel: notice.actionSemanticLabel,
                  onPressed: onAction,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
