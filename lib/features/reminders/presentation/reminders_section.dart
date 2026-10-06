import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/data/reminder_preferences_repository.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_overview.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/notifications/domain/scheduled_reminder.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/reminders/application/reminder_actions.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_labels.dart';
import 'package:self_improvement/features/reminders/presentation/reminder_permission_sheet.dart';

/// The reminders block of the settings: the on/off switch with the honest
/// state of the permission, the editable water time slots, the reminders the
/// app has planned, and the way to the system settings when the system blocks
/// notifications.
///
/// Self-contained: the settings screen embeds it as a card below its group
/// heading. Reminders are off by default and nothing here asks for the
/// permission early: the explanation sheet appears when the user switches
/// reminders on, and the system dialog only after "Weiter zur Systemabfrage".
/// The block never claims that a reminder was delivered; it only knows what
/// it planned.
class RemindersSection extends ConsumerStatefulWidget {
  const RemindersSection({super.key});

  @override
  ConsumerState<RemindersSection> createState() => _RemindersSectionState();
}

class _RemindersSectionState extends ConsumerState<RemindersSection>
    with WidgetsBindingObserver {
  /// A change is running (switch, permission dialog or slot): the controls
  /// are disabled so a second tap cannot start a second change.
  bool _busy = false;
  bool _plannedOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the system settings (or the permission dialog): read the
  /// permission again and plan, so the block shows the real state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(ref.read(reminderActionsProvider).refresh());
    }
  }

  // ------------------------------------------------------------ switch on

  Future<void> _onToggle(bool turnOn) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (turnOn) {
        await _turnOn();
      } else {
        await _turnOff();
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _turnOn() async {
    final actions = ref.read(reminderActionsProvider);
    final permission = await actions.permissionStatus();
    if (!mounted) {
      return;
    }
    var askSystem = true;
    if (permission != NotificationPermission.granted) {
      final choice = await showReminderPermissionSheet(
        context,
        permission: permission,
      );
      switch (choice) {
        case ReminderPermissionChoice.later:
          return;
        case ReminderPermissionChoice.askSystem:
          askSystem = true;
        case ReminderPermissionChoice.openSettings:
          askSystem = false;
      }
    }
    await _enable(askSystem: askSystem);
  }

  Future<void> _enable({required bool askSystem}) async {
    if (!mounted) {
      return;
    }
    final actions = ref.read(reminderActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    final change = await actions.enable(askSystem: askSystem);
    switch (change) {
      case ReminderChangeFailed():
        feedback.showError(
          'Speichern fehlgeschlagen. Die Einstellung ist unverändert.',
          onRetry: () => unawaited(_enable(askSystem: askSystem)),
        );
      case ReminderChanged(:final status):
        if (askSystem) {
          _announceEnabled(feedback, status);
        } else {
          final opened = await actions.openSystemSettings();
          if (!opened) {
            feedback.showInfo(ReminderLabels.settingsNotOpened);
          }
        }
    }
  }

  void _announceEnabled(FeedbackService feedback, ReminderStatus status) {
    switch (status.state) {
      case ReminderState.active:
        feedback.showSaved('Erinnerungen eingeschaltet.');
      case ReminderState.blocked:
        feedback.showInfo(
          'Erinnerungen sind vorgemerkt, aber das System blockiert '
          'Benachrichtigungen noch. Erlaube sie in den Systemeinstellungen.',
        );
      case ReminderState.unavailable:
        feedback.showInfo(
          'Benachrichtigungen sind auf diesem Gerät nicht verfügbar. '
          'Erinnerungen können nicht geplant werden.',
        );
      case ReminderState.schedulingError:
        feedback.showError(
          'Erinnerungen konnten nicht vollständig geplant werden.',
          onRetry: () => unawaited(_retryPlanning()),
        );
      case ReminderState.off:
        break;
    }
  }

  // ----------------------------------------------------------- switch off

  Future<void> _turnOff() async {
    final actions = ref.read(reminderActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    final change = await actions.disable();
    switch (change) {
      case ReminderChangeFailed():
        feedback.showError(
          'Speichern fehlgeschlagen. Die Einstellung ist unverändert.',
          onRetry: () => unawaited(_onToggle(false)),
        );
      case ReminderChanged(:final status):
        if (status.lastError == null) {
          feedback.showSaved('Erinnerungen ausgeschaltet.');
        } else {
          feedback.showInfo(
            'Erinnerungen ausgeschaltet. Einige geplante Erinnerungen '
            'konnten nicht beim System entfernt werden und erscheinen '
            'eventuell noch.',
          );
        }
    }
  }

  // ---------------------------------------------------------------- slots

  Future<void> _onSlot(int hour) async {
    if (!mounted) {
      return;
    }
    final actions = ref.read(reminderActionsProvider);
    final feedback = ref.read(feedbackServiceProvider);
    final change = await actions.toggleWaterSlot(
      hour,
      current: () => ref.read(waterReminderHoursProvider).value ?? <int>{},
    );
    if (change is ReminderChangeFailed) {
      feedback.showError(
        'Speichern fehlgeschlagen. Die Uhrzeiten sind unverändert.',
        onRetry: () => unawaited(_onSlot(hour)),
      );
    }
  }

  // ---------------------------------------------------------- other actions

  Future<void> _openSettings() async {
    if (!mounted) {
      return;
    }
    final feedback = ref.read(feedbackServiceProvider);
    final opened = await ref.read(reminderActionsProvider).openSystemSettings();
    if (!opened) {
      feedback.showInfo(ReminderLabels.settingsNotOpened);
    }
  }

  Future<void> _retryPlanning() async {
    if (!mounted) {
      return;
    }
    final feedback = ref.read(feedbackServiceProvider);
    final status = await ref.read(reminderActionsProvider).refresh();
    if (status.state == ReminderState.schedulingError) {
      feedback.showError(
        'Die Erinnerungen konnten weiterhin nicht geplant werden.',
        onRetry: () => unawaited(_retryPlanning()),
      );
    }
  }

  /// Opens the screen a planned reminder points to. The target is resolved
  /// like a tap on the notification: an unknown payload or a switched off
  /// module opens the dashboard, a missing habit the habit list, a missing
  /// task the task list.
  Future<void> _open(ScheduledReminder reminder) async {
    final router = GoRouter.of(context);
    final route = await ref
        .read(notificationEntryResolverProvider)
        .resolve(reminder.route);
    router.go(route);
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(reminderOverviewProvider);
    return overview.when(
      loading: () => const _LoadingCard(),
      error: (error, stack) => ErrorState(
        title: 'Erinnerungen konnten nicht geladen werden',
        message:
            'Deine Einstellungen sind sicher gespeichert. Versuche es noch '
            'einmal.',
        onRetry: () {
          ref
            ..invalidate(reminderStatusProvider)
            ..invalidate(plannedRemindersProvider);
        },
      ),
      data: _card,
    );
  }

  Widget _card(ReminderOverview overview) {
    final status = overview.status;
    final hoursValue = ref.watch(waterReminderHoursProvider);
    final nutritionOn =
        ref.watch(moduleStatusesProvider).value?[ModuleId.nutrition] ?? true;
    final banner = _banner(status);
    // A row whose time has passed was delivered or lost; it is not "planned"
    // any more, whatever the projection still holds until the next run.
    final now = ref.watch(clockProvider).nowUtc();
    final upcoming = <ScheduledReminder>[
      for (final reminder in overview.reminders)
        if (reminder.fireAtUtc.isAfter(now)) reminder,
    ];
    return AppListGroup(
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            EntryListTile.toggle(
              title: 'Erinnerungen',
              subtitle: ReminderLabels.stateSubtitle(
                status,
                planned: upcoming.length,
              ),
              // At very large text the word "Erinnerungen" needs the width
              // of the icon tile, or it would break inside the word.
              icon: MediaQuery.textScalerOf(context).scale(1) > 1.5
                  ? null
                  : AppIcon.reminder.data,
              value: status.wanted,
              onToggle: _busy ? null : _onToggle,
            ),
            ?banner,
          ],
        ),
        _WaterBlock(
          hours: hoursValue.value ?? const <int>{},
          editable: !_busy && hoursValue.hasValue,
          nutritionOn: nutritionOn,
          onToggle: _onSlot,
        ),
        const _OtherKindsNote(),
        if (upcoming.isNotEmpty)
          _PlannedBlock(
            reminders: upcoming,
            open: _plannedOpen,
            onToggle: () => setState(() => _plannedOpen = !_plannedOpen),
            onOpen: _open,
          )
        else if (status.state == ReminderState.active)
          const _Note(
            'Aktuell ist nichts geplant. Wähle Uhrzeiten für die '
            'Trink-Erinnerung, lege eine Gewohnheit mit Uhrzeit an oder gib '
            'einer Aufgabe eine Erinnerung.',
          ),
        _Notices(status: status),
      ],
    );
  }

  Widget? _banner(ReminderStatus status) {
    switch (status.state) {
      case ReminderState.blocked:
        return _StatusBanner(
          title: 'Benachrichtigungen sind blockiert',
          text:
              'Erlaube sie in den Systemeinstellungen, damit Erinnerungen '
              'ankommen.',
          actionLabel: 'Öffnen',
          actionSemanticLabel:
              'Systemeinstellungen für Benachrichtigungen öffnen',
          onAction: _openSettings,
        );
      case ReminderState.unavailable:
        return _StatusBanner(
          title: 'Benachrichtigungen nicht verfügbar',
          text:
              'Dieses Gerät meldet keine Benachrichtigungen oder der Status '
              'ließ sich nicht lesen. Die App funktioniert weiter, nur '
              'Erinnerungen kommen nicht an.',
          actionLabel: 'Erneut prüfen',
          onAction: () => unawaited(_retryPlanning()),
        );
      case ReminderState.schedulingError:
        return _StatusBanner(
          title: 'Planungsfehler',
          text: ReminderLabels.schedulingErrorText(status.lastError),
          actionLabel: 'Wiederholen',
          onAction: () => unawaited(_retryPlanning()),
          error: true,
        );
      case ReminderState.off:
      case ReminderState.active:
        return null;
    }
  }
}

/// A short neutral line while the status is read.
class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return AppCard(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: 'Erinnerungen werden geladen',
        excludeSemantics: true,
        child: Text(
          'Erinnerungen werden geladen …',
          style: AppTextStyles.bodyRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The honest explanation of a state that stops reminders, with the one
/// action that can fix it. Warning tint for "blocked" and "unavailable", error
/// tint for a planning error; title and text carry the meaning, not the colour.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    this.actionSemanticLabel,
    this.error = false,
  });

  final String title;
  final String text;
  final String actionLabel;
  final String? actionSemanticLabel;
  final VoidCallback onAction;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final background = error ? colors.errorTint : colors.warningTint;
    final foreground = error ? colors.error : colors.warningText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Semantics(
        container: true,
        liveRegion: true,
        explicitChildNodes: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  container: true,
                  label: '$title. $text',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: AppTextStyles.bodyRegular.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SecondaryButton(
                    label: actionLabel,
                    semanticLabel: actionSemanticLabel,
                    expand: false,
                    onPressed: onAction,
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

/// The water slots: one chip per hour, any combination. The chips show the
/// stored set; a change is stored and planned by the engine.
class _WaterBlock extends StatelessWidget {
  const _WaterBlock({
    required this.hours,
    required this.editable,
    required this.nutritionOn,
    required this.onToggle,
  });

  final Set<int> hours;
  final bool editable;
  final bool nutritionOn;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final note = !nutritionOn
        ? 'Das Modul Ernährung ist ausgeschaltet. Trink-Erinnerungen kommen '
              'erst wieder, wenn du es einschaltest.'
        : hours.isEmpty
        ? 'Keine Uhrzeit gewählt: Es gibt keine Trink-Erinnerungen.'
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppIconTile(icon: AppIcon.water.data, accent: AppAccent.water),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      container: true,
                      header: true,
                      child: Text(
                        'Trink-Erinnerung',
                        style: AppTextStyles.bodyDefault.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Wähle die Uhrzeiten. Erreichst du dein Tagesziel, '
                      'entfallen die restlichen Erinnerungen des Tages.',
                      style: AppTextStyles.captionDefault.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: 'Uhrzeiten der Trink-Erinnerung',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final hour in ReminderPreferencesRepository.waterSlotHours)
                  AppFilterChip(
                    label: ReminderLabels.slot(hour),
                    semanticLabel: ReminderLabels.slotSpoken(hour),
                    selected: hours.contains(hour),
                    onSelected: editable ? (_) => onToggle(hour) : null,
                  ),
              ],
            ),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              note,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What the other two kinds of reminders are, so the block does not pretend to
/// have switches the app does not have.
class _OtherKindsNote extends StatelessWidget {
  const _OtherKindsNote();

  @override
  Widget build(BuildContext context) {
    return const _Note(
      'Weitere Erinnerungen: Gewohnheiten erinnern zu der Uhrzeit, die du bei '
      'der Gewohnheit einstellst, Aufgaben zu dem Zeitpunkt, den du bei der '
      'Aufgabe wählst. Am Ende einer laufenden Fokus-Sitzung gibt es einmalig '
      'einen Hinweis.',
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              AppIcon.info.data,
              size: 16,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.captionDefault.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The V1 "notification list": what the app has planned, soonest first. There
/// is no delivery history; the app cannot know what the system showed. Tapping
/// a row opens its target like a tap on the notification would.
class _PlannedBlock extends ConsumerWidget {
  const _PlannedBlock({
    required this.reminders,
    required this.open,
    required this.onToggle,
    required this.onOpen,
  });

  /// Rows shown at most when the list is open.
  static const int maxShown = 8;

  final List<ScheduledReminder> reminders;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<ScheduledReminder> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clock = ref.watch(clockProvider);
    final today = ref.watch(todayProvider);
    String when(ScheduledReminder r) =>
        ReminderLabels.when(clock.toLocal(r.fireAtUtc), today);
    final shown = reminders.take(maxShown).toList();
    final hidden = reminders.length - shown.length;
    final summary =
        '${reminders.length} geplant, nächste: ${when(reminders.first)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        EntryListTile(
          title: 'Geplante Erinnerungen',
          subtitle: summary,
          icon: AppIcon.clock.data,
          accent: AppAccent.focus,
          semanticLabel:
              'Geplante Erinnerungen, $summary, '
              '${open ? 'ausgeklappt' : 'eingeklappt'}',
          trailing: Icon(
            (open ? AppIcon.collapse : AppIcon.expand).data,
            size: 24,
            color: context.tokens.colors.textSecondary,
          ),
          onTap: onToggle,
        ),
        if (open) ...<Widget>[
          for (final reminder in shown)
            EntryListTile.chevron(
              title: ReminderTexts.titleFor(reminder.kind!),
              subtitle: when(reminder),
              semanticLabel:
                  '${ReminderTexts.titleFor(reminder.kind!)}, '
                  '${when(reminder)}, öffnen',
              icon: _iconOf(reminder.kind!),
              accent: _accentOf(reminder.kind!),
              onTap: () => onOpen(reminder),
            ),
          if (hidden > 0)
            _Note(
              hidden == 1
                  ? 'Eine weitere Erinnerung ist geplant.'
                  : '$hidden weitere Erinnerungen sind geplant.',
            ),
        ],
      ],
    );
  }

  static IconData _iconOf(ReminderKind kind) => switch (kind) {
    ReminderKind.water => AppIcon.water.data,
    ReminderKind.habit => AppIcon.habit.data,
    ReminderKind.task => AppIcon.task.data,
    ReminderKind.focusEnd => AppIcon.focus.data,
  };

  static AppAccent _accentOf(ReminderKind kind) => switch (kind) {
    ReminderKind.water => AppAccent.water,
    ReminderKind.habit => AppAccent.habits,
    ReminderKind.task => AppAccent.habits,
    ReminderKind.focusEnd => AppAccent.focus,
  };
}

/// The permission as the device reports it, the limits of local reminders and
/// the planning limit, at the foot of the block.
class _Notices extends StatelessWidget {
  const _Notices({required this.status});

  final ReminderStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.tokens.colors;
    final style = AppTextStyles.captionDefault.copyWith(
      color: colors.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(ReminderLabels.permissionLine(status), style: style),
          if (status.wanted) ...<Widget>[
            const SizedBox(height: 6),
            Text(ReminderTexts.deliveryNotice, style: style),
          ],
          if (status.planLimitReached) ...<Widget>[
            const SizedBox(height: 6),
            Text(ReminderTexts.limitNotice, style: style),
          ],
        ],
      ),
    );
  }
}
