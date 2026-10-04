import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/app_event.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/body/data/weight_repository.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/gamification/application/gamification_providers.dart';
import 'package:self_improvement/features/gamification/data/gamification_repository.dart';
import 'package:self_improvement/features/gamification/data/xp_projector.dart';
import 'package:self_improvement/features/gamification/domain/badges.dart';
import 'package:self_improvement/shared/local_date.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late GamificationRepository repository;
  late AppDatabase db;

  setUp(() async {
    harness = await DataHarness.create(realProjection: true);
    await harness.seedOnboarded(startedOn: LocalDate(2026, 9, 1));
    db = harness.database;
    repository = GamificationRepository(
      database: db,
      xp: XpProjector(db),
      status: harness.dayStatusRepository(),
    );
  });
  tearDown(() => harness.dispose());

  Future<void> award(String key, int points) => db
      .into(db.xpAwards)
      .insert(
        XpAwardsCompanion.insert(
          awardKey: key,
          localDate: LocalDate(2026, 10, 3),
          sourceKind: 'water',
          points: points,
          ruleVersion: 1,
        ),
      );

  Map<BadgeId, bool> earned(GamificationSummary s) => {
    for (final badge in s.badges) badge.id: badge.earned,
  };

  test('a fresh install has 0 XP, level 1 and all badges locked', () async {
    final s = await repository.summary();
    expect(s.totalXp, 0);
    expect(s.level.level, 1);
    expect(s.level.xpInLevel, 0);
    expect(earned(s).values.every((e) => !e), isTrue);
    expect(s.badges, hasLength(3));
  });

  test('level boundaries 99 / 100 / 250 come from the sum of awards', () async {
    await award('a', 99);
    var s = await repository.summary();
    expect((s.totalXp, s.level.level, s.level.xpInLevel), (99, 1, 99));
    await award('b', 1);
    s = await repository.summary();
    expect((s.totalXp, s.level.level, s.level.xpInLevel), (100, 2, 0));
    await award('c', 150);
    s = await repository.summary();
    expect((s.totalXp, s.level.level, s.level.xpInLevel), (250, 3, 50));
  });

  test(
    'first step: an eligible activity unlocks it, an ineligible one does not',
    () async {
      final weights = WeightRepository(database: db, runner: harness.runner);
      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'g-off',
              moduleId: 'gamification',
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 10),
              localDate: LocalDate(2026, 10, 3),
              enabled: false,
            ),
          );
      await weights.create(
        commandId: harness.ids.newId(),
        draft: WeightDraft(
          weightGrams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
        ),
      );
      expect(earned(await repository.summary())[BadgeId.firstStep], isFalse);

      await db
          .into(db.moduleStatusHistory)
          .insert(
            ModuleStatusHistoryCompanion.insert(
              id: 'g-on',
              moduleId: 'gamification',
              effectiveAtUtc: DateTime.utc(2026, 10, 3, 8, 20),
              localDate: LocalDate(2026, 10, 3),
              enabled: true,
            ),
          );
      final id = await weights.create(
        commandId: harness.ids.newId(),
        draft: WeightDraft(
          weightGrams: 71000,
          occurredAtUtc: DateTime.utc(2026, 10, 2, 6),
        ),
      );
      expect(earned(await repository.summary())[BadgeId.firstStep], isTrue);

      // Deleting the only eligible record locks the badge again.
      await weights.delete(commandId: harness.ids.newId(), id: id.entityId!);
      expect(earned(await repository.summary())[BadgeId.firstStep], isFalse);
    },
  );

  test('focus collected needs 3.600 completed seconds, discarded time does not count', () async {
    Future<void> focus(String id, int seconds, String status) => db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: id,
            category: 'reading',
            plannedSeconds: 3600,
            accumulatedSeconds: Value(seconds),
            startedAtUtc: DateTime.utc(2026, 10, 3, 6),
            endedAtUtc: Value(DateTime.utc(2026, 10, 3, 7)),
            completedLocalDate: Value(
              status == 'completed' ? LocalDate(2026, 10, 3) : null,
            ),
            timezoneId: 'Europe/Berlin',
            status: status,
            createdAtUtc: DateTime.utc(2026, 10, 3, 6),
            updatedAtUtc: DateTime.utc(2026, 10, 3, 6),
          ),
        );
    await focus('a', 3000, 'completed');
    await focus('b', 3600, 'discarded');
    expect(await repository.completedFocusSeconds(), 3000);
    expect(earned(await repository.summary())[BadgeId.focusCollected], isFalse);
    await focus('c', 600, 'completed');
    expect(await repository.completedFocusSeconds(), 3600);
    expect(earned(await repository.summary())[BadgeId.focusCollected], isTrue);
  });

  test(
    'one week: unlocked by a longest streak of 7 days from real data',
    () async {
      final weights = WeightRepository(database: db, runner: harness.runner);
      harness.clock.setNow(DateTime.utc(2026, 10, 10, 8));
      for (var day = 1; day <= 6; day++) {
        await weights.create(
          commandId: harness.ids.newId(),
          draft: WeightDraft(
            weightGrams: 71500,
            occurredAtUtc: DateTime.utc(2026, 10, day, 6),
          ),
        );
      }
      expect(
        earned(await repository.summary())[BadgeId.oneWeek],
        isFalse,
        reason: '6 days',
      );
      await weights.create(
        commandId: harness.ids.newId(),
        draft: WeightDraft(
          weightGrams: 71500,
          occurredAtUtc: DateTime.utc(2026, 10, 7, 6),
        ),
      );
      expect(
        earned(await repository.summary())[BadgeId.oneWeek],
        isTrue,
        reason: '7 days',
      );
    },
  );

  test('summary stream re-emits after a commit', () async {
    final values = <int>[];
    final subscription = repository.watchSummary().listen(
      (s) => values.add(s.totalXp),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final weights = WeightRepository(database: db, runner: harness.runner);
    await weights.create(
      commandId: harness.ids.newId(),
      draft: WeightDraft(
        weightGrams: 71500,
        occurredAtUtc: DateTime.utc(2026, 10, 3, 6),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await subscription.cancel();
    expect(values.first, 0);
    expect(values.last, 10);
  });

  group('level-up detection', () {
    test('emits only when a commit crosses a level boundary', () async {
      final container = harness.createContainer();
      final seen = <LevelUp>[];
      container.listen(levelUpProvider, (_, next) {
        final value = next.value;
        if (value != null) {
          seen.add(value);
        }
      });
      await Future<void>.delayed(Duration.zero);
      harness.events
        ..publish(
          const ActivityCommitted(commandType: 'x', xpBefore: 90, xpAfter: 95),
        )
        ..publish(
          const ActivityCommitted(commandType: 'x', xpBefore: 95, xpAfter: 105),
        )
        ..publish(
          const ActivityCommitted(
            commandType: 'x',
            xpBefore: 105,
            xpAfter: 100,
          ),
        )
        ..publish(
          const ActivityCommitted(
            commandType: 'x',
            xpBefore: 105,
            xpAfter: 105,
          ),
        )
        ..publish(
          const ActivityRemoved(commandType: 'x', xpBefore: 205, xpAfter: 95),
        )
        ..publish(
          const ActivityCommitted(
            commandType: 'x',
            xpBefore: 195,
            xpAfter: 305,
          ),
        );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(seen.map((l) => l.level), [
        2,
        4,
      ], reason: '100 -> level 2; jumping 195 -> 305 crosses to level 4');
    });
  });
}
