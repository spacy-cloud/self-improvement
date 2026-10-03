import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/notifications/data/scheduled_notification_repository.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_time.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late ScheduledNotificationRepository repository;

  setUp(() async {
    harness = await DataHarness.create();
    repository = ScheduledNotificationRepository(harness.database);
  });
  tearDown(() => harness.dispose());

  PlannedNotification planned(
    String key, {
    DateTime? at,
    String route = '/water',
    String? ruleId,
  }) => PlannedNotification(
    semanticKey: key,
    kind: ReminderKind.water,
    fireAtUtc: at ?? DateTime.utc(2026, 10, 3, 8),
    route: route,
    title: 'Zeit für ein Glas Wasser',
    sourceRuleId: ruleId,
  );

  Future<void> insertRule(String id) => harness.database
      .into(harness.database.reminderRules)
      .insert(
        ReminderRulesCompanion.insert(
          id: id,
          moduleId: 'nutrition',
          kind: 'water',
          enabled: true,
          route: '/water',
          localTime: const Value(LocalTime(10, 0)),
        ),
      );

  group('ids', () {
    test('are positive integers handed out by the database counter', () async {
      final first = await repository.insert(planned('water:2026-10-03:10:00'));
      final second = await repository.insert(planned('water:2026-10-03:12:00'));
      expect(first, greaterThan(0));
      expect(second, greaterThan(first));
    });

    test('are never reused after a row was deleted', () async {
      final first = await repository.insert(planned('water:2026-10-03:10:00'));
      await repository.delete(first);
      final second = await repository.insert(planned('water:2026-10-03:12:00'));
      expect(second, greaterThan(first));

      // Not even for the same key: the reminder gets a fresh id.
      await repository.delete(second);
      final again = await repository.insert(planned('water:2026-10-03:10:00'));
      expect(again, greaterThan(second));
    });

    test('are not reused after all rows were deleted', () async {
      final ids = <int>[];
      for (var n = 0; n < 3; n++) {
        ids.add(await repository.insert(planned('k$n')));
      }
      await repository.deleteAll();
      final next = await repository.insert(planned('k-new'));
      expect(next, greaterThan(ids.last));
    });
  });

  group('rows', () {
    test('a semantic key exists only once', () async {
      await repository.insert(planned('water:2026-10-03:10:00'));
      await expectLater(
        repository.insert(planned('water:2026-10-03:10:00')),
        throwsA(anything),
      );
      expect(await repository.all(), hasLength(1));
    });

    test('keep time, route, source rule and the scheduled state', () async {
      await insertRule('rule-1');
      final id = await repository.insert(
        planned(
          'water:2026-10-03:10:00',
          at: DateTime.utc(2026, 10, 3, 8),
          ruleId: 'rule-1',
        ),
      );
      final row = (await repository.all()).single;
      expect(row.notificationId, id);
      expect(row.semanticKey, 'water:2026-10-03:10:00');
      expect(row.fireAtUtc, DateTime.utc(2026, 10, 3, 8));
      expect(row.route, '/water');
      expect(row.sourceRuleId, 'rule-1');
      expect(row.kind, ReminderKind.water);

      final raw = await harness.database
          .select(harness.database.scheduledNotifications)
          .getSingle();
      expect(raw.state, 'scheduled');
    });

    test('update moves time and route but keeps id and key', () async {
      final id = await repository.insert(planned('habit:x:2026-10-03'));
      await repository.update(
        id,
        planned(
          'habit:x:2026-10-03',
          at: DateTime.utc(2026, 10, 3, 17),
          route: '/habits',
        ),
      );
      final row = (await repository.all()).single;
      expect(row.notificationId, id);
      expect(row.semanticKey, 'habit:x:2026-10-03');
      expect(row.fireAtUtc, DateTime.utc(2026, 10, 3, 17));
      expect(row.route, '/habits');
    });

    test('are ordered by fire time, then by id', () async {
      final late = await repository.insert(
        planned('k-late', at: DateTime.utc(2026, 10, 3, 12)),
      );
      final earlyA = await repository.insert(
        planned('k-early-a', at: DateTime.utc(2026, 10, 3, 8)),
      );
      final earlyB = await repository.insert(
        planned('k-early-b', at: DateTime.utc(2026, 10, 3, 8)),
      );
      expect(
        [for (final r in await repository.all()) r.notificationId],
        [earlyA, earlyB, late],
      );
    });

    test('delete removes only the named row', () async {
      final a = await repository.insert(planned('a'));
      final b = await repository.insert(planned('b'));
      await repository.delete(a);
      expect([for (final r in await repository.all()) r.notificationId], [b]);
    });

    test('deleting the source rule keeps the row without a source', () async {
      await insertRule('rule-1');
      await repository.insert(planned('k', ruleId: 'rule-1'));
      await (harness.database.delete(
        harness.database.reminderRules,
      )..where((r) => r.id.equals('rule-1'))).go();
      expect((await repository.all()).single.sourceRuleId, isNull);
    });

    test('a damaged key has no kind', () async {
      await repository.insert(planned('unknown:x'));
      expect((await repository.all()).single.kind, isNull);
    });
  });

  group('watchAll', () {
    test('emits the current rows and every change', () async {
      final emissions = <List<String>>[];
      final subscription = repository.watchAll().listen(
        (rows) => emissions.add([for (final r in rows) r.semanticKey]),
      );
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      final id = await repository.insert(planned('a'));
      await pumpEventQueue();
      expect(emissions.last, ['a']);

      await repository.delete(id);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);
    });
  });
}
