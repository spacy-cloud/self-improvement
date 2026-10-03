/// German display text for focus durations (deterministic, locale free).
library;

/// A countdown or planned duration as `MM:SS`, or `H:MM:SS` from one hour on:
/// `1500` -> `25:00`, `612` -> `10:12`, `3725` -> `1:02:05`.
///
/// Negative values show as zero.
String formatCountdown(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// A saved duration for lists and summaries: whole minutes (rounded down, like
/// the focus goal counts them), or seconds below one minute.
/// `1200` -> `20 Min.`, `299` -> `4 Min.`, `45` -> `45 Sek.`.
String formatFocusDuration(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  if (seconds < 60) {
    return '$seconds Sek.';
  }
  return '${seconds ~/ 60} Min.';
}
