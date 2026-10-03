/// Lifecycle state of a focus session (specification section 8.2).
///
/// Open states are [running], [paused] and [awaitingConfirmation]; there is at
/// most ONE open session at any time. [completed] and [discarded] are final.
enum FocusStatus {
  /// The countdown runs; `segment_started_at_utc` is set.
  running('running'),

  /// Paused by the user; the elapsed time is in `accumulated_seconds`.
  paused('paused'),

  /// The planned time is over (countdown reached zero, or the app was closed
  /// past the end). Nothing is awarded and no completed record exists until
  /// the user confirms with "Sitzung speichern".
  awaitingConfirmation('awaiting_confirmation'),

  /// Saved by the user; the saved duration counts on the completion day.
  completed('completed'),

  /// Thrown away by the user; never counts as focus time.
  discarded('discarded');

  const FocusStatus(this.key);

  /// Stable persisted identifier.
  final String key;

  /// Whether the session still occupies the single "open session" slot.
  bool get isOpen =>
      this == running || this == paused || this == awaitingConfirmation;

  /// The status for a persisted [key], or `null` when unknown.
  static FocusStatus? tryParse(String key) {
    for (final status in values) {
      if (status.key == key) {
        return status;
      }
    }
    return null;
  }

  /// Like [tryParse], but an unknown key is a programming/data error.
  static FocusStatus fromKey(String key) =>
      tryParse(key) ?? (throw ArgumentError.value(key, 'key', 'unknown'));
}
