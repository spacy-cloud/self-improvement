import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/dashboard/domain/motivation.dart';
import 'package:self_improvement/shared/local_date.dart';

/// The nine titles as ticket BS-121 lists them, in rotation order. The wording
/// is a default that may be changed; changing it means changing this table.
const Map<GoalsStanding, List<String>> _wording = <GoalsStanding, List<String>>{
  GoalsStanding.none: <String>[
    'Heute ist ein guter Tag, um anzufangen.',
    'Jeder Tag ist ein neuer Anfang.',
    'Ein Eintrag nach dem anderen.',
  ],
  GoalsStanding.partial: <String>[
    'Stark unterwegs!',
    'Kleine Schritte zählen.',
    'Bleib in deinem Tempo.',
  ],
  GoalsStanding.all: <String>[
    'Geschafft!',
    'Das war ein runder Tag.',
    'Heute hat alles geklappt.',
  ],
};

/// Pairs (reached, applicable) of every stand.
const Map<GoalsStanding, List<(int, int)>> _counts =
    <GoalsStanding, List<(int, int)>>{
      GoalsStanding.none: <(int, int)>[(0, 4), (0, 5), (0, 1)],
      GoalsStanding.partial: <(int, int)>[
        (1, 4),
        (2, 4),
        (3, 4),
        (1, 5),
        (4, 5),
      ],
      GoalsStanding.all: <(int, int)>[(4, 4), (5, 5), (1, 1), (6, 6)],
    };

String _title(LocalDate date, GoalsStanding standing, [int index = 0]) {
  final (fulfilled, applicable) = _counts[standing]![index];
  return motivationTextFor(date, fulfilled: fulfilled, applicable: applicable);
}

void main() {
  group('the stand of the goals (BS-121)', () {
    test('(C04) none, some and all goals reached', () {
      for (final entry in _counts.entries) {
        for (final (fulfilled, applicable) in entry.value) {
          expect(
            GoalsStanding.of(fulfilled: fulfilled, applicable: applicable),
            entry.key,
            reason: '$fulfilled of $applicable',
          );
        }
      }
    });

    test('(C04) a single goal is all goals once it is reached', () {
      expect(GoalsStanding.of(fulfilled: 1, applicable: 1), GoalsStanding.all);
      expect(GoalsStanding.of(fulfilled: 0, applicable: 1), GoalsStanding.none);
    });

    test('(C04) without an applicable goal nothing is reached', () {
      // The dashboard shows "Noch keine Tagesziele" then, no ring and no title.
      expect(GoalsStanding.of(fulfilled: 0, applicable: 0), GoalsStanding.none);
      expect(GoalsStanding.of(fulfilled: 2, applicable: 0), GoalsStanding.none);
      expect(
        GoalsStanding.of(fulfilled: 0, applicable: -1),
        GoalsStanding.none,
      );
    });

    test('(C04) numbers outside the valid range stay inside the stands', () {
      expect(
        GoalsStanding.of(fulfilled: -1, applicable: 4),
        GoalsStanding.none,
      );
      expect(
        GoalsStanding.of(fulfilled: 5, applicable: 4),
        GoalsStanding.all,
        reason: 'clamps like the ring',
      );
    });
  });

  group('the titles (BS-121)', () {
    test('(C04) three neutral texts per stand, all nine different', () {
      final all = <String>[
        for (final standing in GoalsStanding.values) ...<String>[
          ...motivationTextsOf(standing),
        ],
      ];
      for (final standing in GoalsStanding.values) {
        expect(
          motivationTextsOf(standing),
          hasLength(3),
          reason: standing.name,
        );
      }
      expect(
        all.toSet(),
        hasLength(9),
        reason: 'no text twice, none shared between two stands',
      );
      for (final text in all) {
        expect(text, isNotEmpty);
        expect(text.toLowerCase(), isNot(contains('abnehm')));
        expect(text.toLowerCase(), isNot(contains('gewicht')));
      }
    });

    test('(C04) the wording is the one of the ticket', () {
      for (final standing in GoalsStanding.values) {
        expect(
          motivationTextsOf(standing),
          _wording[standing],
          reason: standing.name,
        );
      }
    });

    test('(C04) the text follows dayOfYear % 3 inside the list of the stand', () {
      // 3 October 2026 is day 276 of the year and 276 % 3 == 0: the first text.
      final start = LocalDate(2026, 10, 3);
      expect(start.dayOfYear, 276);
      for (final standing in GoalsStanding.values) {
        final texts = _wording[standing]!;
        expect(_title(start, standing), texts[0], reason: standing.name);
        expect(
          _title(start.addDays(1), standing),
          texts[1],
          reason: '${standing.name}, 4 October (day 277)',
        );
        expect(
          _title(start.addDays(2), standing),
          texts[2],
          reason: '${standing.name}, 5 October (day 278)',
        );
        expect(
          _title(start.addDays(3), standing),
          texts[0],
          reason: '${standing.name}, 6 October (day 279)',
        );
      }
    });

    test('(C04) the text repeats every three days and three days show all '
        'three texts of a stand', () {
      final start = LocalDate(2026, 10, 3);
      for (final standing in GoalsStanding.values) {
        for (var offset = 0; offset < 12; offset++) {
          expect(
            _title(start.addDays(offset), standing),
            _title(start.addDays(offset + 3), standing),
            reason: '${standing.name}, offset $offset',
          );
        }
        final shown = <String>{
          for (var i = 0; i < 3; i++) _title(start.addDays(i), standing),
        };
        expect(shown, hasLength(3), reason: standing.name);
      }
    });

    test('(C04) the rotation is the day of the year: it restarts with the '
        'year', () {
      final lastDay = LocalDate(2026, 12, 31);
      final firstDay = LocalDate(2027, 1, 1);
      expect(lastDay.dayOfYear, 365);
      expect(firstDay.dayOfYear, 1);
      final texts = _wording[GoalsStanding.partial]!;
      expect(_title(lastDay, GoalsStanding.partial), texts[2]);
      expect(_title(firstDay, GoalsStanding.partial), texts[1]);
    });

    test('(C04) no title of another stand shows on any day of the year', () {
      for (final year in const <int>[2026, 2028]) {
        var date = LocalDate(year, 1, 1);
        while (date.year == year) {
          for (final entry in _counts.entries) {
            for (final (fulfilled, applicable) in entry.value) {
              final text = motivationTextFor(
                date,
                fulfilled: fulfilled,
                applicable: applicable,
              );
              final reason = '$date, $fulfilled of $applicable';
              expect(_wording[entry.key], contains(text), reason: reason);
              for (final other in GoalsStanding.values) {
                if (other != entry.key) {
                  expect(
                    _wording[other],
                    isNot(contains(text)),
                    reason: '$reason: a text of "${other.name}"',
                  );
                }
              }
            }
          }
          date = date.addDays(1);
        }
      }
    });

    test('(C04) it is stable within a day and does not depend on time', () {
      final date = LocalDate(2026, 1, 1);
      expect(date.dayOfYear, 1);
      expect(
        _title(date, GoalsStanding.none),
        _wording[GoalsStanding.none]![1],
      );
      expect(
        _title(LocalDate(2026, 1, 1), GoalsStanding.none),
        _title(date, GoalsStanding.none),
      );
    });

    test('(C04) the same day shows another title when the stand changes', () {
      // The bug of BS-121: "Heute ist ein guter Tag, um anzufangen." stood next
      // to "Du hast heute alle Tagesziele erreicht.".
      final day = LocalDate(2026, 10, 3);
      expect(
        motivationTextFor(day, fulfilled: 0, applicable: 5),
        'Heute ist ein guter Tag, um anzufangen.',
      );
      expect(
        motivationTextFor(day, fulfilled: 2, applicable: 5),
        'Stark unterwegs!',
      );
      expect(motivationTextFor(day, fulfilled: 5, applicable: 5), 'Geschafft!');
      expect(motivationTextFor(day, fulfilled: 1, applicable: 1), 'Geschafft!');
    });
  });
}
