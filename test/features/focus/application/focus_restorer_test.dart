import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/features/focus/application/focus_restorer.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';

/// A repository whose "mark awaiting" can be made to fail, like a concurrent
/// change or a broken disk.
final class _MarkFailingRepository extends FocusRepository {
  _MarkFailingRepository({required super.database, required super.runner});

  Object? markFailure;

  @override
  Future<CommandOutcome> markAwaitingConfirmation({
    required String commandId,
    required String id,
  }) {
    final failure = markFailure;
    if (failure != null) {
      throw failure;
    }
    return super.markAwaitingConfirmation(commandId: commandId, id: id);
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late _MarkFailingRepository repository;
  late FocusRestorer restorer;
  var restored = 0;

  setUp(() async {
    harness = await DataHarness.create();
    repository = _MarkFailingRepository(
      database: harness.database,
      runner: harness.runner,
    );
    restored = 0;
    restorer = FocusRestorer(
      repository: repository,
      clock: harness.clock,
      ids: harness.ids,
      onRestored: () => restored++,
    );
  });
  tearDown(() => harness.dispose());

  Future<String> start({int planned = 600}) async {
    final outcome = await repository.start(
      commandId: harness.ids.newId(),
      category: FocusCategory.reading,
      plannedSeconds: planned,
    );
    return outcome.entityId!;
  }

  test(
    'without an open session: nothing to restore, the callback still runs',
    () async {
      final result = await restorer.restore();
      expect(result.outcome, FocusRestoreOutcome.noOpenSession);
      expect(result.session, isNull);
      expect(result.elapsed, isNull);
      expect(restored, 1);
    },
  );

  test(
    'a running session with time left is untouched and reports the remainder',
    () async {
      final id = await start(planned: 600);
      harness.clock.advance(const Duration(seconds: 200));
      final result = await restorer.restore();
      expect(result.outcome, FocusRestoreOutcome.unchanged);
      expect(result.session!.id, id);
      expect(result.elapsed!.remainingSeconds, 400);
      expect(restored, 1);
      expect((await repository.findById(id))!.rowVersion, 1);
    },
  );

  test('a session past its end becomes awaiting confirmation and the persisted session is returned', () async {
    final id = await start(planned: 600);
    harness.clock.advance(const Duration(hours: 3));
    final result = await restorer.restore();
    expect(result.outcome, FocusRestoreOutcome.movedToAwaitingConfirmation);
    expect(result.session!.status, FocusStatus.awaitingConfirmation);
    expect(result.session!.rowVersion, 2, reason: 'the persisted row');
    expect(result.elapsed!.remainingSeconds, 0);
    expect((await repository.findById(id))!.accumulatedSeconds, 600);
  });

  test('restoring again is a no-op (idempotent)', () async {
    await start(planned: 600);
    harness.clock.advance(const Duration(hours: 3));
    await restorer.restore();
    final again = await restorer.restore();
    expect(again.outcome, FocusRestoreOutcome.unchanged);
    expect(again.session!.status, FocusStatus.awaitingConfirmation);
    final receipts = await harness.database
        .select(harness.database.commandReceipts)
        .get();
    expect(
      receipts.where((r) => r.commandType == FocusRepository.awaitType),
      hasLength(1),
    );
    expect(restored, 2);
  });

  test('paused sessions stay paused, however long ago', () async {
    final id = await start();
    harness.clock.advance(const Duration(seconds: 100));
    await repository.pause(commandId: harness.ids.newId(), id: id);
    harness.clock.advance(const Duration(days: 30));
    final result = await restorer.restore();
    expect(result.outcome, FocusRestoreOutcome.unchanged);
    expect(result.session!.status, FocusStatus.paused);
  });

  test('a concurrent change is not an error', () async {
    await start();
    harness.clock.advance(const Duration(hours: 1));
    repository.markFailure = const ConflictFailure(ConflictKind.invalidState);
    final result = await restorer.restore();
    expect(result.outcome, FocusRestoreOutcome.unchanged);
    expect(restored, 1);

    repository.markFailure = const NotFoundFailure(entity: 'focus_session');
    final gone = await restorer.restore();
    expect(gone.outcome, FocusRestoreOutcome.noOpenSession);
  });

  test('a storage failure is thrown, the callback still runs', () async {
    final id = await start();
    harness.clock.advance(const Duration(hours: 1));
    repository.markFailure = const StorageFailure();
    await expectLater(restorer.restore(), throwsA(isA<StorageFailure>()));
    expect(restored, 1);
    expect(
      (await repository.findById(id))!.status,
      FocusStatus.running,
      reason: 'nothing was written; the next restore tries again',
    );
    repository.markFailure = null;
    final retry = await restorer.restore();
    expect(retry.outcome, FocusRestoreOutcome.movedToAwaitingConfirmation);
  });
}
