/// The "now" of a new entry whose time the user did not touch, frozen while
/// the content stays the same.
///
/// A form saves "the moment of saving" for such an entry. If that instant were
/// read again on a retry after a failure, the content fingerprint would differ
/// from the first attempt and `SubmissionTracker` would hand out a NEW command
/// id, although the user changed nothing. Keeping the instant of the first
/// attempt makes the retry byte-identical (same fingerprint, same id), while
/// edited content takes a fresh "now".
class AttemptClock {
  Object? _content;
  DateTime? _instant;

  /// The instant for content described by [content] (any value with value
  /// equality): [now] is read only when there is no attempt yet or the content
  /// differs from the last one.
  DateTime instantFor(Object content, DateTime Function() now) {
    final frozen = _instant;
    if (frozen != null && _content == content) {
      return frozen;
    }
    final fresh = now();
    _content = content;
    _instant = fresh;
    return fresh;
  }

  /// Forget the attempt: after a successful save, or when the form starts over.
  void reset() {
    _content = null;
    _instant = null;
  }
}
