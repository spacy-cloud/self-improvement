import 'package:self_improvement/core/commands/id_generator.dart';

/// Wraps an [IdGenerator] and remembers every id it issued, so tests can
/// prove that a retry reused a command id.
final class RecordingIdGenerator implements IdGenerator {
  RecordingIdGenerator(this._inner);

  final IdGenerator _inner;

  /// All issued ids in order.
  final List<String> issued = [];

  @override
  String newId() {
    final id = _inner.newId();
    issued.add(id);
    return id;
  }
}
