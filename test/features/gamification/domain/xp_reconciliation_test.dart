import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/features/gamification/domain/xp_award.dart';
import 'package:self_improvement/features/gamification/domain/xp_calculator.dart';
import 'package:self_improvement/features/gamification/domain/xp_facts.dart';
import 'package:self_improvement/features/gamification/domain/xp_reconciliation.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final day = LocalDate(2026, 10, 3);
  final profileStart = LocalDate(2026, 9, 1);

  XpAward waterAward(
    String id, {
    LocalDate? date,
    int points = 5,
    int ruleVersion = 1,
    String? sourceId,
    XpSource source = XpSource.water,
  }) => XpAward(
    key: 'water:$id',
    date: date ?? day,
    source: source,
    sourceId: sourceId ?? id,
    points: points,
    ruleVersion: ruleVersion,
  );

  /// Applies a reconciliation to a stored set, like the data layer does.
  List<XpAward> apply(Iterable<XpAward> stored, AwardReconciliation result) {
    final byKey = {for (final award in stored) award.key: award};
    for (final key in result.toDeleteKeys) {
      byKey.remove(key);
    }
    for (final award in result.toUpsert) {
      byKey[award.key] = award;
    }
    return byKey.values.toList();
  }

  group('reconcileAwards', () {
    test('nothing stored and nothing desired means nothing to do', () {
      final result = reconcileAwards(existing: const [], desired: const []);
      expect(result.isEmpty, isTrue);
      expect(result.toUpsert, isEmpty);
      expect(result.toDeleteKeys, isEmpty);
    });

    test('missing awards are inserted', () {
      final result = reconcileAwards(
        existing: const [],
        desired: [waterAward('a'), waterAward('b')],
      );
      expect(result.toUpsert, [waterAward('a'), waterAward('b')]);
      expect(result.toDeleteKeys, isEmpty);
      expect(result.isEmpty, isFalse);
    });

    test('awards that are no longer valid are deleted', () {
      final result = reconcileAwards(
        existing: [waterAward('a'), waterAward('b')],
        desired: [waterAward('a')],
      );
      expect(result.toDeleteKeys, ['water:b']);
      expect(result.toUpsert, isEmpty);
    });

    test('unchanged awards are left alone', () {
      final result = reconcileAwards(
        existing: [waterAward('a'), waterAward('b')],
        desired: [waterAward('b'), waterAward('a')],
      );
      expect(result.isEmpty, isTrue);
    });

    test('a changed award is updated, not deleted', () {
      for (final changed in [
        waterAward('a', points: 7),
        waterAward('a', date: day.addDays(1)),
        waterAward('a', ruleVersion: 2),
        waterAward('a', sourceId: 'other'),
        waterAward('a', source: XpSource.task),
      ]) {
        final result = reconcileAwards(
          existing: [waterAward('a')],
          desired: [changed],
        );
        expect(result.toUpsert, [changed], reason: '$changed');
        expect(result.toDeleteKeys, isEmpty, reason: '$changed');
      }
    });

    test('a moved record is updated under its key with the new date', () {
      final moved = waterAward('a', date: day.addDays(-1));
      final result = reconcileAwards(
        existing: [waterAward('a')],
        desired: [moved],
      );
      expect(result.toUpsert.single.date, day.addDays(-1));
      expect(result.toDeleteKeys, isEmpty);
    });

    test('inserts, updates and deletes are found together and sorted', () {
      final result = reconcileAwards(
        existing: [
          waterAward('keep'),
          waterAward('gone-b'),
          waterAward('change', points: 5),
          waterAward('gone-a'),
        ],
        desired: [
          waterAward('new-b'),
          waterAward('change', points: 6),
          waterAward('keep'),
          waterAward('new-a'),
        ],
      );
      expect(result.toUpsert.map((award) => award.key), [
        'water:change',
        'water:new-a',
        'water:new-b',
      ]);
      expect(result.toDeleteKeys, ['water:gone-a', 'water:gone-b']);
    });

    test('is independent of the order of the inputs', () {
      final existing = [
        waterAward('a'),
        waterAward('b'),
        waterAward('c', points: 1),
      ];
      final desired = [waterAward('c'), waterAward('d'), waterAward('a')];
      final forward = reconcileAwards(existing: existing, desired: desired);
      final backward = reconcileAwards(
        existing: existing.reversed,
        desired: desired.reversed,
      );
      expect(backward.toUpsert, forward.toUpsert);
      expect(backward.toDeleteKeys, forward.toDeleteKeys);
    });

    test('is idempotent: reconciling twice leaves nothing to do', () {
      final stored = [
        waterAward('a'),
        waterAward('gone'),
        waterAward('c', points: 1),
      ];
      final desired = [waterAward('a'), waterAward('c'), waterAward('new')];
      final first = reconcileAwards(existing: stored, desired: desired);
      expect(first.isEmpty, isFalse);
      final afterFirst = apply(stored, first);
      final second = reconcileAwards(existing: afterFirst, desired: desired);
      expect(second.isEmpty, isTrue);
      expect(afterFirst.map((award) => award.key).toSet(), {
        'water:a',
        'water:c',
        'water:new',
      });
    });

    test('the last occurrence of a duplicated desired key wins', () {
      final result = reconcileAwards(
        existing: const [],
        desired: [waterAward('a', points: 1), waterAward('a', points: 5)],
      );
      expect(result.toUpsert, [waterAward('a', points: 5)]);
    });

    test('desired awards are not removed because another day is stored', () {
      // The data layer only passes the stored awards of the affected dates.
      final result = reconcileAwards(
        existing: [waterAward('a', date: day.addDays(-1))],
        desired: [
          waterAward('a', date: day.addDays(-1)),
          waterAward('b'),
        ],
      );
      expect(result.toUpsert, [waterAward('b')]);
      expect(result.toDeleteKeys, isEmpty);
    });

    test('results cannot be modified afterwards', () {
      final result = reconcileAwards(
        existing: [waterAward('gone')],
        desired: [waterAward('new')],
      );
      expect(
        () => result.toUpsert.add(waterAward('x')),
        throwsUnsupportedError,
      );
      expect(result.toDeleteKeys.clear, throwsUnsupportedError);
    });
  });

  group('reconciling computed days', () {
    WaterXpFact water(String id, int minute) => WaterXpFact(
      id: id,
      occurredAtUtc: DateTime.utc(2026, 10, 3, 6, minute),
      createdAtUtc: DateTime.utc(2026, 10, 3, 6, minute),
      eligible: true,
      amountMl: 250,
    );

    List<XpAward> desiredFor(List<WaterXpFact> entries, {LocalDate? on}) =>
        computeDayAwards(
          XpDayFacts(date: on ?? day, water: entries),
          profileStart: profileStart,
        );

    int total(Iterable<XpAward> awards) =>
        awards.fold(0, (sum, award) => sum + award.points);

    test('a retry without changes creates no points', () {
      final entries = [for (var i = 1; i <= 3; i++) water('w$i', i)];
      final stored = apply(
        const [],
        reconcileAwards(existing: const [], desired: desiredFor(entries)),
      );
      expect(total(stored), 15);
      final retry = reconcileAwards(
        existing: stored,
        desired: desiredFor(entries),
      );
      expect(retry.isEmpty, isTrue);
    });

    test('a deleted entry is replaced by the next one, total stays 20', () {
      final entries = [for (var i = 1; i <= 5; i++) water('w$i', i)];
      var stored = apply(
        const [],
        reconcileAwards(existing: const [], desired: desiredFor(entries)),
      );
      expect(total(stored), 20);

      final remaining = entries.where((entry) => entry.id != 'w2').toList();
      final change = reconcileAwards(
        existing: stored,
        desired: desiredFor(remaining),
      );
      expect(change.toDeleteKeys, ['water:w2']);
      expect(change.toUpsert.map((award) => award.key), ['water:w5']);
      stored = apply(stored, change);
      expect(total(stored), 20, reason: 'no double award');
      expect(
        reconcileAwards(
          existing: stored,
          desired: desiredFor(remaining),
        ).isEmpty,
        isTrue,
      );
    });

    test('undoing every entry removes all awards', () {
      final entries = [for (var i = 1; i <= 2; i++) water('w$i', i)];
      final stored = apply(
        const [],
        reconcileAwards(existing: const [], desired: desiredFor(entries)),
      );
      final change = reconcileAwards(
        existing: stored,
        desired: desiredFor(const []),
      );
      expect(change.toUpsert, isEmpty);
      expect(change.toDeleteKeys, ['water:w1', 'water:w2']);
      expect(apply(stored, change), isEmpty);
    });

    test('moving an entry to another day recomputes both days', () {
      final yesterday = day.addDays(-1);
      final onDay = [for (var i = 1; i <= 4; i++) water('w$i', i)];
      final stored = [
        ...desiredFor(onDay),
        ...desiredFor(const [], on: yesterday),
      ];
      expect(total(stored), 20);

      // w1 moves to yesterday: both days are recomputed and reconciled.
      final movedDay = onDay.where((entry) => entry.id != 'w1').toList();
      final desired = [
        ...desiredFor(movedDay),
        ...desiredFor([water('w1', 1)], on: yesterday),
      ];
      final change = reconcileAwards(existing: stored, desired: desired);
      expect(change.toDeleteKeys, isEmpty);
      expect(change.toUpsert.map((award) => (award.key, award.date)), [
        ('water:w1', yesterday),
      ]);
      expect(total(apply(stored, change)), 20);
    });
  });
}
