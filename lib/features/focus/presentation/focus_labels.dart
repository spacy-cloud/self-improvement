/// German texts of the focus screens that are derived from data (pure Dart: no
/// Flutter import, trivially unit-testable).
library;

import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';
import 'package:self_improvement/features/focus/domain/focus_history.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_xp_preview.dart';
import 'package:self_improvement/features/gamification/domain/xp_rules.dart';

/// Text of the status pill: `Läuft · Lernen`, `Pausiert · Lernen`, `Geschafft!`
/// (the planned time is over and waits for the confirmation).
String focusStatusText(FocusStatus status, FocusCategory category) =>
    switch (status) {
      FocusStatus.running => 'Läuft · ${category.label}',
      FocusStatus.paused => 'Pausiert · ${category.label}',
      FocusStatus.awaitingConfirmation => 'Geschafft!',
      FocusStatus.completed => 'Abgeschlossen · ${category.label}',
      FocusStatus.discarded => 'Verworfen · ${category.label}',
    };

/// A duration for screen readers: `10 Minuten und 12 Sekunden`,
/// `1 Stunde, 5 Minuten und 3 Sekunden`, `45 Sekunden`.
String spokenDuration(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final parts = <String>[
    if (hours > 0) '$hours ${hours == 1 ? 'Stunde' : 'Stunden'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'Minute' : 'Minuten'}',
    if (rest > 0 || seconds == 0) '$rest ${rest == 1 ? 'Sekunde' : 'Sekunden'}',
  ];
  return switch (parts.length) {
    1 => parts.first,
    2 => '${parts[0]} und ${parts[1]}',
    _ => '${parts[0]}, ${parts[1]} und ${parts[2]}',
  };
}

/// What a screen reader says about the ring of the open session. It is read
/// when the ring is focused; it is not a live region, so the countdown is never
/// announced second by second.
String focusRingSpoken({
  required FocusStatus status,
  required FocusCategory category,
  required int remainingSeconds,
  required int plannedSeconds,
  String? pausedText,
}) {
  final left =
      'Noch ${spokenDuration(remainingSeconds)} von '
      '${spokenDuration(plannedSeconds)}.';
  return switch (status) {
    FocusStatus.running => 'Fokus läuft, ${category.label}. $left',
    FocusStatus.paused =>
      'Fokus pausiert, ${category.label}. $left'
          '${pausedText == null ? '' : ' $pausedText.'}',
    FocusStatus.awaitingConfirmation =>
      'Fokus geschafft, ${category.label}. '
          '${spokenDuration(plannedSeconds)} abgeschlossen. '
          'Die Sitzung wartet auf deine Bestätigung.',
    FocusStatus.completed ||
    FocusStatus.discarded => 'Fokus beendet, ${category.label}.',
  };
}

/// The planned duration of the setup for screen readers: `25 Minuten`.
String plannedMinutesSpoken(int minutes) =>
    '$minutes ${minutes == 1 ? 'Minute' : 'Minuten'}';

/// The remaining time rounded UP to whole minutes, for places that must not
/// change every second (dashboard card): `Noch 11 Min.`, `Zeit abgelaufen`.
String remainingMinutesText(int remainingSeconds) {
  if (remainingSeconds <= 0) {
    return 'Zeit abgelaufen';
  }
  return 'Noch ${(remainingSeconds + 59) ~/ 60} Min.';
}

/// How long a session is paused, in the wording of the pause screen:
/// `gerade pausiert`, `pausiert seit 2 Min.`, `pausiert seit 1 Std. 5 Min.`.
String pausedSinceText(Duration since) {
  final minutes = since.inMinutes < 0 ? 0 : since.inMinutes;
  if (minutes < 1) {
    return 'gerade pausiert';
  }
  if (minutes < 60) {
    return 'pausiert seit $minutes Min.';
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? 'pausiert seit $hours Std.'
      : 'pausiert seit $hours Std. $rest Min.';
}

/// `Heute` card caption: the goal progress in words.
String focusTodayCaption(FocusTodaySummary summary) {
  if (summary.goalMinutes == null) {
    return summary.isEmpty
        ? 'Noch keine Sitzung heute'
        : sessionCountText(summary.sessionCount);
  }
  if (summary.goalReached) {
    return 'Tagesziel erreicht';
  }
  return 'Noch ${summary.remainingGoalMinutes} Min. bis zu deinem Tagesziel';
}

/// `1 Sitzung heute`, `3 Sitzungen heute`.
String sessionCountText(int count) =>
    count == 1 ? '1 Sitzung heute' : '$count Sitzungen heute';

/// Spoken text of the "today" progress bar.
String focusTodaySpoken(FocusTodaySummary summary) {
  final goal = summary.goalMinutes;
  final done = summary.completedMinutes;
  return goal == null
      ? 'Fokuszeit heute: $done Minuten'
      : 'Fokuszeit heute: $done von $goal Minuten';
}

/// What saving a session of [savedSeconds] adds to today, in words: the saved
/// time and, with an active goal, the progress `45 → 70 von 60 Min.`.
String focusSaveEffectText({
  required int savedSeconds,
  required FocusTodaySummary today,
}) {
  final saved = formatFocusDuration(savedSeconds);
  final before = today.completedMinutes;
  final after = (today.completedSeconds + savedSeconds) ~/ 60;
  final goal = today.goalMinutes;
  return goal == null
      ? 'Speichern zählt $saved zu deiner Fokuszeit heute '
            '($before → $after Min.).'
      : 'Speichern zählt $saved zu deinem Tagesziel '
            '($before → $after von $goal Min.).';
}

/// German text for [outcome], or null when nothing is shown.
String? focusXpText(FocusXpOutcome outcome) => switch (outcome) {
  FocusXpOutcome.hidden => null,
  FocusXpOutcome.belowMinimum =>
    'Unter 5 Minuten: Die Zeit wird gespeichert, es gibt keine XP.',
  FocusXpOutcome.limitReached => 'Für heute gibt es keine weiteren Fokus-XP.',
  FocusXpOutcome.awarded => '+${XpRules.focusPoints} XP beim Speichern',
};

/// Subtitle of the dashboard card while a session is open.
String focusOpenCardSubtitle({
  required FocusStatus status,
  required FocusCategory category,
  required int remainingSeconds,
}) => switch (status) {
  FocusStatus.running =>
    '${category.label} · ${remainingMinutesText(remainingSeconds)}',
  FocusStatus.paused =>
    '${category.label} · ${formatCountdown(remainingSeconds)} übrig',
  FocusStatus.awaitingConfirmation => '${category.label} · Bestätigung offen',
  FocusStatus.completed || FocusStatus.discarded => category.label,
};

/// Value line of the dashboard card while a session is open.
String focusOpenCardValue(FocusStatus status) => switch (status) {
  FocusStatus.running => 'Läuft',
  FocusStatus.paused => 'Pausiert',
  FocusStatus.awaitingConfirmation => 'Geschafft!',
  FocusStatus.completed || FocusStatus.discarded => '–',
};

/// The label of the resume action for the open session.
String focusResumeLabel(FocusStatus status) =>
    status == FocusStatus.awaitingConfirmation
    ? 'Sitzung bestätigen'
    : 'Fokus fortsetzen';
