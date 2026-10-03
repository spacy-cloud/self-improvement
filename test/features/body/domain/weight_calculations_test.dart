import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/body/domain/weight_calculations.dart';
import 'package:self_improvement/shared/local_date.dart';

WeightSample sample(String id, String isoDate, int hour, int grams) {
  final date = LocalDate.parse(isoDate);
  return WeightSample(
    id: id,
    occurredAtUtc: DateTime.utc(date.year, date.month, date.day, hour),
    localDate: date,
    grams: grams,
  );
}

void main() {
  final today = LocalDate(2026, 10, 3);

  group('current weight and deltas (AT08)', () {
    test('no measurements: nothing', () {
      expect(currentWeight(const []), isNull);
      expect(weekDelta(const [], today), isNull);
    });

    test(
      'the latest measurement by time is current, regardless of input order',
      () {
        final samples = [
          sample('b', '2026-10-02', 7, 71800),
          sample('c', '2026-10-03', 7, 71500),
          sample('a', '2026-10-01', 7, 72000),
        ];
        expect(currentWeight(samples)!.id, 'c');
        expect(chronological(samples).map((s) => s.id), ['a', 'b', 'c']);
      },
    );

    test('equal times break ties by id', () {
      final samples = [
        sample('a', '2026-10-03', 7, 71000),
        sample('b', '2026-10-03', 7, 72000),
      ];
      expect(currentWeight(samples)!.id, 'b');
    });

    test('detail delta is current minus the previous measurement', () {
      final samples = [
        sample('prev', '2026-10-02', 7, 71800),
        sample('cur', '2026-10-03', 7, 71500),
      ];
      expect(
        deltaToPrevious(samples, 'cur'),
        -300,
        reason: '71,5 - 71,8 = -0,3 kg',
      );
      expect(
        deltaToPrevious(samples, 'prev'),
        isNull,
        reason: 'no predecessor',
      );
      expect(deltaToPrevious(samples, 'missing'), isNull);
    });

    test('the preview delta of a new value uses the latest earlier entry', () {
      final samples = [
        sample('old', '2026-10-01', 7, 72000),
        sample('prev', '2026-10-02', 7, 71800),
      ];
      final when = DateTime.utc(2026, 10, 3, 7);
      expect(
        deltaBefore(samples, grams: 71500, occurredAtUtc: when),
        -300,
        reason: '71,5 - 71,8',
      );
      expect(
        deltaBefore(samples, grams: 72500, occurredAtUtc: when),
        700,
        reason: 'a gain stays signed and neutral',
      );
      expect(deltaBefore(samples, grams: 71800, occurredAtUtc: when), 0);
    });

    test('the preview delta ignores later entries and the edited one', () {
      final samples = [
        sample('a', '2026-10-01', 7, 72000),
        sample('edited', '2026-10-02', 7, 71800),
        sample('later', '2026-10-03', 7, 71000),
      ];
      final at = DateTime.utc(2026, 10, 2, 7);
      expect(
        deltaBefore(
          samples,
          grams: 71500,
          occurredAtUtc: at,
          excludeId: 'edited',
        ),
        -500,
        reason: 'compared with the entry before the edited one',
      );
      expect(
        deltaBefore(
          samples,
          grams: 72500,
          occurredAtUtc: DateTime.utc(2026, 10, 1, 7),
          excludeId: 'a',
        ),
        isNull,
        reason: 'nothing earlier than the first measurement',
      );
      expect(
        deltaBefore(
          const [],
          grams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 1),
        ),
        isNull,
      );
    });

    test('all deltas at once equal the single delta of each entry', () {
      final samples = [
        sample('c', '2026-10-03', 7, 71500),
        sample('a', '2026-10-01', 7, 72000),
        sample('b', '2026-10-02', 7, 71800),
      ];
      final all = deltasToPrevious(samples);
      expect(all, {'b': -200, 'c': -300});
      for (final id in ['a', 'b', 'c']) {
        expect(all[id], deltaToPrevious(samples, id));
      }
      expect(deltasToPrevious(const []), isEmpty);
    });

    test('a single measurement has no comparison', () {
      expect(
        deltaToPrevious([sample('a', '2026-10-03', 7, 71500)], 'a'),
        isNull,
      );
    });

    test('week comparison uses the latest measurement on or before today - 7', () {
      final samples = [
        sample('old', '2026-09-25', 7, 73000),
        sample('anchor', '2026-09-26', 18, 72500),
        sample('newer', '2026-09-30', 7, 72000),
        sample('cur', '2026-10-03', 7, 71500),
      ];
      // today - 7 = 2026-09-26: the anchor is the latest one dated <= that day.
      expect(weekDelta(samples, today), 71500 - 72500);
    });

    test('week comparison boundary: day -7 counts, day -6 does not', () {
      final onBoundary = [
        sample('a', '2026-09-26', 7, 72000),
        sample('cur', '2026-10-03', 7, 71500),
      ];
      expect(weekDelta(onBoundary, today), -500);
      final tooRecent = [
        sample('a', '2026-09-27', 7, 72000),
        sample('cur', '2026-10-03', 7, 71500),
      ];
      expect(
        weekDelta(tooRecent, today),
        isNull,
        reason: 'Noch kein Wochenvergleich',
      );
    });
  });

  group('chart points: last entry per day, no artificial zeros (AT08)', () {
    final samples = [
      sample('a', '2026-09-20', 7, 73000),
      sample('b', '2026-10-01', 7, 72000),
      sample('c', '2026-10-01', 19, 72200),
      sample('d', '2026-10-03', 7, 71500),
    ];

    test('0 measurements: no points', () {
      expect(dailyPoints(const [], today, 7), isEmpty);
    });

    test('1 measurement: exactly one point', () {
      final points = dailyPoints(
        [sample('x', '2026-10-03', 7, 71500)],
        today,
        7,
      );
      expect(points, hasLength(1));
      expect(points.single.grams, 71500);
    });

    test('several measurements on one day yield the last one', () {
      final points = dailyPoints(samples, today, 7);
      expect(points.map((p) => (p.date.toIso(), p.grams)).toList(), [
        ('2026-10-01', 72200),
        ('2026-10-03', 71500),
      ]);
    });

    test('window is the last N local days inclusive of today', () {
      // 7 days: 2026-09-27 .. 2026-10-03.
      expect(dailyPoints(samples, today, 7).map((p) => p.date.toIso()), [
        '2026-10-01',
        '2026-10-03',
      ]);
      final onFirstDay = [sample('f', '2026-09-27', 7, 70000)];
      expect(dailyPoints(onFirstDay, today, 7), hasLength(1));
      final justOutside = [sample('g', '2026-09-26', 7, 70000)];
      expect(dailyPoints(justOutside, today, 7), isEmpty);
      // 30 days include 2026-09-20 (14 days back) too.
      expect(dailyPoints(samples, today, 30).first.date.toIso(), '2026-09-20');
      // 90 days: 2026-07-06 .. 2026-10-03.
      expect(
        dailyPoints([sample('h', '2026-07-06', 7, 70000)], today, 90),
        hasLength(1),
      );
      expect(
        dailyPoints([sample('i', '2026-07-05', 7, 70000)], today, 90),
        isEmpty,
      );
    });

    test('future-dated samples are ignored by the window', () {
      expect(
        dailyPoints([sample('f', '2026-10-04', 7, 70000)], today, 7),
        isEmpty,
      );
    });
  });

  group('goal progress and remaining distance (AT09)', () {
    test('loss: start 74,0 target 68,0 current 71,5', () {
      final goal = weightGoal(
        startGrams: 74000,
        targetGrams: 68000,
        currentGrams: 71500,
      )!;
      expect(goal.progress, closeTo(0.4167, 0.0001));
      expect(goal.remainingGrams, 3500);
      expect(goal.reached, isFalse);
    });

    test('gain: start 60,0 target 65,0 current 62,5', () {
      final goal = weightGoal(
        startGrams: 60000,
        targetGrams: 65000,
        currentGrams: 62500,
      )!;
      expect(goal.progress, closeTo(0.5, 1e-9));
      expect(goal.remainingGrams, 2500);
      expect(goal.reached, isFalse);
    });

    test('reached and exceeded in the chosen direction: remaining is 0', () {
      final exactLoss = weightGoal(
        startGrams: 74000,
        targetGrams: 68000,
        currentGrams: 68000,
      )!;
      expect(exactLoss.reached, isTrue);
      expect(exactLoss.remainingGrams, 0);
      expect(exactLoss.progress, 1);
      final passedLoss = weightGoal(
        startGrams: 74000,
        targetGrams: 68000,
        currentGrams: 66000,
      )!;
      expect(passedLoss.reached, isTrue);
      expect(
        passedLoss.remainingGrams,
        0,
        reason: 'never a negative remainder',
      );
      expect(passedLoss.progress, 1);
      final passedGain = weightGoal(
        startGrams: 60000,
        targetGrams: 65000,
        currentGrams: 66000,
      )!;
      expect(passedGain.reached, isTrue);
      expect(passedGain.remainingGrams, 0);
    });

    test(
      'moving away from the goal clamps progress to 0 but keeps the distance',
      () {
        final away = weightGoal(
          startGrams: 74000,
          targetGrams: 68000,
          currentGrams: 76000,
        )!;
        expect(away.progress, 0);
        expect(away.reached, isFalse);
        expect(away.remainingGrams, 8000);
        final awayGain = weightGoal(
          startGrams: 60000,
          targetGrams: 65000,
          currentGrams: 58000,
        )!;
        expect(awayGain.progress, 0);
        expect(awayGain.remainingGrams, 7000);
      },
    );

    test('start equals target: progress 1 only when current equals target', () {
      final equal = weightGoal(
        startGrams: 70000,
        targetGrams: 70000,
        currentGrams: 70000,
      )!;
      expect(equal.progress, 1);
      expect(equal.reached, isTrue);
      expect(equal.remainingGrams, 0);
      final off = weightGoal(
        startGrams: 70000,
        targetGrams: 70000,
        currentGrams: 71000,
      )!;
      expect(off.progress, 0);
      expect(off.reached, isFalse);
      expect(off.remainingGrams, 1000);
    });

    test('a missing value hides the goal', () {
      expect(
        weightGoal(startGrams: null, targetGrams: 68000, currentGrams: 71000),
        isNull,
      );
      expect(
        weightGoal(startGrams: 74000, targetGrams: null, currentGrams: 71000),
        isNull,
      );
      expect(
        weightGoal(startGrams: 74000, targetGrams: 68000, currentGrams: null),
        isNull,
      );
    });
  });

  group('BMI (neutral number only)', () {
    test('needs height, age and weight', () {
      expect(
        calculateBmi(heightCm: null, ageYears: 30, weightGrams: 71500),
        isNull,
      );
      expect(
        calculateBmi(heightCm: 175, ageYears: null, weightGrams: 71500),
        isNull,
      );
      expect(
        calculateBmi(heightCm: 175, ageYears: 30, weightGrams: null),
        isNull,
      );
    });

    test('is kg / m^2 with one decimal, rounded half up', () {
      expect(
        calculateBmi(heightCm: 175, ageYears: 30, weightGrams: 71500)!.tenths,
        233,
      );
      expect(
        calculateBmi(heightCm: 180, ageYears: 30, weightGrams: 81000)!.tenths,
        250,
      );
      expect(
        calculateBmi(heightCm: 160, ageYears: 40, weightGrams: 64000)!.tenths,
        250,
      );
      // 70,0 kg at 170 cm = 24.2214 -> 24,2; 72,0 kg at 170 cm = 24.9135 -> 24,9.
      expect(
        calculateBmi(heightCm: 170, ageYears: 40, weightGrams: 70000)!.tenths,
        242,
      );
      expect(
        calculateBmi(heightCm: 170, ageYears: 40, weightGrams: 72000)!.tenths,
        249,
      );
    });

    test('adults only and plausible heights', () {
      expect(
        calculateBmi(heightCm: 175, ageYears: 17, weightGrams: 70000),
        isNull,
      );
      expect(
        calculateBmi(heightCm: 175, ageYears: 18, weightGrams: 70000),
        isNotNull,
      );
      expect(
        calculateBmi(heightCm: 175, ageYears: 121, weightGrams: 70000),
        isNull,
      );
      expect(
        calculateBmi(heightCm: 99, ageYears: 30, weightGrams: 70000),
        isNull,
      );
      expect(
        calculateBmi(heightCm: 251, ageYears: 30, weightGrams: 70000),
        isNull,
      );
    });
  });
}
