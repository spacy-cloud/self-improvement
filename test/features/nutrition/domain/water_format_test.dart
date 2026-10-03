import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  group('entries in ml', () {
    test('plain ml with a thousands dot', () {
      expect(formatWaterMl(250), '250 ml');
      expect(formatWaterMl(50), '50 ml');
      expect(formatWaterMl(999), '999 ml');
      expect(formatWaterMl(1250), '1.250 ml');
      expect(formatWaterMl(2000), '2.000 ml');
    });
  });

  group('totals in litres (up to two decimals, no unnecessary zeros)', () {
    test('the documented cases', () {
      expect(formatWaterLiters(250), '0,25 l');
      expect(formatWaterLiters(500), '0,5 l');
      expect(formatWaterLiters(1000), '1 l');
      expect(formatWaterLiters(1250), '1,25 l');
      expect(formatWaterLiters(1500), '1,5 l');
      expect(formatWaterLiters(2000), '2 l');
      expect(formatWaterLiters(2500), '2,5 l');
      expect(formatWaterLiters(10000), '10 l');
    });

    test('small and odd amounts', () {
      expect(formatWaterLiters(0), '0 l');
      expect(formatWaterLiters(50), '0,05 l');
      expect(formatWaterLiters(100), '0,1 l');
      expect(formatWaterLiters(1990), '1,99 l');
      expect(formatWaterLiters(2800), '2,8 l');
    });

    test('a remainder below 10 ml is not shown, never rounded up', () {
      expect(formatWaterLiters(1255), '1,25 l');
      expect(formatWaterLiters(999), '0,99 l');
      expect(formatWaterLiters(3), '0 l');
    });
  });

  group('percentages', () {
    test('are real percentages with a space before the sign', () {
      expect(formatWaterPercent(0), '0 %');
      expect(formatWaterPercent(75), '75 %');
      expect(formatWaterPercent(112), '112 %');
    });
  });

  group('messages', () {
    test('the snackbar texts', () {
      expect(waterAddedMessage(250), '250 ml hinzugefügt');
      expect(waterAddedMessage(1250), '1.250 ml hinzugefügt');
      expect(waterUpdatedMessage, 'Eintrag aktualisiert');
      expect(waterDeletedMessage, 'Eintrag gelöscht');
    });

    test('the goal message always says the change applies from tomorrow', () {
      expect(
        waterGoalSavedMessage(3000),
        'Tagesziel auf 3 l gesetzt. Es gilt ab morgen.',
      );
      expect(
        waterGoalSavedMessage(2750),
        'Tagesziel auf 2,75 l gesetzt. Es gilt ab morgen.',
      );
    });
  });

  group('progress label (text for screen readers and the card)', () {
    final day = LocalDate(2026, 10, 3);

    // The label only reads the total, so one entry with the whole amount is
    // enough (the amount is not validated in the domain model).
    WaterToday build(int ml, int? target) => buildWaterToday(
      date: day,
      entries: ml == 0
          ? const []
          : [
              WaterEntry(
                id: 'a',
                amountMl: ml,
                occurredAtUtc: DateTime.utc(2026, 10, 3, 7),
                localDate: day,
                timezoneId: 'Europe/Berlin',
                createdAtUtc: DateTime.utc(2026, 10, 3, 7),
                rowVersion: 1,
                gamificationEligible: true,
              ),
            ],
      targetMl: target,
    );

    test('without a target there is no goal claim', () {
      expect(
        waterProgressLabel(build(1250, null)),
        'Wasser heute: 1,25 l, kein Tagesziel aktiv.',
      );
    });

    test('below the target', () {
      expect(
        waterProgressLabel(build(1250, 2500)),
        'Wasser heute: 1,25 l von 2,5 l, 50 Prozent erreicht.',
      );
      expect(
        waterProgressLabel(build(0, 2500)),
        'Wasser heute: 0 l von 2,5 l, 0 Prozent erreicht.',
      );
    });

    test('at and above the target the goal is stated in words', () {
      expect(
        waterProgressLabel(build(2500, 2500)),
        'Wasser heute: 2,5 l von 2,5 l, 100 Prozent erreicht, '
        'Tagesziel erreicht.',
      );
      expect(
        waterProgressLabel(build(2800, 2500)),
        'Wasser heute: 2,8 l von 2,5 l, 112 Prozent erreicht, '
        'Tagesziel erreicht.',
      );
    });

    test('just below the target never says 100 percent', () {
      expect(
        waterProgressLabel(build(2490, 2500)),
        'Wasser heute: 2,49 l von 2,5 l, 99 Prozent erreicht.',
      );
    });
  });
}
