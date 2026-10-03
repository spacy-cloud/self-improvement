import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/application/notification_entry_resolver.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/reminder_harness.dart';

/// What a tap on a notification (cold start or while running) opens, against
/// the real module statuses and records.
void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late ReminderHarness h;
  late NotificationEntryResolver resolver;

  setUp(() async {
    h = await ReminderHarness.create();
    resolver = NotificationEntryResolver(
      database: h.database,
      modules: h.data.moduleStatus,
      clock: h.data.clock,
    );
  });
  tearDown(() => h.dispose());

  group('known routes', () {
    test('open as they are when everything is on', () async {
      final habit = await h.addHabit();
      expect(await resolver.resolve('/'), '/');
      expect(await resolver.resolve('/water'), '/water');
      expect(await resolver.resolve('/habits'), '/habits');
      expect(await resolver.resolve('/focus/session'), '/focus/session');
      expect(await resolver.resolve('/habits/$habit'), '/habits/$habit');
    });

    test(
      'the payload of a planned notification resolves to its route',
      () async {
        await h.setWanted(true);
        final habit = await h.addHabit();
        await h.service.reconcile();
        for (final row in await h.rows()) {
          expect(await resolver.resolve(row.route), row.route);
        }
        expect(
          (await h.rows()).any((r) => r.route == '/habits/$habit'),
          isTrue,
        );
      },
    );
  });

  group('bad payloads', () {
    test('open the dashboard and never throw', () async {
      for (final payload in [
        null,
        '',
        'javascript:alert(1)',
        '/weight/new?kg=71.5',
        '/habits/not-a-uuid',
        '/${'x' * 500}',
      ]) {
        expect(await resolver.resolve(payload), '/', reason: '$payload');
      }
    });
  });

  group('modules switched off', () {
    test('the water route opens the dashboard', () async {
      await h.setModule(ModuleId.nutrition, enabled: false);
      expect(await resolver.resolve('/water'), '/');
    });

    test('habit routes open the dashboard', () async {
      final habit = await h.addHabit();
      await h.setModule(ModuleId.tasks, enabled: false);
      expect(await resolver.resolve('/habits'), '/');
      expect(await resolver.resolve('/habits/$habit'), '/');
    });

    test('the focus route opens the dashboard', () async {
      await h.setModule(ModuleId.focus, enabled: false);
      expect(await resolver.resolve('/focus/session'), '/');
    });

    test('a module switched on again opens its route again', () async {
      await h.setModule(ModuleId.nutrition, enabled: false);
      h.data.clock.advance(const Duration(minutes: 1));
      await h.setModule(ModuleId.nutrition, enabled: true);
      expect(await resolver.resolve('/water'), '/water');
    });

    test('other modules do not matter', () async {
      await h.setModule(ModuleId.focus, enabled: false);
      expect(await resolver.resolve('/water'), '/water');
    });
  });

  group('missing habit', () {
    const unknown = '00000000-0000-4000-8000-0000000000ff';

    test('an unknown habit opens the habit list', () async {
      expect(await resolver.resolve('/habits/$unknown'), '/habits');
    });

    test('a deleted habit opens the habit list', () async {
      final habit = await h.addHabit(deleted: true);
      expect(await resolver.resolve('/habits/$habit'), '/habits');
    });

    test('a habit archived from today on opens the habit list', () async {
      final habit = await h.addHabit(archivedFrom: LocalDate(2026, 10, 3));
      expect(await resolver.resolve('/habits/$habit'), '/habits');
    });

    test('a habit archived long ago opens the habit list', () async {
      final habit = await h.addHabit(archivedFrom: LocalDate(2026, 9, 1));
      expect(await resolver.resolve('/habits/$habit'), '/habits');
    });

    test('a habit archived from tomorrow on still opens today', () async {
      // Archiving works from tomorrow: today the habit is still there.
      final habit = await h.addHabit(archivedFrom: LocalDate(2026, 10, 4));
      expect(await resolver.resolve('/habits/$habit'), '/habits/$habit');
    });

    test('a switched off module wins over a missing habit', () async {
      await h.setModule(ModuleId.tasks, enabled: false);
      expect(await resolver.resolve('/habits/$unknown'), '/');
    });

    test('the next day the archived habit is gone for the tap', () async {
      final habit = await h.addHabit(archivedFrom: LocalDate(2026, 10, 4));
      h.data.clock.advance(const Duration(days: 1));
      expect(await resolver.resolve('/habits/$habit'), '/habits');
    });
  });
}
