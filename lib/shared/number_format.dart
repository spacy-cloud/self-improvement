/// Deterministic German number formatting (decimal comma, thousands dot).
///
/// Implemented without locale data so it behaves identically in tests, on
/// device and independent of the system locale. The UI language is German.
library;

const String _minus = '−'; // true minus sign, as in the design ("−0,3 kg")

/// `1234567` -> `1.234.567`, `-5` -> `-5`.
String formatThousands(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(digits[i]);
  }
  return negative ? '-$buffer' : buffer.toString();
}

/// Integer tenths as a German decimal with exactly one decimal: `715` ->
/// `71,5`, `-3` -> `-0,3` (ASCII minus).
String formatTenths(int tenths) {
  final negative = tenths < 0;
  final abs = tenths.abs();
  final text = '${abs ~/ 10},${abs % 10}';
  return negative ? '-$text' : text;
}

/// Weight in grams as kilograms with one decimal: `71500` -> `71,5`.
String formatKilograms(int grams) => formatTenths(grams ~/ 100);

/// Signed weight difference with a true minus and an explicit plus:
/// `-300` -> `−0,3`, `500` -> `+0,5`, `0` -> `0,0`.
String formatSignedKilograms(int gramsDelta) {
  final tenths = gramsDelta ~/ 100;
  if (tenths == 0) {
    return '0,0';
  }
  final text = formatTenths(tenths.abs());
  return tenths < 0 ? '$_minus$text' : '+$text';
}

/// Millilitres as litres with up to two decimals and no trailing zeros:
/// `1250` -> `1,25`, `2500` -> `2,5`, `2000` -> `2`, `50` -> `0,05`.
String formatLiters(int milliliters) {
  final whole = milliliters ~/ 1000;
  final hundredths = (milliliters % 1000) ~/ 10;
  if (hundredths == 0) {
    return '$whole';
  }
  final fraction = hundredths.toString().padLeft(2, '0');
  final trimmed = fraction.endsWith('0') ? fraction.substring(0, 1) : fraction;
  return '$whole,$trimmed';
}

/// A percentage rounded half up: `0.745` -> `75`.
int roundedPercent(double fraction) => (fraction * 100).round();
