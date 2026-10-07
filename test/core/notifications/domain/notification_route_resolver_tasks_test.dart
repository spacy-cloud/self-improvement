import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/notifications/domain/notification_route_resolver.dart';
import 'package:self_improvement/core/notifications/domain/notification_routes.dart';

import '../support/planner_fixtures.dart';

/// The payload of a task reminder and what a tap on it opens (BS-111, AT29):
/// the form "Aufgabe bearbeiten" of the task, the task list when the task is
/// gone, the dashboard when the module is off or the payload is not ours.
void main() {
  final taskId = uuid(21);
  // A UUID that contains letters, so that its upper case form differs.
  const letterId = '0000000a-0000-4000-8000-00000000000b';

  String resolve(
    String? payload, {
    Set<ModuleId>? enabled,
    bool exists = true,
    List<NotificationEntity>? asked,
  }) => NotificationRouteResolver.resolve(
    payload,
    isModuleEnabled: (module) =>
        (enabled ?? ModuleId.values.toSet()).contains(module),
    entityExists: (entity) {
      asked?.add(entity);
      return exists;
    },
  );

  group('the route of a task', () {
    test('is /tasks/<uuid>, the form of the task (BS-111, AT29)', () {
      expect(NotificationRoutes.taskEdit(taskId), '/tasks/$taskId');
      expect(NotificationRoutes.taskEditPrefix, '/tasks/');
      expect(NotificationRoutes.tasks, '/habits?tab=tasks');
    });

    test('an id that is not a canonical UUID becomes the task list, never a '
        'payload with user text (BS-111)', () {
      expect(NotificationRoutes.taskEdit('Steuer & mehr'), '/habits?tab=tasks');
      expect(NotificationRoutes.taskEdit('t1'), '/habits?tab=tasks');
      expect(NotificationRoutes.taskEdit(''), '/habits?tab=tasks');
      expect(
        NotificationRoutes.taskEdit(letterId.toUpperCase()),
        '/habits?tab=tasks',
      );
    });

    test('parse names the module tasks and the task as the entity '
        '(BS-111)', () {
      final target = NotificationRouteResolver.parse('/tasks/$taskId')!;
      expect(target.route, '/tasks/$taskId');
      expect(target.module, ModuleId.tasks);
      expect(
        target.entity,
        NotificationEntity(NotificationEntityKind.task, taskId),
      );
      final list = NotificationRouteResolver.parse('/habits?tab=tasks')!;
      expect(list.route, '/habits?tab=tasks');
      expect(list.module, ModuleId.tasks);
      expect(list.entity, isNull);
    });

    test('an entity of a habit and one of a task with the same id are '
        'different (BS-111)', () {
      expect(
        NotificationEntity(NotificationEntityKind.task, taskId),
        isNot(NotificationEntity(NotificationEntityKind.habit, taskId)),
      );
    });
  });

  group('what is not accepted as a task payload (BS-111, AT29)', () {
    test('everything but exactly /tasks/<lower case uuid> opens the '
        'dashboard', () {
      for (final payload in <String>[
        '/tasks',
        '/tasks/',
        '/tasks/new',
        '/tasks/$taskId/edit',
        '/tasks/$taskId/',
        '/tasks/$taskId?x=1',
        '/tasks/$taskId#a',
        '/tasks/$taskId\n',
        ' /tasks/$taskId',
        '//tasks/$taskId',
        '/Tasks/$taskId',
        '/tasks/${letterId.toUpperCase()}',
        '/tasks/not-an-id',
        '/tasks/..%2F..',
        'tasks/$taskId',
        'https://example.invalid/tasks/$taskId',
        '/tasks/${'0' * 64}',
        '/habits?tab=habits',
        '/habits?tab=tasks&x=1',
        '/habits?tab=tasks#a',
        '/habits/?tab=tasks',
      ]) {
        expect(
          NotificationRouteResolver.parse(payload),
          isNull,
          reason: payload,
        );
        expect(resolve(payload), '/', reason: payload);
      }
    });

    test('an upper case letter in any one of the five groups of the id is '
        'refused (BS-111, AT29)', () {
      const lower = 'abcdef12-abcd-abcd-abcd-abcdef123456';
      expect(NotificationRouteResolver.parse('/tasks/$lower'), isNotNull);
      final groups = lower.split('-');
      for (var group = 0; group < groups.length; group++) {
        final changed = [...groups];
        changed[group] = changed[group].replaceFirst('a', 'A');
        final id = changed.join('-');
        expect(id, isNot(lower));
        expect(
          NotificationRouteResolver.parse('/tasks/$id'),
          isNull,
          reason: 'group ${group + 1}: $id',
        );
        expect(NotificationRoutes.taskEdit(id), NotificationRoutes.tasks);
      }
    });

    test('the longest valid payload stays inside the length limit', () {
      expect(
        '/tasks/$taskId'.length,
        lessThanOrEqualTo(NotificationRouteResolver.maxPayloadLength),
      );
      expect(NotificationRouteResolver.parse('/tasks/$letterId'), isNotNull);
    });
  });

  group('what a tap opens (BS-111, AT29)', () {
    test('an existing task: its form', () {
      expect(resolve('/tasks/$taskId'), '/tasks/$taskId');
    });

    test('a task that does not exist (any more): the task list', () {
      expect(resolve('/tasks/$taskId', exists: false), '/habits?tab=tasks');
    });

    test('a habit that does not exist still opens the habit list '
        '(regression)', () {
      expect(resolve('/habits/${uuid(7)}', exists: false), '/habits');
    });

    test('the module tasks off: the dashboard, the record is not even asked '
        'for', () {
      final asked = <NotificationEntity>[];
      expect(
        resolve(
          '/tasks/$taskId',
          enabled: ModuleId.values.toSet()..remove(ModuleId.tasks),
          asked: asked,
        ),
        '/',
      );
      expect(asked, isEmpty);
    });

    test('the task list route needs the module and no record', () {
      final asked = <NotificationEntity>[];
      expect(resolve('/habits?tab=tasks', asked: asked), '/habits?tab=tasks');
      expect(asked, isEmpty);
      expect(
        resolve(
          '/habits?tab=tasks',
          enabled: ModuleId.values.toSet()..remove(ModuleId.tasks),
        ),
        '/',
      );
    });

    test('the record is asked for exactly once, as a task', () {
      final asked = <NotificationEntity>[];
      resolve('/tasks/$taskId', asked: asked);
      expect(asked, [NotificationEntity(NotificationEntityKind.task, taskId)]);
    });
  });
}
