import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/goals/domain/day_snapshot.dart';
import 'package:self_improvement/core/goals/domain/goal_keys.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  final profileStart = LocalDate(2026, 9, 1);
  final today = LocalDate(2026, 10, 3);
  final yesterday = today.addDays(-1);
  final tomorrow = today.addDays(1);

  bool allEnabled(ModuleId module, LocalDate day) => true;

  DaySnapshot? build({
    LocalDate? day,
    LocalDate? start,
    Iterable<GoalVersion> versions = const [],
    bool Function(ModuleId module, LocalDate day)? moduleEnabledOn,
    Iterable<HabitSnapshotInput> habits = const [],
  }) => buildDaySnapshot(
    day: day ?? today,
    profileStart: start ?? profileStart,
    versions: versions,
    isModuleEnabledOn: moduleEnabledOn ?? allEnabled,
    habits: habits,
  );

  DaySnapshot built({
    LocalDate? day,
    Iterable<GoalVersion> versions = const [],
    bool Function(ModuleId module, LocalDate day)? moduleEnabledOn,
    Iterable<HabitSnapshotInput> habits = const [],
  }) => build(
    day: day,
    versions: versions,
    moduleEnabledOn: moduleEnabledOn,
    habits: habits,
  )!;

  Map<String, bool> applicability(DaySnapshot snapshot) => {
    for (final item in snapshot.items) item.goalKey: item.applicable,
  };

  group('HabitSnapshotInput.applicableOn', () {
    test('an active habit applies from its start day on', () {
      final habit = HabitSnapshotInput(id: 'h', startedOn: today);
      expect(habit.applicableOn(yesterday), isFalse);
      expect(habit.applicableOn(today), isTrue, reason: 'starts today');
      expect(habit.applicableOn(tomorrow), isTrue);
      expect(habit.applicableOn(today.addDays(400)), isTrue);
    });

    test('archived from tomorrow stays applicable today', () {
      final habit = HabitSnapshotInput(
        id: 'h',
        startedOn: profileStart,
        archivedFrom: tomorrow,
      );
      expect(habit.applicableOn(yesterday), isTrue);
      expect(habit.applicableOn(today), isTrue, reason: 'archive day itself');
      expect(habit.applicableOn(tomorrow), isFalse);
      expect(habit.applicableOn(tomorrow.addDays(30)), isFalse);
    });

    test('archived from today no longer applies today', () {
      final habit = HabitSnapshotInput(
        id: 'h',
        startedOn: profileStart,
        archivedFrom: today,
      );
      expect(habit.applicableOn(yesterday), isTrue);
      expect(habit.applicableOn(today), isFalse);
    });

    test('a habit archived on the day it starts never applies', () {
      final habit = HabitSnapshotInput(
        id: 'h',
        startedOn: today,
        archivedFrom: today,
      );
      expect(habit.applicableOn(yesterday), isFalse);
      expect(habit.applicableOn(today), isFalse);
      expect(habit.applicableOn(tomorrow), isFalse);
    });
  });

  group('buildDaySnapshot: range and defaults', () {
    test('no snapshot before the profile start', () {
      expect(build(day: profileStart.addDays(-1)), isNull);
      expect(build(day: LocalDate(2020, 1, 1)), isNull);
    });

    test('a snapshot exists on the profile start day and after it', () {
      expect(build(day: profileStart), isNotNull);
      expect(build(day: profileStart.addDays(1)), isNotNull);
      expect(build(day: today.addDays(30)), isNotNull);
    });

    test('contains the six daily goals in enum order with defaults (BS-99: "Workout heute" is last and off)', () {
      final snapshot = built();
      expect(snapshot.date, today);
      expect(snapshot.items, [
        const GoalSnapshotItem(
          goalKey: 'water',
          module: ModuleId.nutrition,
          target: 2500,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'steps',
          module: ModuleId.body,
          target: 10000,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'weight_entry',
          module: ModuleId.body,
          target: 1,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'focus_minutes',
          module: ModuleId.focus,
          target: 25,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'task_completion',
          module: ModuleId.tasks,
          target: 1,
          applicable: true,
        ),
        const GoalSnapshotItem(
          goalKey: 'workout_daily',
          module: ModuleId.focus,
          target: 1,
          applicable: false,
        ),
      ]);
    });

    test('weekly workout goal, meals and XP never appear as daily goals', () {
      final versions = [
        GoalVersion(
          type: GoalType.workoutWeekly,
          target: 5,
          effectiveFrom: profileStart,
        ),
      ];
      final keys = built(
        versions: versions,
        habits: [HabitSnapshotInput(id: 'h', startedOn: profileStart)],
      ).items.map((item) => item.goalKey);
      expect(keys, isNot(contains('workout_weekly')));
      expect(
        keys.where((key) => !isHabitGoalKey(key)).toSet(),
        GoalType.dailyTypes.map((type) => type.key).toSet(),
      );
      expect(
        built().items.map((item) => item.module),
        isNot(contains(ModuleId.gamification)),
      );
    });

    test('is deterministic', () {
      expect(built().items, built().items);
    });
  });

  group('buildDaySnapshot: goal versions', () {
    test('takes the threshold of the version in effect on that day', () {
      final versions = [
        GoalVersion(
          type: GoalType.water,
          target: 2000,
          effectiveFrom: LocalDate(2026, 9, 1),
        ),
        GoalVersion(
          type: GoalType.water,
          target: 3000,
          effectiveFrom: LocalDate(2026, 10, 1),
        ),
        GoalVersion(
          type: GoalType.steps,
          target: 6000,
          effectiveFrom: LocalDate(2026, 9, 15),
        ),
      ];
      int? target(LocalDate day, String key) =>
          built(day: day, versions: versions).itemFor(key)?.target;
      expect(target(LocalDate(2026, 9, 30), 'water'), 2000);
      expect(target(LocalDate(2026, 10, 1), 'water'), 3000);
      expect(target(today, 'water'), 3000);
      expect(target(LocalDate(2026, 9, 14), 'steps'), 10000);
      expect(target(LocalDate(2026, 9, 15), 'steps'), 6000);
    });

    test('a version that starts later does not change an earlier day', () {
      final beforeChange = built(day: today);
      final withFutureVersion = built(
        day: today,
        versions: [
          GoalVersion(
            type: GoalType.water,
            target: 5000,
            effectiveFrom: tomorrow,
          ),
        ],
      );
      expect(withFutureVersion.items, beforeChange.items);
      expect(
        built(
          day: tomorrow,
          versions: [
            GoalVersion(
              type: GoalType.water,
              target: 5000,
              effectiveFrom: tomorrow,
            ),
          ],
        ).itemFor('water')?.target,
        5000,
      );
    });

    test('a disabled goal is not applicable but keeps its threshold', () {
      final snapshot = built(
        versions: [
          GoalVersion(
            type: GoalType.water,
            target: 3000,
            enabled: false,
            effectiveFrom: profileStart,
          ),
          GoalVersion(
            type: GoalType.weightEntry,
            enabled: false,
            effectiveFrom: profileStart,
          ),
        ],
      );
      expect(applicability(snapshot), {
        'water': false,
        'steps': true,
        'weight_entry': false,
        'focus_minutes': true,
        'task_completion': true,
        'workout_daily': false,
      });
      expect(snapshot.itemFor('water')?.target, 3000);
      expect(snapshot.itemFor('weight_entry')?.target, 1);
    });

    test('a goal that is switched off later still applied before', () {
      final versions = [
        GoalVersion(
          type: GoalType.steps,
          enabled: false,
          target: 10000,
          effectiveFrom: today,
        ),
      ];
      expect(
        built(day: yesterday, versions: versions).itemFor('steps')?.applicable,
        isTrue,
      );
      expect(
        built(day: today, versions: versions).itemFor('steps')?.applicable,
        isFalse,
      );
    });

    test('switch goals always use the fixed threshold 1', () {
      final snapshot = built(
        versions: [
          GoalVersion(
            type: GoalType.taskCompletion,
            target: 9,
            effectiveFrom: profileStart,
          ),
        ],
      );
      expect(snapshot.itemFor('task_completion')?.target, 1);
    });
  });

  group('buildDaySnapshot: modules', () {
    test('a disabled module makes exactly its goals not applicable', () {
      // "Workout heute" is switched on here: it is off by default, so without
      // the version the module would not be the reason it does not apply.
      final dailyWorkoutOn = GoalVersion(
        type: GoalType.workoutDaily,
        effectiveFrom: profileStart,
      );
      final expected = <ModuleId, Set<String>>{
        ModuleId.nutrition: {'water'},
        ModuleId.body: {'steps', 'weight_entry'},
        ModuleId.focus: {'focus_minutes', 'workout_daily'},
        ModuleId.tasks: {'task_completion'},
        ModuleId.gamification: <String>{},
      };
      expected.forEach((disabled, offKeys) {
        final snapshot = built(
          versions: [dailyWorkoutOn],
          moduleEnabledOn: (module, day) => module != disabled,
        );
        for (final item in snapshot.items) {
          expect(
            item.applicable,
            !offKeys.contains(item.goalKey),
            reason: '${disabled.key} off, ${item.goalKey}',
          );
        }
      });
    });

    test('a goal needs the goal switch AND its module', () {
      final waterOff = GoalVersion(
        type: GoalType.water,
        target: 2500,
        enabled: false,
        effectiveFrom: profileStart,
      );
      bool onlyNutritionOff(ModuleId module, LocalDate day) =>
          module != ModuleId.nutrition;
      expect(applicability(built(versions: [waterOff]))['water'], isFalse);
      expect(
        applicability(built(moduleEnabledOn: onlyNutritionOff))['water'],
        isFalse,
      );
      expect(
        applicability(
          built(versions: [waterOff], moduleEnabledOn: onlyNutritionOff),
        )['water'],
        isFalse,
      );
    });

    test('all modules off leaves a snapshot without applicable goals', () {
      final snapshot = built(moduleEnabledOn: (module, day) => false);
      expect(snapshot.items, hasLength(6));
      expect(snapshot.items.where((item) => item.applicable), isEmpty);
    });

    test('the module status is asked for the day of the snapshot', () {
      final asked = <LocalDate>[];
      built(
        day: LocalDate(2026, 9, 20),
        moduleEnabledOn: (module, day) {
          asked.add(day);
          return true;
        },
      );
      expect(asked, isNotEmpty);
      expect(asked.toSet(), {LocalDate(2026, 9, 20)});
    });

    test('a module disabled from today on leaves earlier days applicable', () {
      bool nutritionOffSinceToday(ModuleId module, LocalDate day) =>
          !(module == ModuleId.nutrition && !day.isBefore(today));
      expect(
        built(
          day: yesterday,
          moduleEnabledOn: nutritionOffSinceToday,
        ).itemFor('water')?.applicable,
        isTrue,
      );
      expect(
        built(
          day: today,
          moduleEnabledOn: nutritionOffSinceToday,
        ).itemFor('water')?.applicable,
        isFalse,
      );
      expect(
        built(
          day: tomorrow,
          moduleEnabledOn: nutritionOffSinceToday,
        ).itemFor('water')?.applicable,
        isFalse,
        reason: 'future days use the current module status',
      );
    });
  });

  group('buildDaySnapshot: habits', () {
    HabitSnapshotInput habit(
      String id, {
      required LocalDate startedOn,
      LocalDate? archivedFrom,
    }) => HabitSnapshotInput(
      id: id,
      startedOn: startedOn,
      archivedFrom: archivedFrom,
    );

    test('applicable habits follow the daily goals, sorted by id', () {
      final snapshot = built(
        habits: [
          habit('b-habit', startedOn: profileStart),
          habit('a-habit', startedOn: profileStart),
          habit('c-habit', startedOn: profileStart),
        ],
      );
      expect(snapshot.items.map((item) => item.goalKey).toList(), [
        'water',
        'steps',
        'weight_entry',
        'focus_minutes',
        'task_completion',
        'workout_daily',
        'habit:a-habit',
        'habit:b-habit',
        'habit:c-habit',
      ]);
    });

    test('a habit item belongs to the tasks module and has no threshold', () {
      final snapshot = built(habits: [habit('h1', startedOn: profileStart)]);
      expect(
        snapshot.itemFor('habit:h1'),
        const GoalSnapshotItem(
          goalKey: 'habit:h1',
          module: ModuleId.tasks,
          target: null,
          applicable: true,
        ),
      );
    });

    test('a habit created today is a goal today, a future one is not', () {
      final snapshot = built(
        habits: [
          habit('new-today', startedOn: today),
          habit('starts-tomorrow', startedOn: tomorrow),
        ],
      );
      expect(snapshot.itemFor('habit:new-today')?.applicable, isTrue);
      expect(snapshot.itemFor('habit:starts-tomorrow'), isNull);
    });

    test('a habit archived today is still a goal today, not tomorrow', () {
      final archivedToday = habit(
        'h1',
        startedOn: profileStart,
        archivedFrom: tomorrow,
      );
      expect(
        built(
          day: today,
          habits: [archivedToday],
        ).itemFor('habit:h1')?.applicable,
        isTrue,
      );
      expect(
        built(day: tomorrow, habits: [archivedToday]).itemFor('habit:h1'),
        isNull,
      );
    });

    test('an archived habit stays in the snapshots of its past days', () {
      final archived = habit(
        'h1',
        startedOn: profileStart,
        archivedFrom: LocalDate(2026, 9, 10),
      );
      expect(
        built(
          day: LocalDate(2026, 9, 9),
          habits: [archived],
        ).itemFor('habit:h1'),
        isNotNull,
      );
      expect(
        built(
          day: LocalDate(2026, 9, 10),
          habits: [archived],
        ).itemFor('habit:h1'),
        isNull,
      );
      expect(built(day: today, habits: [archived]).itemFor('habit:h1'), isNull);
    });

    test('a habit is not a goal before it started', () {
      final habitStartedLater = habit('h1', startedOn: LocalDate(2026, 9, 20));
      expect(
        built(
          day: LocalDate(2026, 9, 19),
          habits: [habitStartedLater],
        ).itemFor('habit:h1'),
        isNull,
      );
      expect(
        built(
          day: LocalDate(2026, 9, 20),
          habits: [habitStartedLater],
        ).itemFor('habit:h1'),
        isNotNull,
      );
    });

    test('a disabled tasks module keeps the habit item but not applicable', () {
      final snapshot = built(
        habits: [habit('h1', startedOn: profileStart)],
        moduleEnabledOn: (module, day) => module != ModuleId.tasks,
      );
      expect(snapshot.itemFor('habit:h1')?.applicable, isFalse);
      expect(snapshot.itemFor('water')?.applicable, isTrue);
      expect(snapshot.itemFor('task_completion')?.applicable, isFalse);
    });

    test('another disabled module does not affect habits', () {
      final snapshot = built(
        habits: [habit('h1', startedOn: profileStart)],
        moduleEnabledOn: (module, day) => module != ModuleId.nutrition,
      );
      expect(snapshot.itemFor('habit:h1')?.applicable, isTrue);
    });
  });

  group('DaySnapshot helpers', () {
    test('itemFor and applicableTargetFor', () {
      final snapshot = built(
        moduleEnabledOn: (module, day) => module != ModuleId.nutrition,
      );
      expect(snapshot.itemFor('steps')?.target, 10000);
      expect(snapshot.itemFor('nope'), isNull);
      expect(snapshot.applicableTargetFor(GoalType.steps.key), 10000);
      expect(
        snapshot.applicableTargetFor(GoalType.water.key),
        isNull,
        reason: 'not applicable: no threshold for XP decisions',
      );
      expect(snapshot.applicableTargetFor('nope'), isNull);
    });

    test('item accessors parse the goal key', () {
      final snapshot = built(
        habits: [HabitSnapshotInput(id: 'h1', startedOn: profileStart)],
      );
      expect(snapshot.itemFor('water')?.type, GoalType.water);
      expect(snapshot.itemFor('water')?.habitId, isNull);
      expect(snapshot.itemFor('habit:h1')?.type, isNull);
      expect(snapshot.itemFor('habit:h1')?.habitId, 'h1');
    });
  });

  group('maskTodaySnapshot', () {
    final versions = <GoalVersion>[
      GoalVersion(
        type: GoalType.water,
        target: 3000,
        effectiveFrom: profileStart,
      ),
      GoalVersion(
        type: GoalType.focusMinutes,
        target: 40,
        enabled: false,
        effectiveFrom: profileStart,
      ),
    ];
    final habits = [HabitSnapshotInput(id: 'h1', startedOn: profileStart)];

    DaySnapshot storedToday() => built(versions: versions, habits: habits);

    DaySnapshot mask(
      DaySnapshot stored, {
      required bool Function(ModuleId module) moduleEnabledNow,
      Iterable<HabitSnapshotInput>? habitsNow,
      Iterable<GoalVersion>? versionsNow,
      LocalDate? onDay,
    }) => maskTodaySnapshot(
      today: onDay ?? today,
      stored: stored,
      versions: versionsNow ?? versions,
      habits: habitsNow ?? habits,
      isModuleEnabledNow: moduleEnabledNow,
    );

    test('disabling a module masks its goals immediately', () {
      final masked = mask(
        storedToday(),
        moduleEnabledNow: (module) => module != ModuleId.nutrition,
      );
      expect(masked.itemFor('water')?.applicable, isFalse);
      expect(masked.itemFor('steps')?.applicable, isTrue);
      expect(masked.itemFor('task_completion')?.applicable, isTrue);
      expect(masked.itemFor('habit:h1')?.applicable, isTrue);
    });

    test('masking keeps the frozen target of the masked goal', () {
      final masked = mask(
        storedToday(),
        moduleEnabledNow: (module) => module != ModuleId.nutrition,
      );
      expect(masked.itemFor('water')?.target, 3000);
      expect(
        masked.items.map((item) => item.goalKey),
        storedToday().items.map((item) => item.goalKey),
      );
    });

    test('re-enabling restores applicability with the original target', () {
      final original = storedToday();
      final masked = mask(
        original,
        moduleEnabledNow: (module) => module != ModuleId.nutrition,
      );
      final restored = mask(masked, moduleEnabledNow: (module) => true);
      expect(restored.items, original.items);
      expect(restored.itemFor('water')?.target, 3000);
      expect(restored.itemFor('water')?.applicable, isTrue);
    });

    test('re-enabling does not switch on a goal that is switched off', () {
      final original = storedToday();
      expect(original.itemFor('focus_minutes')?.applicable, isFalse);
      final masked = mask(
        original,
        moduleEnabledNow: (module) => module != ModuleId.focus,
      );
      expect(masked.itemFor('focus_minutes')?.applicable, isFalse);
      final restored = mask(masked, moduleEnabledNow: (module) => true);
      expect(restored.itemFor('focus_minutes')?.applicable, isFalse);
      expect(restored.itemFor('focus_minutes')?.target, 40);
    });

    test('disabling and re-enabling several modules round-trips', () {
      final original = storedToday();
      var current = original;
      for (final off in [ModuleId.body, ModuleId.tasks, ModuleId.nutrition]) {
        current = mask(current, moduleEnabledNow: (module) => module != off);
        expect(
          current.items.where((item) => !item.applicable),
          isNotEmpty,
          reason: off.key,
        );
      }
      expect(
        mask(current, moduleEnabledNow: (module) => true).items,
        original.items,
      );
    });

    test('disabling the tasks module masks habits, enabling restores them', () {
      final original = storedToday();
      final masked = mask(
        original,
        moduleEnabledNow: (module) => module != ModuleId.tasks,
      );
      expect(masked.itemFor('habit:h1')?.applicable, isFalse);
      expect(masked.itemFor('task_completion')?.applicable, isFalse);
      expect(
        mask(masked, moduleEnabledNow: (module) => true).items,
        original.items,
      );
    });

    test('a past day is never changed by the module choice of today', () {
      final past = built(day: yesterday, versions: versions, habits: habits);
      final result = mask(past, moduleEnabledNow: (module) => false);
      expect(identical(result, past), isTrue);
      expect(result.items, past.items);
      expect(
        result.itemFor('water')?.applicable,
        isTrue,
        reason: 'yesterday keeps its applicable goals',
      );
    });

    test('a future day is not touched either', () {
      final future = built(day: tomorrow, versions: versions, habits: habits);
      final result = mask(future, moduleEnabledNow: (module) => false);
      expect(identical(result, future), isTrue);
    });

    test(
      'targets stay frozen even if the versions resolve differently now',
      () {
        final stored = storedToday();
        final changedVersions = [
          GoalVersion(
            type: GoalType.water,
            target: 4500,
            effectiveFrom: profileStart,
          ),
        ];
        final masked = mask(
          stored,
          versionsNow: changedVersions,
          moduleEnabledNow: (module) => true,
        );
        expect(
          masked.itemFor('water')?.target,
          3000,
          reason: 'frozen original',
        );
        final rebuilt = built(versions: changedVersions, habits: habits);
        expect(rebuilt.itemFor('water')?.target, 4500);
      },
    );

    test('a habit created today is added, the other items stay', () {
      final stored = storedToday();
      final habitsNow = [
        ...habits,
        HabitSnapshotInput(id: 'h0-new', startedOn: today),
      ];
      final masked = mask(
        stored,
        habitsNow: habitsNow,
        moduleEnabledNow: (module) => true,
      );
      expect(masked.items.map((item) => item.goalKey).toList(), [
        'water',
        'steps',
        'weight_entry',
        'focus_minutes',
        'task_completion',
        'workout_daily',
        'habit:h0-new',
        'habit:h1',
      ]);
      expect(masked.itemFor('habit:h0-new')?.applicable, isTrue);
    });

    test('a habit archived today stays applicable today', () {
      final archivedToday = [
        HabitSnapshotInput(
          id: 'h1',
          startedOn: profileStart,
          archivedFrom: tomorrow,
        ),
      ];
      final masked = mask(
        storedToday(),
        habitsNow: archivedToday,
        moduleEnabledNow: (module) => true,
      );
      expect(masked.itemFor('habit:h1')?.applicable, isTrue);
    });

    test(
      'equals a rebuild with the live module status when sources are stable',
      () {
        final live = <ModuleId, bool>{
          ModuleId.body: false,
          ModuleId.nutrition: true,
          ModuleId.focus: true,
          ModuleId.tasks: false,
          ModuleId.gamification: true,
        };
        final masked = mask(
          storedToday(),
          moduleEnabledNow: (module) => live[module]!,
        );
        final rebuilt = built(
          versions: versions,
          habits: habits,
          moduleEnabledOn: (module, day) => live[module]!,
        );
        expect(masked.items, rebuilt.items);
      },
    );

    test('the date of the snapshot is preserved', () {
      expect(
        mask(storedToday(), moduleEnabledNow: (module) => true).date,
        today,
      );
    });
  });

  group('DaySnapshot value semantics', () {
    test('snapshots with the same date and items are equal', () {
      expect(built(), built());
      expect(built().hashCode, built().hashCode);
      expect(built(), isNot(built(day: yesterday)));
      expect(
        built(),
        isNot(built(moduleEnabledOn: (module, day) => false)),
        reason: 'applicability is part of the value',
      );
      expect(
        built(),
        isNot(
          built(
            habits: [HabitSnapshotInput(id: 'h', startedOn: profileStart)],
          ),
        ),
      );
    });
  });

  group('GoalSnapshotItem value semantics', () {
    test('equality covers all fields', () {
      const base = GoalSnapshotItem(
        goalKey: 'water',
        module: ModuleId.nutrition,
        target: 2500,
        applicable: true,
      );
      expect(
        base,
        const GoalSnapshotItem(
          goalKey: 'water',
          module: ModuleId.nutrition,
          target: 2500,
          applicable: true,
        ),
      );
      expect(
        base.hashCode,
        const GoalSnapshotItem(
          goalKey: 'water',
          module: ModuleId.nutrition,
          target: 2500,
          applicable: true,
        ).hashCode,
      );
      expect(
        base,
        isNot(
          const GoalSnapshotItem(
            goalKey: 'water',
            module: ModuleId.nutrition,
            target: 2500,
            applicable: false,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GoalSnapshotItem(
            goalKey: 'water',
            module: ModuleId.body,
            target: 2500,
            applicable: true,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GoalSnapshotItem(
            goalKey: 'water',
            module: ModuleId.nutrition,
            target: 2600,
            applicable: true,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const GoalSnapshotItem(
            goalKey: 'steps',
            module: ModuleId.nutrition,
            target: 2500,
            applicable: true,
          ),
        ),
      );
    });
  });

  group('"Workout heute" in the snapshot (BS-99)', () {
    GoalVersion daily({required LocalDate from, bool enabled = true}) =>
        GoalVersion(
          type: GoalType.workoutDaily,
          enabled: enabled,
          effectiveFrom: from,
        );

    test('(BS-99) every snapshot has it, off: no version means off', () {
      final item = built().itemFor('workout_daily')!;
      expect(item.type, GoalType.workoutDaily);
      expect(item.module, ModuleId.focus);
      expect(item.target, 1, reason: 'a switch goal: the fixed threshold 1');
      expect(item.applicable, isFalse);
      expect(
        built(day: yesterday).itemFor('workout_daily')?.applicable,
        isFalse,
      );
    });

    test('(BS-99, AT24) a version switches it on from its day, earlier days stay off', () {
      final versions = [daily(from: tomorrow)];
      expect(
        built(
          day: today,
          versions: versions,
        ).itemFor('workout_daily')?.applicable,
        isFalse,
        reason: 'a change saved today applies from tomorrow',
      );
      expect(
        built(
          day: tomorrow,
          versions: versions,
        ).itemFor('workout_daily')?.applicable,
        isTrue,
      );
      expect(
        built(
          day: tomorrow.addDays(30),
          versions: versions,
        ).itemFor('workout_daily')?.applicable,
        isTrue,
      );
    });

    test('(BS-99, AT24) switching it off later leaves the days before on', () {
      final versions = [
        daily(from: profileStart),
        daily(from: today, enabled: false),
      ];
      expect(
        built(
          day: yesterday,
          versions: versions,
        ).itemFor('workout_daily')?.applicable,
        isTrue,
      );
      expect(
        built(
          day: today,
          versions: versions,
        ).itemFor('workout_daily')?.applicable,
        isFalse,
      );
    });

    test('(BS-99) it needs the goal switch AND the focus module', () {
      final on = [daily(from: profileStart)];
      bool focusOff(ModuleId module, LocalDate day) => module != ModuleId.focus;
      expect(built(versions: on).itemFor('workout_daily')?.applicable, isTrue);
      expect(
        built(
          versions: on,
          moduleEnabledOn: focusOff,
        ).itemFor('workout_daily')?.applicable,
        isFalse,
      );
      expect(
        built(moduleEnabledOn: focusOff).itemFor('workout_daily')?.applicable,
        isFalse,
      );
    });

    test('(BS-99) the threshold is the fixed 1 whatever a version stores', () {
      final snapshot = built(
        versions: [
          GoalVersion(
            type: GoalType.workoutDaily,
            target: 9,
            effectiveFrom: profileStart,
          ),
        ],
      );
      expect(snapshot.itemFor('workout_daily')?.target, 1);
    });

    test('(BS-99) the weekly workout goal stays out of the snapshot even next to it', () {
      final snapshot = built(
        versions: [
          daily(from: profileStart),
          GoalVersion(
            type: GoalType.workoutWeekly,
            target: 5,
            effectiveFrom: profileStart,
          ),
        ],
      );
      expect(snapshot.itemFor('workout_weekly'), isNull);
      expect(snapshot.itemFor('workout_daily')?.applicable, isTrue);
    });

    test('(BS-99) masking today: the focus module masks it, enabling restores it with the goal\'s own flag', () {
      DaySnapshot stored(List<GoalVersion> versions) =>
          built(versions: versions);
      DaySnapshot mask(
        DaySnapshot snapshot,
        bool Function(ModuleId) enabled,
        List<GoalVersion> versions,
      ) => maskTodaySnapshot(
        today: today,
        stored: snapshot,
        versions: versions,
        habits: const [],
        isModuleEnabledNow: enabled,
      );

      final on = [daily(from: profileStart)];
      final original = stored(on);
      final masked = mask(original, (module) => module != ModuleId.focus, on);
      expect(masked.itemFor('workout_daily')?.applicable, isFalse);
      expect(
        mask(masked, (module) => true, on).items,
        original.items,
        reason: 'the goal is on again with the module',
      );

      final off = <GoalVersion>[];
      final originalOff = stored(off);
      expect(originalOff.itemFor('workout_daily')?.applicable, isFalse);
      final maskedOff = mask(
        originalOff,
        (module) => module != ModuleId.focus,
        off,
      );
      expect(
        mask(
          maskedOff,
          (module) => true,
          off,
        ).itemFor('workout_daily')?.applicable,
        isFalse,
        reason: 'enabling the module never switches the goal on',
      );
    });
  });
}
