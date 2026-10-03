import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/goals/data/goal_version_repository.dart';
import 'package:self_improvement/core/goals/data/goals_commands.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late GoalsCommands goals;
  late GoalVersionRepository versions;

  final today = LocalDate(2026, 10, 3);
  final tomorrow = LocalDate(2026, 10, 4);

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    versions = GoalVersionRepository(harness.database);
    goals = GoalsCommands(runner: harness.runner, versions: versions);
  });
  tearDown(() => harness.dispose());

  test(
    'a changed target takes effect tomorrow and leaves today untouched (AT24)',
    () async {
      // Today's snapshot exists with the old threshold before the edit.
      final weights = WeightRepository(
        database: harness.database,
        runner: harness.runner,
      );
      await weights.create(
        commandId: harness.ids.newId(),
        draft: WeightDraft(
          weightGrams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
        ),
      );

      final outcome = await goals.update(
        commandId: 'g1',
        changes: const {GoalType.water: GoalSetting(target: 3000)},
      );
      expect(outcome.entityId, '2026-10-04', reason: 'effective date');

      final all = await versions.all();
      final newVersion = all.singleWhere(
        (v) => v.type == GoalType.water && v.effectiveFrom == tomorrow,
      );
      expect(newVersion.target, 3000);
      // Today keeps 2500, tomorrow uses 3000.
      final repo = harness.dayStatusRepository();
      expect(
        (await repo.statusFor(today))!.goals
            .singleWhere((g) => g.goalKey == 'water')
            .target,
        2500,
      );
      harness.clock.advance(const Duration(days: 1));
      expect(
        (await repo.statusFor(tomorrow))!.goals
            .singleWhere((g) => g.goalKey == 'water')
            .target,
        3000,
      );
    },
  );

  test('several edits for tomorrow replace the same version', () async {
    await goals.update(
      commandId: 'a',
      changes: const {GoalType.water: GoalSetting(target: 3000)},
    );
    await goals.update(
      commandId: 'b',
      changes: const {GoalType.water: GoalSetting(target: 3500)},
    );
    final rows = (await versions.all()).where(
      (v) => v.type == GoalType.water && v.effectiveFrom == tomorrow,
    );
    expect(rows.single.target, 3500);
  });

  test('unchanged values create no version', () async {
    final before = (await versions.all()).length;
    await goals.update(
      commandId: 'same',
      changes: const {GoalType.water: GoalSetting(target: 2500)},
    );
    expect((await versions.all()).length, before);
  });

  test('the switch of a goal is versioned like its value', () async {
    await goals.update(
      commandId: 's',
      changes: const {
        GoalType.steps: GoalSetting(target: 10000, enabled: false),
      },
    );
    final repo = harness.dayStatusRepository();
    expect(
      (await repo.statusFor(today))!.goals
          .singleWhere((g) => g.goalKey == 'steps')
          .applicable,
      isTrue,
    );
    harness.clock.advance(const Duration(days: 1));
    expect(
      (await repo.statusFor(tomorrow))!.goals
          .singleWhere((g) => g.goalKey == 'steps')
          .applicable,
      isFalse,
    );
  });

  test(
    'validation boundaries for every goal type, nothing stored on error',
    () async {
      final cases = <GoalType, List<(int, bool)>>{
        GoalType.water: [
          (250, true),
          (10000, true),
          (200, false),
          (10050, false),
          (2525, false),
        ],
        GoalType.steps: [
          (100, true),
          (100000, true),
          (99, false),
          (100001, false),
        ],
        GoalType.focusMinutes: [
          (5, true),
          (180, true),
          (4, false),
          (181, false),
        ],
        GoalType.workoutWeekly: [
          (1, true),
          (14, true),
          (0, false),
          (15, false),
        ],
      };
      var id = 0;
      for (final entry in cases.entries) {
        for (final (target, valid) in entry.value) {
          final call = goals.update(
            commandId: 'v${id++}',
            changes: {entry.key: GoalSetting(target: target)},
          );
          if (valid) {
            await call;
          } else {
            await expectLater(
              call,
              throwsA(isA<ValidationFailure>()),
              reason: '${entry.key.key} $target',
            );
          }
        }
      }
    },
  );

  test('the workout week goal is edited the same way', () async {
    await goals.update(
      commandId: 'w',
      changes: const {GoalType.workoutWeekly: GoalSetting(target: 5)},
    );
    final v = (await versions.all()).singleWhere(
      (g) => g.type == GoalType.workoutWeekly && g.effectiveFrom == tomorrow,
    );
    expect(v.target, 5);
  });

  test('a replayed edit is a no-op', () async {
    await goals.update(
      commandId: 'r',
      changes: const {GoalType.water: GoalSetting(target: 3000)},
    );
    final replay = await goals.update(
      commandId: 'r',
      changes: const {GoalType.water: GoalSetting(target: 4000)},
    );
    expect(replay.replayed, isTrue);
    expect(
      (await versions.all())
          .singleWhere(
            (v) => v.type == GoalType.water && v.effectiveFrom == tomorrow,
          )
          .target,
      3000,
    );
  });
}
