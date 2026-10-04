import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/shared/number_format.dart';

void main() {
  test('thousands use a dot', () {
    expect(formatThousands(0), '0');
    expect(formatThousands(999), '999');
    expect(formatThousands(1000), '1.000');
    expect(formatThousands(7450), '7.450');
    expect(formatThousands(100000), '100.000');
    expect(formatThousands(1234567), '1.234.567');
    expect(formatThousands(-7450), '-7.450');
  });

  test('kilograms have exactly one decimal comma', () {
    expect(formatKilograms(71500), '71,5');
    expect(formatKilograms(71000), '71,0');
    expect(formatKilograms(20000), '20,0');
    expect(formatKilograms(350000), '350,0');
    expect(formatTenths(5), '0,5');
  });

  test('signed kilogram deltas use the true minus and explicit plus', () {
    expect(formatSignedKilograms(-300), '−0,3');
    expect(formatSignedKilograms(500), '+0,5');
    expect(formatSignedKilograms(0), '0,0');
    expect(formatSignedKilograms(-1200), '−1,2');
  });

  test('liters have up to two decimals and no unnecessary zeros', () {
    expect(formatLiters(250), '0,25');
    expect(formatLiters(500), '0,5');
    expect(formatLiters(1000), '1');
    expect(formatLiters(1250), '1,25');
    expect(formatLiters(1500), '1,5');
    expect(formatLiters(2500), '2,5');
    expect(formatLiters(2000), '2');
    expect(formatLiters(50), '0,05');
    expect(formatLiters(10000), '10');
    expect(formatLiters(1990), '1,99');
  });

  test('percentages round half up', () {
    expect(roundedPercent(0.745), 75);
    expect(roundedPercent(0.6), 60);
    expect(roundedPercent(1.2), 120);
    expect(roundedPercent(0), 0);
  });

  test('a percentage is 100 only when the whole is reached', () {
    expect(roundedPercent(0.9966), 99, reason: '99,66 would round up to 100');
    expect(roundedPercent(0.995), 99);
    expect(roundedPercent(0.9949), 99);
    expect(roundedPercent(1), 100);
    expect(roundedPercent(1.004), 100, reason: 'beyond the whole stays');
    expect(wholePercent(99.78), 99);
    expect(wholePercent(100), 100);
    expect(wholePercent(100.4), 100);
  });
}
