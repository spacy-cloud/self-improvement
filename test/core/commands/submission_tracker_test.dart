import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/commands/submission_tracker.dart';

void main() {
  test('the same content reuses the command id (retry, double tap)', () {
    final tracker = SubmissionTracker(SequentialIdGenerator());
    final first = tracker.idFor(('a', 1));
    expect(tracker.idFor(('a', 1)), first);
    expect(tracker.idFor(('a', 1)), first);
  });

  test('changed content gets a new command id', () {
    final tracker = SubmissionTracker(SequentialIdGenerator());
    final first = tracker.idFor(('a', 1));
    final second = tracker.idFor(('a', 2));
    expect(second, isNot(first));
    expect(tracker.idFor(('a', 2)), second);
    // Going back to the earlier content is a new attempt as well.
    expect(tracker.idFor(('a', 1)), isNot(first));
  });

  test('after success the next submit is a new action', () {
    final tracker = SubmissionTracker(SequentialIdGenerator());
    final first = tracker.idFor('x');
    tracker.completed();
    expect(tracker.idFor('x'), isNot(first));
  });

  test('sequential ids are valid UUID v4 shaped and ordered', () {
    final ids = SequentialIdGenerator();
    final a = ids.newId();
    final b = ids.newId();
    final shape = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(shape.hasMatch(a), isTrue);
    expect(a.compareTo(b), lessThan(0));
    final uuid = const UuidGenerator().newId();
    expect(shape.hasMatch(uuid), isTrue);
    expect(const UuidGenerator().newId(), isNot(uuid));
  });
}
