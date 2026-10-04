import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/commands/command_runner.dart';
import 'package:self_improvement/core/commands/id_generator.dart';
import 'package:self_improvement/core/errors/app_failure.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';

void main() {
  UndoPresentation presentation(
    Future<CommandOutcome> Function(String id) run,
    List<String> ids,
  ) => UndoPresentation(
    action: UndoAction(
      run: (id) {
        ids.add(id);
        return run(id);
      },
    ),
    ids: SequentialIdGenerator(),
  );

  test('performing the undo runs one new command with a fresh id', () async {
    final ids = <String>[];
    final undo = presentation((id) async => const CommandOutcome(), ids);
    expect(await undo.perform(), UndoResult.undone);
    expect(ids, ['00000000-0000-4000-8000-000000000001']);
    expect(undo.used, isTrue);
  });

  test('a double tap runs the undo only once', () async {
    final ids = <String>[];
    final undo = presentation((id) async => const CommandOutcome(), ids);
    final results = await Future.wait([undo.perform(), undo.perform()]);
    expect(ids, hasLength(1));
    expect(results.every((r) => r == UndoResult.undone), isTrue);
  });

  test(
    'a conflict is reported with the German message and changes nothing',
    () async {
      final undo = presentation(
        (id) async => throw const ConflictFailure(ConflictKind.staleVersion),
        [],
      );
      expect(await undo.perform(), UndoResult.conflict);
      expect(undo.failureMessage, 'Der Eintrag wurde inzwischen geändert.');
    },
  );

  test('other failures are reported as failed', () async {
    final undo = presentation((id) async => throw const StorageFailure(), []);
    expect(await undo.perform(), UndoResult.failed);
    expect(undo.failureMessage, contains('Speichern fehlgeschlagen'));
    expect(await undo.perform(), UndoResult.failed);
  });

  test('the recording service keeps messages and undo presentations', () async {
    final feedback = RecordingFeedbackService(ids: SequentialIdGenerator());
    feedback
      ..showSaved(
        'Gewicht gespeichert',
        undo: UndoAction(run: (id) async => const CommandOutcome()),
      )
      ..showError('Fehler')
      ..showInfo('Hinweis');
    expect(feedback.events.map((e) => e.kind), ['saved', 'error', 'info']);
    expect(feedback.events.first.message, 'Gewicht gespeichert');
    expect(await feedback.events.first.undo!.perform(), UndoResult.undone);
    expect(feedback.last!.kind, 'info');
    expect(feedback.events[1].undo, isNull);
  });

  test('an error can carry a retry action that the recorder exposes', () {
    final feedback = RecordingFeedbackService(ids: SequentialIdGenerator());
    var retried = 0;
    feedback
      ..showError('Speichern fehlgeschlagen.', onRetry: () => retried++)
      ..showError('Ohne Aktion');
    expect(feedback.events.first.onRetry, isNotNull);
    feedback.events.first.onRetry!();
    expect(retried, 1);
    expect(feedback.events.last.onRetry, isNull);
  });
}
