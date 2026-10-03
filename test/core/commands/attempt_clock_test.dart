import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/attempt_clock.dart';

void main() {
  late DateTime clock;
  late int reads;
  DateTime now() {
    reads++;
    return clock;
  }

  late AttemptClock attempt;

  setUp(() {
    clock = DateTime.utc(2026, 10, 3, 8);
    reads = 0;
    attempt = AttemptClock();
  });

  test('the first attempt reads the clock', () {
    expect(attempt.instantFor('a', now), DateTime.utc(2026, 10, 3, 8));
    expect(reads, 1);
  });

  test('the same content keeps the instant, however late the retry is', () {
    final first = attempt.instantFor(('a', 1), now);
    clock = clock.add(const Duration(minutes: 5));
    expect(attempt.instantFor(('a', 1), now), first);
    expect(reads, 1);
  });

  test('different content takes a fresh instant', () {
    attempt.instantFor(('a', 1), now);
    clock = clock.add(const Duration(minutes: 5));
    expect(attempt.instantFor(('a', 2), now), DateTime.utc(2026, 10, 3, 8, 5));
    expect(reads, 2);
  });

  test('reset forgets the attempt (after a successful save)', () {
    attempt.instantFor('a', now);
    clock = clock.add(const Duration(minutes: 5));
    attempt.reset();
    expect(attempt.instantFor('a', now), DateTime.utc(2026, 10, 3, 8, 5));
    expect(reads, 2);
  });
}
