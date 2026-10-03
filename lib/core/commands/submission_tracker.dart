import 'package:self_improvement/core/commands/id_generator.dart';

/// Keeps the command id of a form submission.
///
/// The SAME id is reused while the submitted content is unchanged (a retry
/// after a failure or a double tap), so a retry can never create a second
/// record. A NEW id is used when the content differs from the last attempt
/// (the user edited the form) or after a successful submit.
///
/// Reusing an id for changed content would be wrong: if the first attempt had
/// actually committed, the changed content would be dropped as a replay.
class SubmissionTracker {
  SubmissionTracker(this._ids);

  final IdGenerator _ids;
  String? _commandId;
  Object? _fingerprint;

  /// The command id to use for content described by [fingerprint] (any value
  /// with value equality, e.g. a record of the form fields).
  String idFor(Object fingerprint) {
    if (_commandId == null || _fingerprint != fingerprint) {
      _commandId = _ids.newId();
      _fingerprint = fingerprint;
    }
    return _commandId!;
  }

  /// Call after the command committed: the next submit is a new action.
  void completed() {
    _commandId = null;
    _fingerprint = null;
  }
}
