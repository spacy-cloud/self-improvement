import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/backup/backup_values.dart';

void main() {
  group('instants', () {
    test('format with millisecond precision, zero padding and Z', () {
      expect(
        BackupValues.formatInstant(DateTime.utc(2026, 1, 2, 3, 4, 5, 6)),
        '2026-01-02T03:04:05.006Z',
      );
      expect(
        BackupValues.formatInstant(DateTime.utc(2026, 12, 31, 23, 59, 59, 999)),
        '2026-12-31T23:59:59.999Z',
      );
      expect(
        BackupValues.formatInstant(DateTime.utc(2026)),
        '2026-01-01T00:00:00.000Z',
      );
    });

    test('formatting normalises a local DateTime to UTC and drops micros', () {
      final instant = DateTime.fromMicrosecondsSinceEpoch(
        DateTime.utc(2026, 5, 6, 7, 8, 9, 10).microsecondsSinceEpoch + 321,
        isUtc: true,
      );
      expect(BackupValues.formatInstant(instant), '2026-05-06T07:08:09.010Z');
    });

    test('parse is the exact inverse of format', () {
      final instant = DateTime.utc(2026, 10, 3, 8, 15, 30, 123);
      final parsed = BackupValues.tryParseInstant(
        BackupValues.formatInstant(instant),
      );
      expect(parsed, instant);
      expect(parsed!.isUtc, isTrue);
    });

    test('accepts the boundaries of a valid day', () {
      expect(
        BackupValues.tryParseInstant('2026-01-01T00:00:00.000Z'),
        DateTime.utc(2026),
      );
      expect(
        BackupValues.tryParseInstant('2024-02-29T23:59:59.999Z'),
        DateTime.utc(2024, 2, 29, 23, 59, 59, 999),
      );
    });

    for (final bad in const {
      'missing milliseconds': '2026-10-03T08:15:30Z',
      'two fractional digits': '2026-10-03T08:15:30.12Z',
      'six fractional digits': '2026-10-03T08:15:30.123456Z',
      'offset instead of Z': '2026-10-03T10:15:30.123+02:00',
      'lower case z': '2026-10-03T08:15:30.123z',
      'no zone': '2026-10-03T08:15:30.123',
      'space instead of T': '2026-10-03 08:15:30.123Z',
      'hour 24': '2026-10-03T24:00:00.000Z',
      'minute 60': '2026-10-03T08:60:00.000Z',
      'leap second 60': '2026-10-03T08:15:60.000Z',
      'February 30': '2026-02-30T08:15:30.000Z',
      'February 29 in a common year': '2026-02-29T08:15:30.000Z',
      'month 13': '2026-13-03T08:15:30.000Z',
      'day 0': '2026-10-00T08:15:30.000Z',
      'five digit year': '12026-10-03T08:15:30.000Z',
      'leading space': ' 2026-10-03T08:15:30.000Z',
      'trailing newline': '2026-10-03T08:15:30.000Z\n',
      'empty': '',
    }.entries) {
      test('rejects ${bad.key}', () {
        expect(BackupValues.tryParseInstant(bad.value), isNull);
      });
    }
  });

  group('uuid shape', () {
    test('accepts the canonical lower case form', () {
      expect(
        BackupValues.isUuid('123e4567-e89b-42d3-a456-426614174000'),
        isTrue,
      );
      expect(
        BackupValues.isUuid('00000000-0000-4000-8000-000000000001'),
        isTrue,
      );
    });

    for (final bad in const [
      '',
      'local',
      '123E4567-E89B-42D3-A456-426614174000',
      '123e4567e89b42d3a456426614174000',
      '123e4567-e89b-42d3-a456-42661417400',
      '123e4567-e89b-42d3-a456-4266141740000',
      '123e4567-e89b-42d3-a456-42661417400g',
      ' 123e4567-e89b-42d3-a456-426614174000',
      '{123e4567-e89b-42d3-a456-426614174000}',
    ]) {
      test('rejects "$bad"', () => expect(BackupValues.isUuid(bad), isFalse));
    }
  });

  group('text', () {
    test('counts code points like SQLite length(), not UTF-16 units', () {
      expect(BackupValues.characterCount('abc'), 3);
      expect(BackupValues.characterCount('äöüß'), 4);
      expect(BackupValues.characterCount('\u{1F600}'), 1);
      expect(BackupValues.characterCount('a\u{1F600}b'), 3);
      expect(BackupValues.characterCount(''), 0);
    });

    test('rejects NUL and unpaired surrogates, accepts the rest', () {
      expect(BackupValues.hasInvalidCharacters('a\u0000b'), isTrue);
      expect(BackupValues.hasInvalidCharacters('\u0000'), isTrue);
      expect(BackupValues.hasInvalidCharacters('\ud800'), isTrue);
      expect(BackupValues.hasInvalidCharacters('x\ud800'), isTrue);
      expect(BackupValues.hasInvalidCharacters('\udc00x'), isTrue);
      expect(BackupValues.hasInvalidCharacters('\ud800x'), isTrue);

      expect(BackupValues.hasInvalidCharacters(''), isFalse);
      expect(
        BackupValues.hasInvalidCharacters('Grüße \u{1F600} – ok'),
        isFalse,
      );
      expect(BackupValues.hasInvalidCharacters('zeile 1\nzeile 2\t'), isFalse);
    });
  });
}
