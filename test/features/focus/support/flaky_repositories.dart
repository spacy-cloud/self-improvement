import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/focus/application/focus_providers.dart';
import 'package:self_improvement/features/focus/data/focus_repository.dart';
import 'package:self_improvement/features/focus/domain/focus_category.dart';

/// A focus repository whose first calls of start, pause and updateNote fail
/// like a broken disk. Every attempt records its command id, so a test can
/// prove that a retry reused it.
final class FlakyFocusRepository extends FocusRepository {
  FlakyFocusRepository({
    required super.database,
    required super.runner,
    this.startFailures = 0,
    this.pauseFailures = 0,
    this.noteFailures = 0,
  });

  int startFailures;
  int pauseFailures;
  int noteFailures;

  final List<String> startIds = [];
  final List<String> pauseIds = [];
  final List<String> noteIds = [];

  @override
  Future<CommandOutcome> start({
    required String commandId,
    required FocusCategory category,
    required int plannedSeconds,
  }) {
    startIds.add(commandId);
    if (startFailures > 0) {
      startFailures--;
      throw const StorageFailure();
    }
    return super.start(
      commandId: commandId,
      category: category,
      plannedSeconds: plannedSeconds,
    );
  }

  @override
  Future<CommandOutcome> pause({
    required String commandId,
    required String id,
  }) {
    pauseIds.add(commandId);
    if (pauseFailures > 0) {
      pauseFailures--;
      throw const StorageFailure();
    }
    return super.pause(commandId: commandId, id: id);
  }

  @override
  Future<CommandOutcome> updateNote({
    required String commandId,
    required String id,
    required String? note,
    int? expectedRowVersion,
  }) {
    noteIds.add(commandId);
    if (noteFailures > 0) {
      noteFailures--;
      throw const StorageFailure();
    }
    return super.updateNote(
      commandId: commandId,
      id: id,
      note: note,
      expectedRowVersion: expectedRowVersion,
    );
  }
}

/// Overrides the focus repository with a [FlakyFocusRepository]; [onCreate]
/// hands the instance to the test.
Override flakyFocusRepository(
  void Function(FlakyFocusRepository repository) onCreate, {
  int startFailures = 0,
  int pauseFailures = 0,
  int noteFailures = 0,
}) => focusRepositoryProvider.overrideWith((ref) {
  final repository = FlakyFocusRepository(
    database: ref.watch(appDatabaseProvider),
    runner: ref.watch(commandRunnerProvider),
    startFailures: startFailures,
    pauseFailures: pauseFailures,
    noteFailures: noteFailures,
  );
  onCreate(repository);
  return repository;
});
