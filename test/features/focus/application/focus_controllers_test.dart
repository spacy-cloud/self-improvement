import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/core/testing/recording_projection.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/application/focus_session_controller.dart';
import 'package:self_improvement/features/focus/application/focus_setup_controller.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';
import 'package:self_improvement/features/focus/domain/focus_status.dart';
import 'package:self_improvement/features/focus/domain/focus_timer.dart';

import '../support/manual_tick_source.dart';
import '../support/recording_ids.dart';

/// A repository whose first [failures] starts fail like a broken disk.
final class _FlakyRepository extends FocusRepository {
  _FlakyRepository({
    required super.database,
    required super.runner,
    this.failures = 0,
  });

  int failures;
  final List<String> startIds = [];

  @override
  Future<CommandOutcome> start({
    required String commandId,
    required FocusCategory category,
    required int plannedSeconds,
  }) {
    startIds.add(commandId);
    if (failures > 0) {
      failures--;
      throw const StorageFailure();
    }
    return super.start(
      commandId: commandId,
      category: category,
      plannedSeconds: plannedSeconds,
    );
  }
}

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DataHarness harness;
  late RecordingProjectionSynchronizer projection;
  late RecordingIdGenerator ids;
  late ProviderContainer container;

  /// A container like `DataHarness.createContainer`, but with the recording id
  /// generator (the harness itself overrides the id provider, which cannot be
  /// overridden twice).
  ProviderContainer containerWith({List<Override> extra = const []}) {
    final created = ProviderContainer(
      retry: (retryCount, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(harness.database),
        clockProvider.overrideWithValue(harness.clock),
        idGeneratorProvider.overrideWithValue(ids),
        commandEventsProvider.overrideWithValue(harness.events),
        projectionSynchronizerProvider.overrideWithValue(harness.projections),
        ...extra,
      ],
    );
    addTearDown(created.dispose);
    return created;
  }

  setUp(() async {
    projection = RecordingProjectionSynchronizer();
    harness = await DataHarness.create(projections: projection);
    ids = RecordingIdGenerator(harness.ids);
    container = containerWith();
  });
  tearDown(() => harness.dispose());

  FocusRepository repository() => container.read(focusRepositoryProvider);

  FocusSessionController actions() =>
      container.read(focusSessionControllerProvider.notifier);

  FocusActionState actionState() =>
      container.read(focusSessionControllerProvider);

  void advance(int seconds) =>
      harness.clock.advance(Duration(seconds: seconds));

  Future<String> start({int planned = 1500}) async {
    final outcome = await repository().start(
      commandId: harness.ids.newId(),
      category: FocusCategory.learning,
      plannedSeconds: planned,
    );
    return outcome.entityId!;
  }

  Future<List<CommandReceiptRow>> receipts() =>
      harness.database.select(harness.database.commandReceipts).get();

  FocusActionDone done(FocusActionResult result) {
    expect(result, isA<FocusActionDone>());
    return result as FocusActionDone;
  }

  FocusActionFailed failed(FocusActionResult result) {
    expect(result, isA<FocusActionFailed>());
    return result as FocusActionFailed;
  }

  group('FocusSessionController', () {
    test(
      'pause and resume return the session id and a German message',
      () async {
        final id = await start();
        advance(60);
        final paused = done(await actions().pause(id));
        expect(paused.sessionId, id);
        expect(paused.message, 'Pausiert');
        expect(paused.undo, isNull, reason: 'pause is not undoable');
        expect((await repository().findById(id))!.status, FocusStatus.paused);

        final resumed = done(await actions().resume(id));
        expect(resumed.message, 'Fokus fortgesetzt');
        expect((await repository().findById(id))!.status, FocusStatus.running);
        expect(actionState().busy, isFalse);
        expect(actionState().failure, isNull);
      },
    );

    test(
      'save and finishEarly complete the session and offer an undo',
      () async {
        final id = await start();
        advance(600);
        final saved = done(await actions().save(id));
        expect(saved.message, 'Sitzung gespeichert');
        expect(saved.undo, isNotNull);
        expect(
          (await repository().findById(id))!.status,
          FocusStatus.completed,
        );
        await saved.undo!.run(harness.ids.newId());
        expect((await repository().findById(id))!.status, FocusStatus.running);

        advance(60);
        final early = done(await actions().finishEarly(id));
        expect(early.action, FocusAction.save);
        expect(
          (await repository().findById(id))!.status,
          FocusStatus.completed,
        );
      },
    );

    test(
      'a session below one second fails with a field error and changes nothing',
      () async {
        final id = await start();
        final result = failed(await actions().save(id));
        expect(result.failure, isA<ValidationFailure>());
        expect(result.fieldErrors.keys, contains(FocusFields.duration));
        expect(
          result.message,
          'Die Sitzung ist zu kurz zum Speichern. Es wird mindestens eine Sekunde benötigt.',
        );
        expect(actionState().failure, same(result.failure));
        expect((await repository().findById(id))!.status, FocusStatus.running);
        actions().clearFailure();
        expect(actionState().failure, isNull);
      },
    );

    test('discard returns an undo that reopens the session', () async {
      final id = await start();
      advance(120);
      final discarded = done(await actions().discard(id));
      expect(discarded.message, 'Sitzung verworfen');
      expect(await repository().findOpen(), isNull);
      await discarded.undo!.run(harness.ids.newId());
      expect((await repository().findOpen())!.id, id);
    });

    test(
      'notes: update with a version, field error for too long, undo',
      () async {
        final id = await start();
        advance(300);
        await actions().save(id);
        final session = (await repository().findById(id))!;
        final saved = done(
          await actions().updateNote(
            id,
            '  Kapitel 2  ',
            expectedRowVersion: session.rowVersion,
          ),
        );
        expect(saved.message, 'Notiz gespeichert');
        expect((await repository().findById(id))!.note, 'Kapitel 2');

        final tooLong = failed(await actions().updateNote(id, 'x' * 501));
        expect(tooLong.fieldErrors.keys, contains(FocusFields.note));

        final stale = failed(
          await actions().updateNote(id, 'neu', expectedRowVersion: 1),
        );
        expect(
          (stale.failure as ConflictFailure).kind,
          ConflictKind.staleVersion,
        );
        expect(stale.message, 'Der Eintrag wurde inzwischen geändert.');

        await saved.undo!.run(harness.ids.newId());
        expect((await repository().findById(id))!.note, isNull);
      },
    );

    test(
      'delete returns the undo and removes the session from the history',
      () async {
        final id = await start();
        advance(300);
        await actions().save(id);
        final deleted = done(await actions().delete(id));
        expect(deleted.message, 'Sitzung gelöscht');
        expect(await repository().findById(id), isNull);
        await deleted.undo!.run(harness.ids.newId());
        expect(await repository().findById(id), isNotNull);
      },
    );

    test(
      'an impossible action is a conflict, a missing session NotFound',
      () async {
        final id = await start();
        advance(5000);
        await repository().markAwaitingConfirmation(
          commandId: harness.ids.newId(),
          id: id,
        );
        final resume = failed(await actions().resume(id));
        expect(
          (resume.failure as ConflictFailure).kind,
          ConflictKind.invalidState,
        );
        expect(
          resume.message,
          'Die Aktion ist im aktuellen Zustand nicht möglich.',
        );
        final missing = failed(await actions().pause('missing'));
        expect(missing.failure, isA<NotFoundFailure>());
      },
    );

    test('a double tap runs one action and ignores the other', () async {
      final id = await start();
      advance(600);
      final results = await Future.wait([
        actions().save(id),
        actions().save(id),
      ]);
      expect(results.whereType<FocusActionDone>(), hasLength(1));
      expect(results.whereType<FocusActionIgnored>(), hasLength(1));
      expect((await repository().findById(id))!.status, FocusStatus.completed);
      expect(
        projection.syncs,
        hasLength(1),
        reason: 'exactly one completion reached the projection',
      );
    });

    test('while an action runs the state is busy', () async {
      final id = await start();
      advance(100);
      final future = actions().pause(id);
      expect(actionState().busy, isTrue);
      await future;
      expect(actionState().busy, isFalse);
    });

    test('a retry after a storage failure reuses the command id, a new action gets a new one', () async {
      final id = await start();
      advance(600);
      // Ids issued so far include the entity id of the session.
      final baseline = ids.issued.length;
      projection.failure = StateError('disk full');
      final first = failed(await actions().save(id));
      expect(first.failure, isA<StorageFailure>());
      expect(first.message, contains('Speichern fehlgeschlagen'));
      expect((await repository().findById(id))!.status, FocusStatus.running);
      expect(ids.issued, hasLength(baseline + 1), reason: 'one command id');
      final commandId = ids.issued.last;

      projection.failure = null;
      done(await actions().save(id));
      expect(
        ids.issued,
        hasLength(baseline + 1),
        reason: 'the retry reused the id',
      );
      expect(
        (await receipts()).where((r) => r.commandId == commandId),
        hasLength(1),
        reason: 'the committed save carries the id of the first attempt',
      );
      expect((await repository().findById(id))!.status, FocusStatus.completed);

      await actions().updateNote(id, 'danach');
      expect(
        ids.issued,
        hasLength(baseline + 2),
        reason: 'a new action, a new id',
      );
    });

    test('two real pauses on different times are two commands', () async {
      final id = await start();
      final baseline = ids.issued.length;
      advance(100);
      await actions().pause(id);
      await actions().resume(id);
      advance(100);
      await actions().pause(id);
      expect(
        (await repository().findById(id))!.accumulatedSeconds,
        200,
        reason: 'the second pause was not swallowed as a replay',
      );
      expect(ids.issued, hasLength(baseline + 3));
    });
  });

  group('FocusSetupController', () {
    FocusSetupController setup() => container.read(focusSetupProvider.notifier);
    FocusSetupState setupState() => container.read(focusSetupProvider);

    setUp(() {
      container.listen(focusSetupProvider, (_, _) {});
    });

    test('starts with 25 minutes, "Sonstiges" and no failure', () {
      expect(setupState().plannedMinutes, 25);
      expect(setupState().plannedSeconds, 1500);
      expect(setupState().category, FocusCategory.other);
      expect(setupState().canStepDown, isTrue);
      expect(setupState().canStepUp, isTrue);
      expect(setupState().submitting, isFalse);
      expect(setupState().fieldErrors, isEmpty);
      expect(setupState().failure, isNull);
    });

    test('the stepper moves in 5 minute steps within 5 to 180', () {
      setup().stepPlannedMinutes(1);
      expect(setupState().plannedMinutes, 30);
      setup().stepPlannedMinutes(-1);
      setup().stepPlannedMinutes(-1);
      expect(setupState().plannedMinutes, 20);
      for (var i = 0; i < 10; i++) {
        setup().stepPlannedMinutes(-1);
      }
      expect(setupState().plannedMinutes, 5, reason: 'lower bound');
      expect(setupState().canStepDown, isFalse);
      expect(setupState().canStepUp, isTrue);
      for (var i = 0; i < 50; i++) {
        setup().stepPlannedMinutes(1);
      }
      expect(setupState().plannedMinutes, 180, reason: 'upper bound');
      expect(setupState().canStepUp, isFalse);
      expect(setupState().canStepDown, isTrue);
    });

    test('set minutes are clamped to 5 and 180', () {
      setup().setPlannedMinutes(500);
      expect(setupState().plannedMinutes, 180);
      setup().setPlannedMinutes(0);
      expect(setupState().plannedMinutes, 5);
      setup().setPlannedMinutes(45);
      expect(setupState().plannedMinutes, 45);
      expect(setupState().plannedSeconds, 2700);
    });

    test('selecting a category keeps the duration', () {
      setup().stepPlannedMinutes(1);
      setup().selectCategory(FocusCategory.programming);
      expect(setupState().category, FocusCategory.programming);
      expect(setupState().plannedMinutes, 30);
    });

    test('start persists the choices and returns the new session', () async {
      setup().selectCategory(FocusCategory.meditation);
      setup().stepPlannedMinutes(1);
      final result = done(await setup().start());
      expect(result.message, 'Fokus gestartet');
      final session = (await repository().findOpen())!;
      expect(result.sessionId, session.id);
      expect(session.category, FocusCategory.meditation);
      expect(session.plannedSeconds, 1800);
      expect(session.status, FocusStatus.running);
      expect(setupState().submitting, isFalse);
    });

    test('a start while a session is open names the open session', () async {
      final openId = await start();
      final result = failed(await setup().start());
      final failure = result.failure as ConflictFailure;
      expect(failure.kind, ConflictKind.openFocusSession);
      expect(failure.relatedEntityId, openId);
      expect(result.message, 'Es läuft bereits eine Fokus-Sitzung.');
      expect(setupState().failure, same(failure));
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        hasLength(1),
      );
    });

    test('a double tap starts exactly one session', () async {
      final results = await Future.wait([setup().start(), setup().start()]);
      expect(results.whereType<FocusActionDone>(), hasLength(1));
      expect(results.whereType<FocusActionIgnored>(), hasLength(1));
      expect(
        await harness.database.select(harness.database.focusSessions).get(),
        hasLength(1),
      );
    });

    test('a retry after a failure reuses the command id; a later start gets a new one', () async {
      final flaky = _FlakyRepository(
        database: harness.database,
        runner: harness.runner,
        failures: 1,
      );
      final retryContainer = containerWith(
        extra: [focusRepositoryProvider.overrideWithValue(flaky)],
      );
      retryContainer.listen(focusSetupProvider, (_, _) {});
      final controller = retryContainer.read(focusSetupProvider.notifier);

      final first = failed(await controller.start());
      expect(first.failure, isA<StorageFailure>());
      expect(
        retryContainer.read(focusSetupProvider).failure,
        isA<StorageFailure>(),
      );
      expect(retryContainer.read(focusSetupProvider).submitting, isFalse);
      expect(
        retryContainer.read(focusSetupProvider).plannedMinutes,
        25,
        reason: 'the choices are kept',
      );

      done(await controller.start());
      expect(flaky.startIds, hasLength(2));
      expect(flaky.startIds[0], flaky.startIds[1], reason: 'same id on retry');
      expect(retryContainer.read(focusSetupProvider).failure, isNull);

      // Finish it and start another one: that is a new action, a new id.
      final openId = (await flaky.findOpen())!.id;
      advance(10);
      await flaky.save(commandId: harness.ids.newId(), id: openId);
      done(await controller.start());
      expect(flaky.startIds, hasLength(3));
      expect(flaky.startIds[2], isNot(flaky.startIds[0]));
    });

    test(
      'changing the choices after a failure is a different request (new id)',
      () async {
        final flaky = _FlakyRepository(
          database: harness.database,
          runner: harness.runner,
          failures: 1,
        );
        final retryContainer = containerWith(
          extra: [focusRepositoryProvider.overrideWithValue(flaky)],
        );
        retryContainer.listen(focusSetupProvider, (_, _) {});
        final controller = retryContainer.read(focusSetupProvider.notifier);
        failed(await controller.start());
        controller.stepPlannedMinutes(1);
        done(await controller.start());
        expect(flaky.startIds[0], isNot(flaky.startIds[1]));
      },
    );

    test('the state is auto-disposed with its screen', () async {
      final fresh = harness.createContainer();
      final subscription = fresh.listen(focusSetupProvider, (_, _) {});
      fresh.read(focusSetupProvider.notifier).stepPlannedMinutes(1);
      expect(fresh.read(focusSetupProvider).plannedMinutes, 30);
      subscription.close();
      await settle();
      fresh.listen(focusSetupProvider, (_, _) {});
      expect(fresh.read(focusSetupProvider).plannedMinutes, 25);
    });
  });
}
