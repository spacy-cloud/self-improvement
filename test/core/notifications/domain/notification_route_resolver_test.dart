import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/schema_keys.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_route_resolver.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';
import 'package:self_improvement/core/notifications/domain/planned_notification.dart';
import 'package:self_improvement/core/notifications/domain/reminder_kind.dart';
import 'package:self_improvement/shared/local_date.dart';
import 'package:self_improvement/shared/local_time.dart';

import '../support/planner_fixtures.dart';

void main() {
  final habitId = uuid(7);
  // A UUID that contains letters, so that its upper case form differs.
  const letterId = '0000000a-0000-4000-8000-00000000000b';

  String resolve(
    String? payload, {
    Set<ModuleId>? enabled,
    bool habitExists = true,
    List<NotificationEntity>? asked,
  }) => NotificationRouteResolver.resolve(
    payload,
    isModuleEnabled: (module) =>
        (enabled ?? ModuleId.values.toSet()).contains(module),
    entityExists: (entity) {
      asked?.add(entity);
      return habitExists;
    },
  );

  group('known routes', () {
    test('every whitelisted route resolves to itself', () {
      expect(resolve('/'), '/');
      expect(resolve('/water'), '/water');
      expect(resolve('/habits'), '/habits');
      expect(resolve('/focus/session'), '/focus/session');
      expect(resolve('/habits/$habitId'), '/habits/$habitId');
    });

    test('the route constants are the whitelist', () {
      expect(NotificationRoutes.home, '/');
      expect(NotificationRoutes.water, '/water');
      expect(NotificationRoutes.habits, '/habits');
      expect(NotificationRoutes.focusSession, '/focus/session');
      expect(NotificationRoutes.habitDetail(habitId), '/habits/$habitId');
    });

    test('parse names the owning module and the entity', () {
      expect(NotificationRouteResolver.parse('/')!.module, isNull);
      expect(
        NotificationRouteResolver.parse('/water')!.module,
        ModuleId.nutrition,
      );
      expect(
        NotificationRouteResolver.parse('/habits')!.module,
        ModuleId.tasks,
      );
      expect(
        NotificationRouteResolver.parse('/focus/session')!.module,
        ModuleId.focus,
      );
      final habit = NotificationRouteResolver.parse('/habits/$habitId')!;
      expect(habit.module, ModuleId.tasks);
      expect(
        habit.entity,
        NotificationEntity(NotificationEntityKind.habit, habitId),
      );
      expect(NotificationRouteResolver.parse('/water')!.entity, isNull);
    });
  });

  group('malformed or unknown payloads open the dashboard', () {
    final bad = <String, String?>{
      'null': null,
      'empty': '',
      'blank': '   ',
      'no leading slash': 'water',
      'no leading slash habit': 'habits/$habitId',
      'unknown route': '/settings',
      'module route that is not offered': '/nutrition/water',
      'sub route of a known route': '/water/new',
      'focus without session': '/focus',
      'javascript scheme': 'javascript:alert(1)',
      'https url': 'https://example.com/water',
      'file url': 'file:///etc/passwd',
      'intent url': 'intent://scan/#Intent;scheme=zxing;end',
      'scheme relative': '//example.com/water',
      'trailing slash': '/water/',
      'query string': '/water?amount=250',
      'fragment': '/water#top',
      'dot dot': '/habits/../water',
      'encoded dot dot': '/habits/%2e%2e',
      'leading space': ' /water',
      'trailing space': '/water ',
      'trailing newline': '/water\n',
      'embedded newline': '/wa\nter',
      'null byte': '/water\u0000',
      'upper case route': '/WATER',
      'fullwidth letters': '/ｗater',
      'health values in a query': '/weight/new?kg=71.5',
      'habit title instead of id': '/habits/Lesen',
      'upper case uuid': '/habits/${letterId.toUpperCase()}',
      'uuid with braces': '/habits/{$habitId}',
      'short uuid': '/habits/${habitId.substring(1)}',
      'uuid with trailing newline': '/habits/$habitId\n',
      'uuid with suffix': '/habits/$habitId/edit',
      'uuid with trailing slash': '/habits/$habitId/',
      'two uuids': '/habits/$habitId/$habitId',
      'habit new': '/habits/new',
      'json': '{"route":"/water"}',
    };

    for (final entry in bad.entries) {
      test(entry.key, () {
        expect(resolve(entry.value), '/');
        expect(NotificationRouteResolver.parse(entry.value), isNull);
      });
    }

    test('an overlong payload is rejected without parsing', () {
      final long = '/habits/${'a' * 1000}';
      expect(resolve(long), '/');
      expect(resolve('/${'a' * 64}'), '/');
      expect(resolve('/${'w' * 100000}'), '/');
    });

    test('the longest valid payload is accepted', () {
      final longest = '/habits/$habitId';
      expect(longest.length, lessThanOrEqualTo(64));
      expect(resolve(longest), longest);
    });

    test('a bad payload never asks for modules or records', () {
      final asked = <NotificationEntity>[];
      var moduleChecks = 0;
      final route = NotificationRouteResolver.resolve(
        'javascript:alert(1)',
        isModuleEnabled: (_) {
          moduleChecks++;
          return true;
        },
        entityExists: (entity) {
          asked.add(entity);
          return true;
        },
      );
      expect(route, '/');
      expect(moduleChecks, 0);
      expect(asked, isEmpty);
    });
  });

  group('module switched off', () {
    test('water with nutrition off opens the dashboard', () {
      expect(resolve('/water', enabled: {ModuleId.tasks}), '/');
    });

    test('habits with tasks off open the dashboard, list and detail', () {
      final enabled = ModuleId.values.toSet()..remove(ModuleId.tasks);
      expect(resolve('/habits', enabled: enabled), '/');
      expect(resolve('/habits/$habitId', enabled: enabled), '/');
    });

    test('focus with focus off opens the dashboard', () {
      final enabled = ModuleId.values.toSet()..remove(ModuleId.focus);
      expect(resolve('/focus/session', enabled: enabled), '/');
    });

    test('the dashboard is reachable with every module off', () {
      expect(resolve('/', enabled: <ModuleId>{}), '/');
    });

    test('another module being off does not matter', () {
      final enabled = ModuleId.values.toSet()..remove(ModuleId.focus);
      expect(resolve('/water', enabled: enabled), '/water');
    });

    test('a switched off module wins over a missing record', () {
      final enabled = ModuleId.values.toSet()..remove(ModuleId.tasks);
      expect(
        resolve('/habits/$habitId', enabled: enabled, habitExists: false),
        '/',
      );
    });
  });

  group('missing record', () {
    test('a deleted or archived habit opens the habit list', () {
      expect(resolve('/habits/$habitId', habitExists: false), '/habits');
    });

    test('the record check receives the habit id from the payload', () {
      final asked = <NotificationEntity>[];
      resolve('/habits/$habitId', asked: asked);
      expect(asked, [
        NotificationEntity(NotificationEntityKind.habit, habitId),
      ]);
    });

    test('routes without a record never ask for one', () {
      final asked = <NotificationEntity>[];
      resolve('/habits', asked: asked, habitExists: false);
      resolve('/water', asked: asked, habitExists: false);
      resolve('/focus/session', asked: asked, habitExists: false);
      resolve('/', asked: asked, habitExists: false);
      expect(asked, isEmpty);
    });

    test('an existing habit keeps its detail route', () {
      expect(resolve('/habits/$habitId'), '/habits/$habitId');
    });
  });

  group('ids in payloads', () {
    test('only canonical lower case UUIDs are local ids', () {
      expect(NotificationRoutes.isLocalId(uuid(1)), isTrue);
      expect(NotificationRoutes.isLocalId('h1'), isFalse);
      expect(NotificationRoutes.isLocalId(''), isFalse);
      expect(NotificationRoutes.isLocalId('${uuid(1)}\n'), isFalse);
      expect(NotificationRoutes.isLocalId(letterId), isTrue);
      expect(NotificationRoutes.isLocalId(letterId.toUpperCase()), isFalse);
    });

    test('a habit id that is not a UUID becomes the habit list', () {
      expect(NotificationRoutes.habitDetail('Lesen & mehr'), '/habits');
      expect(NotificationRoutes.habitDetail('h1'), '/habits');
    });
  });

  group('reminder kinds', () {
    test('the kind keys are the schema keys of the rules plus the task', () {
      // A task reminder (schema 2, BS-111) belongs to the task itself
      // (`tasks.reminder_at_utc`) and is no row of `reminder_rules`: its kind
      // exists only as the prefix of the semantic key, so the kinds of the
      // rules are all the schema knows.
      expect(
        ReminderKind.values.map((k) => k.key).toSet().difference({'task'}),
        SchemaKeys.reminderKinds.toSet(),
      );
    });

    test('each kind belongs to the module whose switch removes it', () {
      expect(ReminderKind.water.module, ModuleId.nutrition);
      expect(ReminderKind.habit.module, ModuleId.tasks);
      expect(ReminderKind.focusEnd.module, ModuleId.focus);
    });

    test('the kind of a semantic key is read from its prefix', () {
      expect(
        ReminderKeys.kindOf(
          ReminderKeys.water(LocalDate(2026, 10, 3), const LocalTime(10, 0)),
        ),
        ReminderKind.water,
      );
      expect(
        ReminderKeys.kindOf(
          ReminderKeys.habit(habitId, LocalDate(2026, 10, 3)),
        ),
        ReminderKind.habit,
      );
      expect(
        ReminderKeys.kindOf(ReminderKeys.focusEnd(uuid(1))),
        ReminderKind.focusEnd,
      );
      expect(ReminderKeys.kindOf('task_due:x'), isNull);
      expect(ReminderKeys.kindOf('nokind'), isNull);
      expect(ReminderKeys.kindOf(':x'), isNull);
    });

    test('semantic keys have the documented shape', () {
      expect(
        ReminderKeys.water(LocalDate(2026, 10, 3), const LocalTime(10, 0)),
        'water:2026-10-03:10:00',
      );
      expect(
        ReminderKeys.habit(habitId, LocalDate(2026, 10, 3)),
        'habit:$habitId:2026-10-03',
      );
      expect(ReminderKeys.focusEnd(uuid(2)), 'focus_end:${uuid(2)}');
    });
  });
}
