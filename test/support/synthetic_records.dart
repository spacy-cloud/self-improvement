import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'db_fixtures.dart';

/// How [insertSyntheticRecords] shapes the data.
final class SyntheticData {
  const SyntheticData({
    this.habitTitles = const <String>[
      'Gewohnheit 1',
      'Gewohnheit 2',
      'Gewohnheit 3',
    ],
    this.mealNames = const <String>['Mahlzeit 1', 'Mahlzeit 2', 'Mahlzeit 3'],
    this.varied = false,
    this.seed = 42,
  });

  /// Titles of the habits (one habit per title).
  final List<String> habitTitles;

  /// Names of the three daily meals.
  final List<String> mealNames;

  /// Richer variety for demo data: calories on most meals (some stay empty on
  /// purpose, so the "Kalorien unvollständig" state shows), alternating
  /// workout and focus categories. The load test keeps this off so its numbers
  /// stay comparable.
  final bool varied;

  /// Seed of the pseudo random generator (the result is deterministic).
  final int seed;
}

/// Writes deterministic synthetic records for every day from [first] to [last]
/// straight into [database] (no commands, no projections: call the projection
/// synchronizer afterwards) and returns how many rows were inserted. Ids come
/// from [ids], so the rows are valid for the backup format.
///
/// Used by the load test (AT36) and by the demo backup generator.
Future<int> insertSyntheticRecords(
  AppDatabase database,
  IdGenerator ids,
  LocalDate first,
  LocalDate last, {
  SyntheticData data = const SyntheticData(),
}) async {
  final random = math.Random(data.seed);
  var count = 0;
  final days = <LocalDate>[
    for (var d = first; !d.isAfter(last); d = d.addDays(1)) d,
  ];
  DateTime at(LocalDate date, int hour) =>
      DateTime.utc(date.year, date.month, date.day, hour);

  final habitIds = <String>[for (final _ in data.habitTitles) ids.newId()];

  await database.batch((batch) {
    for (var h = 0; h < habitIds.length; h++) {
      batch.insert(
        database.habits,
        habitRow(
          id: habitIds[h],
          title: data.habitTitles[h],
        ).copyWith(startedLocalDate: Value(first)),
      );
      count++;
    }
    for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
      final day = days[dayIndex];
      if (random.nextInt(10) != 0) {
        batch.insert(
          database.weightEntries,
          weightRow(
            id: ids.newId(),
            grams:
                78000 -
                ((day.year * 365 + day.month * 30 + day.day) % 90) * 100,
            at: at(day, 6),
          ).copyWith(localDate: Value(day)),
        );
        count++;
      }
      if (random.nextInt(100) < 85) {
        batch.insert(
          database.stepDays,
          stepRow(
            id: ids.newId(),
            steps: 2000 + random.nextInt(14000),
            date: day,
          ),
        );
        count++;
      }
      if (random.nextInt(100) < 80) {
        for (var i = 0; i < 4; i++) {
          batch.insert(
            database.waterEntries,
            waterRow(id: ids.newId(), ml: i == 0 ? 500 : 250).copyWith(
              occurredAtUtc: Value(at(day, 8 + i * 3)),
              localDate: Value(day),
            ),
          );
          count++;
        }
      }
      if (random.nextInt(100) < 60) {
        for (var i = 0; i < 3; i++) {
          final kcal = data.varied && random.nextInt(100) < 75
              ? Value<int?>(300 + random.nextInt(500))
              : const Value<int?>.absent();
          batch.insert(
            database.mealEntries,
            mealRow(
              id: ids.newId(),
              name: data.mealNames[i % data.mealNames.length],
              kcal: kcal,
            ).copyWith(
              occurredAtUtc: Value(at(day, 7 + i * 5)),
              localDate: Value(day),
            ),
          );
          count++;
        }
      }
      if (day.weekday == 2 || day.weekday == 5) {
        batch.insert(
          database.workoutEntries,
          workoutRow(
            id: ids.newId(),
            minutes: 30 + random.nextInt(60),
            category: data.varied && day.weekday == 5 ? 'cardio' : 'strength',
          ).copyWith(occurredAtUtc: Value(at(day, 17)), localDate: Value(day)),
        );
        count++;
      }
      if (random.nextInt(100) < 50) {
        batch.insert(
          database.focusSessions,
          focusRow(
            id: ids.newId(),
            status: 'completed',
            accumulated: 1500,
            completedDate: Value(day),
            category: data.varied ? _focusCategories[dayIndex % 4] : 'reading',
          ).copyWith(startedAtUtc: Value(at(day, 9))),
        );
        count++;
      }
      if (random.nextInt(100) < 40) {
        batch.insert(
          database.tasks,
          taskRow(
            id: ids.newId(),
            title: 'Aufgabe $count',
            completedAt: Value(at(day, 12)),
            completedDate: Value(day),
            eligibility: const Value(true),
          ).copyWith(createdAtUtc: Value(at(day, 8))),
        );
        count++;
      }
      for (final habitId in habitIds) {
        if (random.nextInt(100) < 55) {
          batch.insert(
            database.habitChecks,
            habitCheckRow(id: ids.newId(), habitId: habitId, date: day),
          );
          count++;
        }
      }
    }
  });
  return count;
}

const List<String> _focusCategories = <String>[
  'reading',
  'learning',
  'programming',
  'meditation',
];
