import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/notifications/application/reminder_providers.dart';
import 'package:self_improvement/core/notifications/domain/reminder_status.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/time/clock_service.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// F7: what the production start put in place. On the emulator these are the
/// real services (database file, `flutter_timezone`, the notification plugin);
/// the host runs the same checks with its fakes.
///
/// Only what is deterministic on a fresh emulator is asserted: no particular
/// permission state (it depends on the system image), only that it can be read.
Future<void> realPlatformFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F7: the database is a file in the app support directory');
  await ctx.run(
    ctx.environment.expectDatabaseOnDisk,
    reason: 'the database file check did not finish',
  );

  ctx.log('F7: the device zone is a valid IANA id and the clock uses it');
  final zoneId = await ctx.run(
    ctx.environment.platformZoneId,
    reason: 'the platform did not report the device zone',
  );
  expect(zoneId, isNotEmpty);
  expect(
    TimeZones.isKnown(zoneId),
    isTrue,
    reason: 'the platform zone "$zoneId" is not in the timezone database',
  );
  expect(
    ctx.container.read(clockProvider).timeZoneId,
    zoneId,
    reason: 'the app clock must run in the zone the platform reports',
  );

  ctx.log('F7: the reminder platform is initialized and answers');
  final platform = ctx.container.read(reminderPlatformProvider);
  await ctx.run(
    platform.initialize,
    reason: 'the reminder platform did not initialize',
  );
  // Initializing again is allowed and does nothing.
  await ctx.run(
    platform.initialize,
    reason: 'the second initialization of the reminder platform did not finish',
  );
  final permission = await ctx.run(
    platform.permissionStatus,
    reason: 'the notification permission could not be read',
  );
  expect(
    permission,
    anyOf(NotificationPermission.granted, NotificationPermission.denied),
    reason:
        'on Android the permission is either granted or not granted, '
        'never "unavailable"',
  );
  final pending = await ctx.run(
    platform.pendingIds,
    reason: 'the pending notifications could not be read',
  );
  expect(pending, isA<Set<int>>());
}
