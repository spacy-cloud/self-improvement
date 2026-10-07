import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/day_status.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/body/steps/application/steps_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/workout_day_providers.dart';
import 'package:self_improvement/features/focus/domain/focus_session.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/nutrition/application/meal_providers.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/nutrition/domain/meal_summary.dart';
import 'package:self_improvement/features/nutrition/domain/water_overview.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/dashboard_test_kit.dart';
import '../support/day_browser_kit.dart';

// BS-93: a card of a day before today that cannot read its numbers says so and
// offers "Erneut versuchen", and the retry reads AGAIN what failed (a retry that
// asks another provider would leave the card broken). Each case lets the one
// source of a card fail and counts how often it was asked.

/// The day the cards are paged to: Thursday, 1 October.
final LocalDate _day = hostToday.addDays(-2);

/// A read that fails. [onRead] is told each time the provider is built.
Stream<T> _fails<T>(void Function() onRead) {
  onRead();
  return Stream<T>.error(StateError('no read'));
}

void main() {
  final cases = <(String, Override Function(void Function() onRead))>[
    (
      'Schritte',
      (onRead) => stepsDayProvider.overrideWith(
        (ref, day) => _fails<StepsToday>(onRead),
      ),
    ),
    (
      'Wasser',
      (onRead) => waterDayProvider.overrideWith(
        (ref, day) => _fails<WaterToday>(onRead),
      ),
    ),
    (
      'Gewicht',
      (onRead) => weightEntriesProvider.overrideWith(
        (ref) => _fails<List<WeightEntry>>(onRead),
      ),
    ),
    (
      'Workout',
      (onRead) => workoutEntriesOnProvider.overrideWith(
        (ref, day) => _fails<List<WorkoutEntry>>(onRead),
      ),
    ),
    (
      'Fokus',
      (onRead) => focusSessionsOnProvider.overrideWith(
        (ref, day) => _fails<List<FocusSession>>(onRead),
      ),
    ),
    (
      'Aufgaben und Gewohnheiten',
      (onRead) =>
          tasksProvider.overrideWith((ref) => _fails<List<Task>>(onRead)),
    ),
    (
      'Ernährung',
      (onRead) =>
          mealsDayProvider.overrideWith((ref, day) => _fails<MealDay>(onRead)),
    ),
    (
      'XP und Level',
      (onRead) => totalXpThroughProvider.overrideWith(
        (ref, day) => _fails<int>(onRead),
      ),
    ),
  ];

  group('a card that cannot read (BS-93, AT27, Q01)', () {
    for (final (card, failing) in cases) {
      testWidgets('(BS-93, AT27) the card "$card" of a day says so and '
          '"Erneut versuchen" reads what failed again', (tester) async {
        var reads = 0;
        final home = await pumpRealHome(
          tester,
          overrides: <Override>[failing(() => reads++)],
        );
        await showDay(tester, home, _day);
        expect(find.text('Erneut versuchen'), findsOneWidget);
        expect(find.text('Daten konnten nicht geladen werden'), findsWidgets);
        expect(tester.takeException(), isNull, reason: 'no overflow');

        final before = reads;
        expect(before, greaterThan(0));
        await tester.ensureVisible(find.text('Erneut versuchen'));
        await tester.pump();
        await tester.tap(find.text('Erneut versuchen'));
        await tester.pump();
        await settle(tester);
        expect(reads, greaterThan(before), reason: 'the retry read it again');
      });
    }
  });

  group('the status of a day that cannot be read (BS-93, AT27)', () {
    testWidgets('(BS-93, AT27) Home says so and "Erneut versuchen" reads that '
        'day again', (tester) async {
      var reads = 0;
      final home = await pumpRealHome(
        tester,
        overrides: <Override>[
          dayStatusProvider.overrideWith((ref, day) {
            reads++;
            return reads == 1
                ? Stream<DayStatus?>.error(StateError('no read'))
                : ref.watch(dayStatusRepositoryProvider).watchDay(day);
          }),
        ],
      );
      await showDay(tester, home, _day);
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      expect(find.text('Nicht heute'), findsNothing);

      await tester.tap(find.text('Erneut versuchen'));
      await tester.pump();
      await settle(tester);
      expect(reads, 2);
      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
      expect(find.text('Nicht heute'), findsOneWidget);
      expect(find.text('Donnerstag, 1. Oktober'), findsOneWidget);
    });
  });
}
