import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/focus/domain/focus_formatting.dart';

void main() {
  group('formatCountdown', () {
    test('minutes and seconds with leading zeros', () {
      expect(formatCountdown(1500), '25:00');
      expect(formatCountdown(612), '10:12');
      expect(formatCountdown(59), '00:59');
      expect(formatCountdown(0), '00:00');
      expect(formatCountdown(300), '05:00');
    });

    test('hours from 3600 seconds on', () {
      expect(formatCountdown(3599), '59:59');
      expect(formatCountdown(3600), '1:00:00');
      expect(formatCountdown(3725), '1:02:05');
      expect(formatCountdown(10800), '3:00:00');
    });

    test('negative values show as zero', () {
      expect(formatCountdown(-5), '00:00');
    });
  });

  group('formatFocusDuration', () {
    test('whole minutes round down, like the focus goal counts them', () {
      expect(formatFocusDuration(1200), '20 Min.');
      expect(formatFocusDuration(299), '4 Min.');
      expect(formatFocusDuration(300), '5 Min.');
      expect(formatFocusDuration(60), '1 Min.');
      expect(formatFocusDuration(119), '1 Min.');
      expect(formatFocusDuration(10800), '180 Min.');
    });

    test('below one minute the seconds are shown', () {
      expect(formatFocusDuration(45), '45 Sek.');
      expect(formatFocusDuration(1), '1 Sek.');
      expect(formatFocusDuration(0), '0 Sek.');
      expect(formatFocusDuration(59), '59 Sek.');
      expect(formatFocusDuration(-3), '0 Sek.');
    });
  });
}
