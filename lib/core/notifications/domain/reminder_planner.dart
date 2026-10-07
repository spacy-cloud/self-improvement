import 'package:flutter/foundation.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_inputs.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/notifications/domain/reminder_texts.dart';
import 'package:self_improvement/core/time/clock_service.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

/// Why the planner returned nothing although reminders could exist.
enum ReminderPlanSkip {
  /// The master switch is off (default): nothing is scheduled and everything
  /// pending is cancelled.
  remindersOff,

  /// Reminders are wanted but the system does not allow notifications: the
  /// same, and the status explains it.
  permissionMissing,
}

/// The desired set of notifications for one run.
@immutable
final class ReminderPlan {
  const ReminderPlan({
    required this.notifications,
    this.skipped,
    this.droppedByLimit = 0,
  });

  /// Nothing is planned for a global reason.
  const ReminderPlan.skipped(ReminderPlanSkip reason)
    : this(notifications: const [], skipped: reason);

  /// The notifications to hand to the system, ordered by fire time (focus end
  /// first on equal time), at most [ReminderPlanner.maxNotifications].
  final List<PlannedNotification> notifications;

  /// Set when nothing is planned because reminders are off or not permitted.
  final ReminderPlanSkip? skipped;

  /// How many due notifications were left out by the global cap.
  final int droppedByLimit;

  /// True when the cap cut the plan: the rest is planned on a later start.
  bool get limitReached => droppedByLimit > 0;
}

/// Pure planner: computes the desired set of local notifications from plain
/// facts. It reads no database, no clock of its own and no platform.
///
/// ## Rules
///
/// - **Switches.** Reminders are off by default. With the master switch off,
///   or without the system permission, the plan is empty
///   ([ReminderPlanSkip]); the caller then cancels everything pending.
/// - **Horizon.** Seven local calendar days: today and the next six, found by
///   calendar arithmetic ([LocalDate.addDays]) and never by adding 24 hours,
///   so a day with a daylight saving change is still exactly one day. The
///   horizon applies to what recurs (water slots, habits). It does not apply to
///   a task reminder, see below.
/// - **Cap.** At most [maxNotifications] (40) future notifications overall,
///   ordered by fire time; on equal time the focus end comes first, then
///   tasks, then habits, then water, then by semantic key. 40 stays below the
///   64 pending notifications iOS keeps, so the cap also protects against
///   that limit. What the cap cuts is reported in
///   [ReminderPlan.droppedByLimit]; it is planned on a later run when time has
///   passed and the nearest ones are gone.
/// - **Water.** Every enabled rule of module `nutrition` on every day of the
///   horizon whose wall clock time is still ahead. When today's water goal is
///   already reached, today's remaining water reminders are dropped; later
///   days are unaffected.
/// - **Habits.** Module `tasks`. A habit is reminded at its individual time on
///   every day it applies: from its start date; archiving works from tomorrow,
///   so on the archive day itself the habit still applies and from
///   `archivedFrom` on it does not; soft deleted habits never.
/// - **Tasks.** Module `tasks`. One notification per open task with a reminder
///   (`tasks.reminder_at_utc`), at exactly that instant, under the key
///   `task:<id>`. A reminder is one moment the user chose, not a recurring
///   one, so it is **not** limited to the seven day horizon: it is planned as
///   soon as its instant lies ahead (a reminder in three weeks must not depend
///   on the app being opened in the week before it). It competes for the 40
///   places by fire time like everything else. Completing or deleting the task
///   removes it from the plan, reopening or restoring puts it back, changing
///   the reminder moves it under the same key. The instant is absolute: it
///   does not follow a change of the device time zone, and a daylight saving
///   change cannot move it.
/// - **Focus end.** Module `focus`. Exactly one notification for a *running*
///   session, at the persisted segment start plus the remaining planned
///   seconds. A paused or awaiting session has none. Pause, completion,
///   discard or switching the module off remove it from the plan, resume plans
///   it again.
/// - **Past.** A notification whose time is not strictly after
///   [ReminderInputs.nowUtc] is never planned.
///
/// ## Daylight saving time
///
/// A wall clock time is converted to an instant with [ClockService.toUtc], so
/// the local time of every reminder stays right on the 23 hour and the 25 hour
/// day.
///
/// - **Spring forward (gap).** A time that does not exist on that day (for
///   Europe/Berlin on 2026-03-29 everything from 02:00 to 02:59) is *shifted*
///   to the first valid time after the gap (03:00) instead of skipped: the user
///   still gets the reminder on that day, only slightly later. The semantic
///   key keeps the configured time, so the shift is stable across runs.
/// - **Fall back (ambiguity).** A time that exists twice (2026-10-25 02:00 to
///   02:59) is planned once, at its first occurrence (the earlier offset),
///   which matches how the rest of the app resolves doubled wall clock times.
final class ReminderPlanner {
  const ReminderPlanner({
    required this._clock,
    this.horizonDays = defaultHorizonDays,
    this.maxNotifications = defaultMaxNotifications,
  }) : assert(horizonDays >= 1, 'horizon needs at least one day'),
       assert(maxNotifications >= 1, 'cap needs at least one notification');

  /// Seven calendar days: today plus six.
  static const int defaultHorizonDays = 7;

  /// Global maximum of planned future notifications.
  static const int defaultMaxNotifications = 40;

  final ClockService _clock;

  /// How many local calendar days (starting today) are planned.
  final int horizonDays;

  /// Global cap of planned notifications.
  final int maxNotifications;

  /// Computes the desired set of notifications for [inputs].
  ReminderPlan plan(ReminderInputs inputs) {
    if (!inputs.remindersWanted) {
      return const ReminderPlan.skipped(ReminderPlanSkip.remindersOff);
    }
    if (inputs.permission != NotificationPermission.granted) {
      return const ReminderPlan.skipped(ReminderPlanSkip.permissionMissing);
    }

    final zone = inputs.timeZoneId;
    final today = _clock.localDateOf(inputs.nowUtc, timeZoneId: zone);
    final days = [for (var i = 0; i < horizonDays; i++) today.addDays(i)];

    final byKey = <String, PlannedNotification>{};
    void add(PlannedNotification notification) =>
        byKey.putIfAbsent(notification.semanticKey, () => notification);

    if (inputs.isModuleEnabled(ModuleId.nutrition)) {
      _planWater(inputs, today, days, add);
    }
    if (inputs.isModuleEnabled(ModuleId.tasks)) {
      _planHabits(inputs, days, add);
      _planTasks(inputs, add);
    }
    if (inputs.isModuleEnabled(ModuleId.focus)) {
      _planFocusEnd(inputs, add);
    }

    final all = byKey.values.toList()..sort(_compare);
    final kept = all.length <= maxNotifications
        ? all
        : all.sublist(0, maxNotifications);
    return ReminderPlan(
      notifications: List.unmodifiable(kept),
      droppedByLimit: all.length - kept.length,
    );
  }

  void _planWater(
    ReminderInputs inputs,
    LocalDate today,
    List<LocalDate> days,
    void Function(PlannedNotification) add,
  ) {
    // Sorted so that duplicate slots resolve the same way for any input order.
    final rules = [...inputs.waterRules.where((rule) => rule.enabled)]
      ..sort((a, b) {
        final byTime = a.time.compareTo(b.time);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    for (final day in days) {
      if (day == today && inputs.waterGoalReachedToday) {
        continue;
      }
      for (final rule in rules) {
        final fireAt = _fireAt(day, rule.time, inputs.timeZoneId);
        if (fireAt == null || !fireAt.isAfter(inputs.nowUtc)) {
          continue;
        }
        add(
          PlannedNotification(
            semanticKey: ReminderKeys.water(day, rule.time),
            kind: ReminderKind.water,
            fireAtUtc: fireAt,
            route: NotificationRoutes.water,
            title: ReminderTexts.waterTitle,
            sourceRuleId: rule.id,
          ),
        );
      }
    }
  }

  void _planHabits(
    ReminderInputs inputs,
    List<LocalDate> days,
    void Function(PlannedNotification) add,
  ) {
    for (final habit in inputs.habits) {
      final time = habit.reminderTime;
      if (time == null) {
        continue;
      }
      for (final day in days) {
        if (!habit.appliesOn(day)) {
          continue;
        }
        final fireAt = _fireAt(day, time, inputs.timeZoneId);
        if (fireAt == null || !fireAt.isAfter(inputs.nowUtc)) {
          continue;
        }
        add(
          PlannedNotification(
            semanticKey: ReminderKeys.habit(habit.id, day),
            kind: ReminderKind.habit,
            fireAtUtc: fireAt,
            route: NotificationRoutes.habitDetail(habit.id),
            title: ReminderTexts.habitTitle,
          ),
        );
      }
    }
  }

  /// A task reminder is a single instant: planned when it lies strictly ahead,
  /// whatever the distance (see the class documentation).
  void _planTasks(
    ReminderInputs inputs,
    void Function(PlannedNotification) add,
  ) {
    for (final task in inputs.tasks) {
      final fireAt = task.reminderAtUtc;
      if (!fireAt.isAfter(inputs.nowUtc)) {
        continue;
      }
      add(
        PlannedNotification(
          semanticKey: ReminderKeys.task(task.id),
          kind: ReminderKind.task,
          fireAtUtc: fireAt,
          route: NotificationRoutes.taskEdit(task.id),
          title: ReminderTexts.taskTitle,
        ),
      );
    }
  }

  void _planFocusEnd(
    ReminderInputs inputs,
    void Function(PlannedNotification) add,
  ) {
    final focus = inputs.focusSession;
    final endsAt = focus?.endsAtUtc;
    if (focus == null || endsAt == null || !endsAt.isAfter(inputs.nowUtc)) {
      return;
    }
    add(
      PlannedNotification(
        semanticKey: ReminderKeys.focusEnd(focus.sessionId),
        kind: ReminderKind.focusEnd,
        fireAtUtc: endsAt,
        route: NotificationRoutes.focusSession,
        title: ReminderTexts.focusEndTitle,
      ),
    );
  }

  /// The instant of [time] on [day] in [zone]; a time inside a spring forward
  /// gap is shifted to the first valid time after the gap.
  DateTime? _fireAt(LocalDate day, LocalTime time, String zone) {
    final resolution = _clock.toUtc(day, time, timeZoneId: zone);
    switch (resolution) {
      case ZonedResolved(:final utc):
        return utc;
      case ZonedNonexistent(:final nextValid):
        // The first valid time can lie on the next day if the gap spans
        // midnight; a smaller time of day than requested reveals that.
        final date = nextValid.minutesOfDay < time.minutesOfDay
            ? day.addDays(1)
            : day;
        final shifted = _clock.toUtc(date, nextValid, timeZoneId: zone);
        return switch (shifted) {
          ZonedResolved(:final utc) => utc,
          ZonedNonexistent() => null,
        };
    }
  }

  static int _compare(PlannedNotification a, PlannedNotification b) {
    final byTime = a.fireAtUtc.compareTo(b.fireAtUtc);
    if (byTime != 0) {
      return byTime;
    }
    final byKind = a.kind.sortRank.compareTo(b.kind.sortRank);
    if (byKind != 0) {
      return byKind;
    }
    return a.semanticKey.compareTo(b.semanticKey);
  }
}
