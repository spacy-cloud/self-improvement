import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/bootstrap/app_runtime.dart';
import 'package:self_improvement/core/bootstrap/device_time_zone.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/profile/profile_repository.dart';
import 'package:self_improvement/core/testing/broken_executor.dart';

final class _FakeSource implements TimeZoneSource {
  _FakeSource(this.id, {this.fails = false});

  String id;
  bool fails;

  @override
  Future<String> currentZoneId() async {
    if (fails) {
      throw StateError('no platform');
    }
    return id;
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('uses the platform zone when it is a known IANA id', () async {
    final zone = await DeviceTimeZone.detect(_FakeSource('Europe/Berlin'));
    expect(zone.id, 'Europe/Berlin');
  });

  test('falls back to UTC for unknown ids and platform errors', () async {
    expect(
      (await DeviceTimeZone.detect(_FakeSource('Mars/Olympus'))).id,
      'UTC',
    );
    expect(
      (await DeviceTimeZone.detect(_FakeSource('x', fails: true))).id,
      'UTC',
    );
  });

  test('refresh reports a change only when the zone really changed', () async {
    final source = _FakeSource('Europe/Berlin');
    final zone = await DeviceTimeZone.detect(source);
    expect(await zone.refresh(), isFalse);
    source.id = 'America/New_York';
    expect(await zone.refresh(), isTrue);
    expect(zone.id, 'America/New_York');
    expect(await zone.refresh(), isFalse);
  });

  test('the runtime opens, migrates and seeds an in-memory database', () async {
    final runtime = await AppRuntime.create(
      executor: NativeDatabase.memory(),
      zoneSource: _FakeSource('Europe/Berlin'),
    );
    addTearDown(runtime.dispose);
    final profile = await ProfileRepository(runtime.database).get();
    expect(profile, isNotNull);
    expect(profile!.onboardingCompleted, isFalse);
    expect(profile.startedOn, runtime.clock.today());
    expect(runtime.clock.timeZoneId, 'Europe/Berlin');
  });

  test('a database that cannot be opened is a MigrationFailure', () async {
    await expectLater(
      AppRuntime.create(
        executor: BrokenQueryExecutor(),
        zoneSource: _FakeSource('Europe/Berlin'),
      ),
      throwsA(isA<MigrationFailure>()),
    );
  });
}
