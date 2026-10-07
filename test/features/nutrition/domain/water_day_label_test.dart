import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/nutrition/domain/water_entry.dart';
import 'package:self_improvement/features/nutrition/domain/water_format.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/nutrition/presentation/water_past_day_card.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The words of the water card for a day that is not today (BS-93): the same
/// states as the live card, said about "diesem Tag", and a day without an
/// entry reads as that and never as zero.
void main() {
  final day = LocalDate(2026, 10, 1);

  WaterEntry entry(String id, int ml) => WaterEntry(
    id: id,
    amountMl: ml,
    occurredAtUtc: DateTime.utc(2026, 10, 1, 8),
    localDate: day,
    timezoneId: 'Europe/Berlin',
    createdAtUtc: DateTime.utc(2026, 10, 1, 8),
    rowVersion: 1,
    gamificationEligible: true,
  );

  WaterToday model(List<int> amounts, {int? target}) => buildWaterToday(
    date: day,
    entries: <WaterEntry>[
      for (var i = 0; i < amounts.length; i++) entry('e$i', amounts[i]),
    ],
    targetMl: target,
  );

  group('the spoken label (BS-93, AT34)', () {
    test('(BS-93, AT34) below the target', () {
      expect(
        waterDayProgressLabel(model(<int>[1000, 500], target: 2500)),
        'Wasser an diesem Tag: 1,5 l von 2,5 l, 60 Prozent erreicht.',
      );
    });

    test('(BS-93, AT34) at or above the target the goal is named', () {
      expect(
        waterDayProgressLabel(model(<int>[2000, 600], target: 2500)),
        'Wasser an diesem Tag: 2,6 l von 2,5 l, 104 Prozent erreicht, '
        'Tagesziel erreicht.',
      );
    });

    test('(BS-93, AT34) without a target there is no percentage', () {
      expect(
        waterDayProgressLabel(model(<int>[1250])),
        'Wasser an diesem Tag: 1,25 l, kein Tagesziel.',
      );
    });

    test('(BS-93, AT34) a day without an entry says "nichts eingetragen" and '
        'names the target of that day, never zero', () {
      expect(
        waterDayProgressLabel(model(<int>[], target: 2500)),
        'Wasser an diesem Tag: nichts eingetragen, Tagesziel 2,5 l.',
      );
      expect(
        waterDayProgressLabel(model(<int>[])),
        'Wasser an diesem Tag: nichts eingetragen, kein Tagesziel.',
      );
      expect(
        waterDayProgressLabel(model(<int>[], target: 2500)),
        isNot(contains('0')),
      );
    });

    test('(BS-93) no word of the label speaks of "heute"', () {
      for (final water in <WaterToday>[
        model(<int>[500], target: 2500),
        model(<int>[3000], target: 2500),
        model(<int>[], target: 2500),
        model(<int>[500]),
      ]) {
        expect(waterDayProgressLabel(water), isNot(contains('heute')));
      }
    });
  });

  group('the line under the bar (BS-93)', () {
    test('(BS-93) percentage, goal reached, reached above the target, no '
        'target, nothing entered', () {
      expect(
        waterDaySubtitle(model(<int>[1500], target: 2500)),
        '60 % erreicht',
      );
      expect(
        waterDaySubtitle(model(<int>[2500], target: 2500)),
        'Tagesziel erreicht',
      );
      expect(
        waterDaySubtitle(model(<int>[2000, 600], target: 2500)),
        'Tagesziel erreicht · 104 %',
      );
      expect(
        waterDaySubtitle(model(<int>[500])),
        'Kein Tagesziel an diesem Tag',
      );
      expect(
        waterDaySubtitle(model(<int>[], target: 2500)),
        'Nichts eingetragen',
      );
    });
  });
}
