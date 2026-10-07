import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/features/body/steps/domain/step_day.dart';
import 'package:self_improvement/features/dashboard/domain/goals_day.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_overview_card.dart';
import 'package:self_improvement/features/focus/domain/workout_day_mark.dart';
import 'package:self_improvement/features/focus/domain/workout_week.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/tasks/domain/habit_icon.dart';
import 'package:self_improvement/shared/local_date.dart';

// BS-103: the model of "Ziele heute" (pure Dart): the numbers are the numbers
// of the day ring, the rows follow the units and percentage rules of the app,
// and the weekly workout goal stays apart.

final LocalDate _today = LocalDate(2026, 10, 3);
final LocalDate _past = LocalDate(2026, 9, 12);

GoalProgress _goal(
  GoalType type, {
  int? current = 0,
  bool reached = false,
  bool applicable = true,
  int? target,
}) => GoalProgress(
  goalKey: type.key,
  module: type.module,
  target: target ?? type.resolveTarget(null),
  applicable: applicable,
  fulfilled: applicable && reached,
  current: current,
);

GoalProgress _habit(String id, {bool checked = false}) => GoalProgress(
  goalKey: habitGoalKey(id),
  module: ModuleId.tasks,
  target: null,
  applicable: true,
  fulfilled: checked,
  current: checked ? 1 : 0,
);

DayStatus _status(List<GoalProgress> goals, {LocalDate? date}) =>
    DayStatus(date: date ?? _today, goals: goals);

GoalsDay _build(
  List<GoalProgress> goals, {
  LocalDate? date,
  List<GoalHabit> habits = const <GoalHabit>[],
  WorkoutDayOutcome? outcome,
  WorkoutWeekSummary? week,
}) => buildGoalsDay(
  status: _status(goals, date: date),
  today: _today,
  habits: habits,
  workoutOutcome: outcome,
  week: week,
);

GoalsDayRow _only(GoalProgress goal, {LocalDate? date}) =>
    _build(<GoalProgress>[goal], date: date).rows.single;

WorkoutWeekSummary _week(int count, {int target = 3}) => WorkoutWeekSummary(
  weekStart: _today.startOfWeek,
  entryCount: count,
  totalMinutes: count * 45,
  weeklyTarget: target,
);

void main() {
  group('the numbers are the numbers of the day ring (BS-103, C04)', () {
    // The same day status the ring counts, in five stands.
    final stands = <String, List<GoalProgress>>{
      'nothing reached': <GoalProgress>[
        _goal(GoalType.water),
        _goal(GoalType.steps),
        _goal(GoalType.focusMinutes),
        _goal(GoalType.weightEntry),
        _goal(GoalType.taskCompletion),
      ],
      'some reached': <GoalProgress>[
        _goal(GoalType.water, current: 1500),
        _goal(GoalType.steps, current: 10000, reached: true),
        _goal(GoalType.focusMinutes, current: 25, reached: true),
        _goal(GoalType.weightEntry),
        _goal(GoalType.taskCompletion),
      ],
      'all reached': <GoalProgress>[
        _goal(GoalType.water, current: 2500, reached: true),
        _goal(GoalType.steps, current: 10000, reached: true),
        _goal(GoalType.weightEntry, current: 1, reached: true),
      ],
      'a single goal': <GoalProgress>[
        _goal(GoalType.water, current: 2500, reached: true),
      ],
      'with habits': <GoalProgress>[
        _goal(GoalType.taskCompletion, current: 1, reached: true),
        _habit('a', checked: true),
        _habit('b'),
        _habit('c'),
      ],
    };
    for (final entry in stands.entries) {
      test('${entry.key}: ring and rows add up to the same x of y', () {
        final status = _status(entry.value);
        final day = buildGoalsDay(status: status, today: _today);
        expect(day.fulfilled, status.fulfilledCount);
        expect(day.applicable, status.applicableCount);
        expect(day.rows, hasLength(status.applicableCount));
        expect(
          day.rows.where((row) => row.isReached),
          hasLength(status.fulfilledCount),
        );
      });
    }

    test('a goal that does not apply is neither listed nor counted', () {
      final day = _build(<GoalProgress>[
        _goal(GoalType.water, current: 2500, reached: true),
        _goal(GoalType.steps, applicable: false),
        _goal(GoalType.workoutDaily, applicable: false),
      ]);
      expect(day.applicable, 1);
      expect(day.rows.map((row) => row.type), <GoalType?>[GoalType.water]);
    });

    test('without an applicable goal the day has no goals and no ring', () {
      final day = _build(<GoalProgress>[
        _goal(GoalType.water, applicable: false),
      ]);
      expect(day.hasGoals, isFalse);
      expect(day.rows, isEmpty);
      final none = GoalsDay.none(date: _today, isToday: true);
      expect(none.hasGoals, isFalse);
      expect(none.applicable, 0);
    });

    test(
      'whether a row is reached comes from the status, not from the words',
      () {
        // The status says reached although the facts of the other sources lag:
        // the row follows the status, which is what the ring counts.
        final row = _only(
          _goal(GoalType.workoutDaily, current: 1, reached: true),
        );
        expect(row.isReached, isTrue);
        final open = _only(_goal(GoalType.workoutDaily, current: 0));
        expect(open.isReached, isFalse);
      },
    );

    test('every daily goal type gets a row', () {
      for (final type in GoalType.dailyTypes) {
        final day = _build(<GoalProgress>[_goal(type)]);
        expect(day.rows, hasLength(1), reason: type.key);
        expect(day.rows.single.type, type);
        expect(day.rows.single.goalKey, type.key);
        expect(day.rows.single.title, isNotEmpty);
      }
    });
  });

  group('units and percentages follow the rules of the app (BS-103)', () {
    test('water in litres: stand, target and percent', () {
      final row = _only(_goal(GoalType.water, current: 1500));
      expect(row.title, 'Wasser');
      expect(row.detail, '1,5 von 2,5 l · 60 %');
      expect(row.status, GoalRowStatus.open);
      expect(row.fraction, closeTo(0.6, 1e-9));
      expect(row.spoken, 'Wasser, 1,5 von 2,5 Litern, 60 Prozent, noch offen');
    });

    test('water at 0 and with a target of one litre', () {
      expect(
        _only(_goal(GoalType.water, current: 0)).detail,
        '0 von 2,5 l · 0 %',
      );
      final one = _only(_goal(GoalType.water, current: 250, target: 1000));
      expect(one.detail, '0,25 von 1 l · 25 %');
      expect(one.spoken, contains('von 1 Liter,'));
    });

    test('water reached shows the real total, the bar stays at the end', () {
      final row = _only(_goal(GoalType.water, current: 2800, reached: true));
      expect(row.detail, '2,8 von 2,5 l · 112 %');
      expect(row.status, GoalRowStatus.reached);
      expect(row.fraction, 1);
      expect(row.spoken, endsWith('112 Prozent, erreicht'));
    });

    test('steps with the thousands dot', () {
      final row = _only(_goal(GoalType.steps, current: 7450));
      expect(row.detail, '7.450 von 10.000 · 75 %');
      expect(
        row.spoken,
        '${row.title}, 7.450 von 10.000 Schritten, 75 Prozent, noch offen',
      );
      expect(row.fraction, closeTo(0.745, 1e-9));
    });

    test('a recorded 0 is a value, no record is not', () {
      final zero = _only(_goal(GoalType.steps, current: 0));
      expect(zero.detail, '0 von 10.000 · 0 %');
      final none = _only(_goal(GoalType.steps, current: null));
      expect(none.detail, 'Noch keine Schritte eingetragen');
      expect(none.fraction, 0);
      expect(none.status, GoalRowStatus.open);
      expect(none.detail, isNot(contains('%')));
    });

    test('focus in minutes', () {
      final row = _only(_goal(GoalType.focusMinutes, current: 45, target: 60));
      expect(row.detail, '45 von 60 Min. · 75 %');
      expect(row.spoken, 'Fokus, 45 von 60 Minuten, 75 Prozent, noch offen');
    });

    test('weight: the number of entries is the stand', () {
      expect(
        _only(_goal(GoalType.weightEntry, current: 0)).detail,
        'Noch nicht gewogen',
      );
      expect(
        _only(_goal(GoalType.weightEntry, current: 1, reached: true)).detail,
        'Heute gewogen',
      );
      expect(
        _only(_goal(GoalType.weightEntry, current: 3, reached: true)).detail,
        'Heute 3-mal gewogen',
      );
    });

    test('tasks: singular and plural', () {
      expect(
        _only(_goal(GoalType.taskCompletion, current: 0)).detail,
        'Noch keine Aufgabe erledigt',
      );
      expect(
        _only(_goal(GoalType.taskCompletion, current: 1, reached: true)).detail,
        '1 Aufgabe erledigt',
      );
      expect(
        _only(_goal(GoalType.taskCompletion, current: 2, reached: true)).detail,
        '2 Aufgaben erledigt',
      );
    });

    test('the bar of a goal that is done or not is empty or full', () {
      expect(_only(_goal(GoalType.weightEntry, current: 0)).fraction, 0);
      expect(
        _only(_goal(GoalType.weightEntry, current: 1, reached: true)).fraction,
        1,
      );
    });

    test('never 100 % before the target, the real value after it', () {
      // Property over the whole range: 100 and more exactly when reached.
      for (final target in <int>[5, 60, 2500, 10000]) {
        for (var current = 0; current <= target * 12 ~/ 10; current++) {
          final percent = goalPercent(current: current, target: target);
          expect(
            percent >= 100,
            current >= target,
            reason: '$current of $target shows $percent %',
          );
          expect(percent <= 99 || current >= target, isTrue);
        }
      }
      expect(goalPercent(current: 9950, target: 10000), 99);
      expect(goalPercent(current: 2490, target: 2500), 99);
      expect(goalPercent(current: 2800, target: 2500), 112);
      expect(goalPercent(current: 745, target: 1000), 75, reason: 'half up');
    });

    test('the same percentage as the water and the steps screens', () {
      for (final target in <int>[250, 1500, 2500, 4999, 10000]) {
        for (var total = 0; total <= target * 2; total += 7) {
          final expected = waterPercent(totalMl: total, targetMl: target);
          expect(
            goalPercent(current: total, target: target),
            expected,
            reason: '$total of $target ml',
          );
          expect(
            goalPercent(current: total, target: target),
            StepsProgress(steps: total, target: target).percent,
            reason: '$total of $target steps',
          );
        }
      }
    });

    test('the text of a row never says 100 % before the goal is reached', () {
      for (var ml = 0; ml <= 3000; ml += 10) {
        final row = _only(
          _goal(GoalType.water, current: ml, reached: ml >= 2500),
        );
        if (ml < 2500) {
          expect(row.detail, isNot(contains('100 %')), reason: '$ml ml');
          expect(row.spoken, isNot(contains('100 Prozent')), reason: '$ml ml');
        }
        if (row.detail.contains('100 %')) {
          expect(ml, greaterThanOrEqualTo(2500));
        }
      }
    });
  });

  group('"Workout heute": its own states (BS-103, BS-99)', () {
    GoalsDayRow workout({
      required bool reached,
      int current = 0,
      WorkoutDayOutcome? outcome,
    }) => _build(<GoalProgress>[
      _goal(GoalType.workoutDaily, current: current, reached: reached),
    ], outcome: outcome).rows.single;

    test('open', () {
      final row = workout(reached: false, outcome: WorkoutDayOutcome.open);
      expect(row.status, GoalRowStatus.open);
      expect(row.detail, 'Noch kein Training eingetragen');
      expect(row.fraction, 0);
      expect(row.title, 'Workout heute');
    });

    test('a workout: reached, with the number of workouts', () {
      final one = workout(
        reached: true,
        current: 1,
        outcome: WorkoutDayOutcome.trained,
      );
      expect(one.status, GoalRowStatus.reached);
      expect(one.detail, '1 Training eingetragen');
      expect(one.fraction, 1);
      final two = workout(
        reached: true,
        current: 2,
        outcome: WorkoutDayOutcome.trained,
      );
      expect(two.detail, '2 Trainings eingetragen');
    });

    test('a rest day counts as reached, as its own state, without a bar', () {
      final row = workout(
        reached: true,
        current: 1,
        outcome: WorkoutDayOutcome.rest,
      );
      expect(row.status, GoalRowStatus.rest);
      expect(row.isReached, isTrue);
      expect(row.detail, 'Ruhetag eingetragen · keine XP, Streak bleibt');
      expect(row.fraction, isNull);
      expect(row.spoken, contains('Ruhetag, zählt als erreicht'));
      expect(row.spoken, contains('keine XP'));
    });

    test(
      'a skipped day counts as reached, as its own state, without a bar',
      () {
        final row = workout(
          reached: true,
          current: 1,
          outcome: WorkoutDayOutcome.skipped,
        );
        expect(row.status, GoalRowStatus.skipped);
        expect(row.isReached, isTrue);
        expect(row.detail, 'Training übersprungen · keine XP, Streak bleibt');
        expect(row.fraction, isNull);
        expect(row.spoken, contains('übersprungen, zählt als erreicht'));
      },
    );

    test('a reached goal of an unknown kind stays reached and says so', () {
      final row = workout(reached: true, current: 1);
      expect(row.status, GoalRowStatus.reached);
      expect(row.detail, 'Eintrag vorhanden');
    });

    test('the marks decide the words, never the number: open stays open', () {
      // The status (the ring) says open; a mark that arrives a moment earlier
      // in another stream does not turn the row into a rest day.
      final row = workout(reached: false, outcome: WorkoutDayOutcome.rest);
      expect(row.status, GoalRowStatus.open);
    });
  });

  group('habits (BS-103)', () {
    test('one row per habit, named and with its symbol', () {
      final day = _build(
        <GoalProgress>[_habit('a', checked: true), _habit('b')],
        habits: <GoalHabit>[
          (id: 'a', title: 'Lesen', icon: HabitIcon.book),
          (id: 'b', title: 'Dehnen', icon: HabitIcon.flame),
        ],
      );
      expect(day.rows.map((row) => row.title), <String>['Lesen', 'Dehnen']);
      expect(day.rows.first.status, GoalRowStatus.reached);
      expect(day.rows.first.detail, 'Heute abgehakt');
      expect(day.rows.last.status, GoalRowStatus.open);
      expect(day.rows.last.detail, 'Noch nicht abgehakt');
      expect(day.rows.first.habitIcon, HabitIcon.book);
      expect(day.rows.last.habitId, 'b');
      expect(day.rows.last.goalKey, habitGoalKey('b'));
      expect(day.rows.last.type, isNull);
      expect(day.rows.first.fraction, 1);
      expect(day.rows.last.fraction, 0);
    });

    test('the habits keep the order of the habit list, not of the keys', () {
      final day = _build(
        <GoalProgress>[_habit('a'), _habit('b'), _habit('c')],
        habits: <GoalHabit>[
          (id: 'c', title: 'Dritte', icon: HabitIcon.book),
          (id: 'a', title: 'Erste', icon: HabitIcon.book),
          (id: 'b', title: 'Zweite', icon: HabitIcon.book),
        ],
      );
      expect(day.rows.map((row) => row.title), <String>[
        'Dritte',
        'Erste',
        'Zweite',
      ]);
    });

    test('an unknown habit still counts and gets a plain name', () {
      final day = _build(<GoalProgress>[_habit('x'), _habit('y')]);
      expect(day.rows, hasLength(2));
      expect(day.rows.map((row) => row.title), <String>[
        'Gewohnheit',
        'Gewohnheit',
      ]);
      expect(day.rows.first.habitIcon, isNull);
    });

    test('a habit goal of a module that is off does not appear', () {
      final off = GoalProgress(
        goalKey: habitGoalKey('a'),
        module: ModuleId.tasks,
        target: null,
        applicable: false,
        fulfilled: false,
        current: 0,
      );
      final day = _build(<GoalProgress>[off, _goal(GoalType.water)]);
      expect(day.rows, hasLength(1));
      expect(day.applicable, 1);
    });
  });

  group('order of the rows (BS-103)', () {
    test('the order of the goal editor, then the habits', () {
      // The snapshot lists weight and focus the other way round and puts the
      // daily workout goal last: the page follows the editor.
      final day = _build(
        <GoalProgress>[
          _goal(GoalType.water),
          _goal(GoalType.steps),
          _goal(GoalType.weightEntry),
          _goal(GoalType.focusMinutes),
          _goal(GoalType.taskCompletion),
          _habit('h'),
          _goal(GoalType.workoutDaily),
        ],
        habits: <GoalHabit>[(id: 'h', title: 'Lesen', icon: HabitIcon.book)],
      );
      expect(day.rows.map((row) => row.title), <String>[
        'Wasser',
        'Schritte',
        'Fokus',
        'Gewicht erfassen',
        'Workout heute',
        'Aufgabe erledigen',
        'Lesen',
      ]);
    });
  });

  group('the weekly workout goal stays apart (BS-103, BS-99)', () {
    test('it is its own row and changes no number of the ring', () {
      final goals = <GoalProgress>[
        _goal(GoalType.water, current: 2500, reached: true),
        _goal(GoalType.steps),
      ];
      final without = _build(goals);
      final withWeek = _build(goals, week: _week(2));
      expect(withWeek.applicable, without.applicable);
      expect(withWeek.fulfilled, without.fulfilled);
      expect(withWeek.rows, hasLength(without.rows.length));
      expect(without.weekly, isNull);
      final weekly = withWeek.weekly!;
      expect(weekly.isWeekly, isTrue);
      expect(weekly.title, 'Workouts diese Woche');
      expect(weekly.detail, '2 von 3 · 67 %');
      expect(weekly.status, GoalRowStatus.open);
      expect(weekly.fraction, closeTo(2 / 3, 1e-9));
      expect(weekly.spoken, contains('2 von 3 Trainings, 67 Prozent'));
      expect(withWeek.rows.any((row) => row.isWeekly), isFalse);
    });

    test('reached, also above the target, with the real count', () {
      final weekly = _build(<GoalProgress>[
        _goal(GoalType.water),
      ], week: _week(5)).weekly!;
      expect(weekly.status, GoalRowStatus.reached);
      expect(weekly.detail, '5 von 3 · 167 %');
      expect(weekly.fraction, 1);
    });

    test('2 of 3 workouts never read 100 %, a week of 0 reads 0 %', () {
      expect(_week(0).weeklyTarget, 3);
      final none = _build(<GoalProgress>[
        _goal(GoalType.water),
      ], week: _week(0)).weekly!;
      expect(none.detail, '0 von 3 · 0 %');
    });

    test('it is not shown while no daily goal applies', () {
      final day = _build(<GoalProgress>[
        _goal(GoalType.water, applicable: false),
      ], week: _week(2));
      expect(day.hasGoals, isFalse);
      expect(day.weekly, isNull);
    });

    test('it is not shown for a past day', () {
      final day = _build(
        <GoalProgress>[_goal(GoalType.water)],
        date: _past,
        week: _week(2),
      );
      expect(day.weekly, isNull);
    });
  });

  group('the head of the page for every stand (BS-103)', () {
    GoalsDay day(int fulfilled, int applicable, {bool today = true}) {
      final goals = <GoalProgress>[
        for (var i = 0; i < applicable; i++)
          _habit('h$i', checked: i < fulfilled),
      ];
      return _build(goals, date: today ? _today : _past);
    }

    final today = <(int, int, String, String, String)>[
      (
        0,
        5,
        'Noch nichts erreicht',
        'Heute ist noch alles offen. Mach den ersten Schritt.',
        '0 von 5 Zielen erreicht',
      ),
      (
        2,
        5,
        '2 von 5 erreicht',
        'Noch 3 Ziele offen. Bleib dran!',
        '2 von 5 Zielen erreicht',
      ),
      (
        4,
        5,
        '4 von 5 erreicht',
        'Noch 1 Ziel offen. Bleib dran!',
        '4 von 5 Zielen erreicht',
      ),
      (
        5,
        5,
        '5 von 5 erreicht',
        'Stark! Heute ist alles geschafft.',
        '5 von 5 Zielen erreicht',
      ),
      (
        1,
        1,
        '1 von 1 Ziel erreicht',
        'Du hast dein Tagesziel erreicht.',
        '1 von 1 Ziel erreicht',
      ),
      (
        0,
        1,
        'Noch nichts erreicht',
        'Heute ist noch alles offen. Mach den ersten Schritt.',
        '0 von 1 Ziel erreicht',
      ),
    ];
    for (final (fulfilled, applicable, title, sentence, ring) in today) {
      test('$fulfilled of $applicable today', () {
        final model = day(fulfilled, applicable);
        expect(model.title, title);
        expect(model.sentence, sentence);
        expect(model.ringLabel, ring);
        expect(model.isComplete, fulfilled == applicable);
        expect(model.ringUnit, applicable == 1 ? 'Ziel' : 'Zielen');
        expect(model.summarySpoken, 'Samstag, 3. Oktober. $title. $sentence');
      });
    }

    test('the list is named after the number of goals', () {
      expect(day(1, 1).listTitle, 'Tagesziel');
      expect(day(1, 4).listTitle, 'Tagesziele');
    });

    test('a past day says "dieses Tages" and never "heute"', () {
      for (final (fulfilled, applicable) in const <(int, int)>[
        (0, 5),
        (2, 5),
        (5, 5),
        (1, 1),
      ]) {
        final model = day(fulfilled, applicable, today: false);
        expect(model.isToday, isFalse);
        expect(model.sentence, 'Du siehst die Werte dieses Tages.');
        expect(model.title.toLowerCase(), isNot(contains('heute')));
        expect(model.title.toLowerCase(), isNot(contains('noch')));
        expect(model.dateText, 'Samstag, 12. September');
      }
      expect(day(0, 5, today: false).title, 'Nichts erreicht');
    });

    test('the spoken text of the ring is the one of the card on Home', () {
      for (var applicable = 1; applicable <= 7; applicable++) {
        for (var fulfilled = 0; fulfilled <= applicable; fulfilled++) {
          expect(
            day(fulfilled, applicable).ringLabel,
            DayOverviewCard(
              fulfilled: fulfilled,
              applicable: applicable,
            ).ringLabel,
            reason: '$fulfilled of $applicable',
          );
        }
      }
    });
  });

  group('a past day uses the words of the past (BS-103)', () {
    test('no "heute" in the rows', () {
      final day = _build(<GoalProgress>[
        _goal(GoalType.steps, current: null),
        _goal(GoalType.weightEntry, current: 0),
        _goal(GoalType.taskCompletion, current: 0),
        _goal(GoalType.workoutDaily, current: 0),
        _habit('a'),
      ], date: _past);
      expect(day.isToday, isFalse);
      for (final row in day.rows) {
        // "Workout heute" is the name of a goal, not a time word.
        final words = row.spoken.replaceFirst(row.title, '').toLowerCase();
        expect(row.detail.toLowerCase(), isNot(contains('heute')));
        expect(row.detail.toLowerCase(), isNot(contains('noch ')));
        expect(words, isNot(contains('heute')));
      }
      expect(day.rows.map((row) => row.detail), <String>[
        'Keine Schritte eingetragen',
        'Nicht gewogen',
        'Kein Training eingetragen',
        'Keine Aufgabe erledigt',
        'Nicht abgehakt',
      ]);
    });
  });
}
