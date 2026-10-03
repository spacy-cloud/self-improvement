import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/feedback/feedback_service.dart';
import 'package:self_improvement/core/modules/module_id.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/body/domain/weight_entry.dart';
import 'package:self_improvement/features/focus/application/workout_providers.dart';
import 'package:self_improvement/features/focus/domain/training_category.dart';
import 'package:self_improvement/features/focus/domain/workout_entry.dart';
import 'package:self_improvement/features/nutrition/application/water_providers.dart';
import 'package:self_improvement/features/tasks/application/task_providers.dart';
import 'package:self_improvement/features/tasks/domain/task.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/dashboard_test_kit.dart';

/// A day after the profile start: no welcome, the real dashboard.
final LocalDate _secondDay = LocalDate(2026, 10, 2);

WeightDraft _weight(DateTime at, {int grams = 71500}) =>
    WeightDraft(weightGrams: grams, occurredAtUtc: at);

void main() {
  testWidgets('(AT01, C04) a saved weight updates ring, streak, XP and card at once and the '
      'dashboard shows no feedback of its own', (tester) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    final fixture = await pumpHome(tester, harness, realWeightCard: true);
    final semantics = tester.ensureSemantics();
    expect(find.text('0 von 5'), findsOneWidget);

    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);

    expect(find.text('1 von 5'), findsOneWidget);
    expect(find.text('Du hast heute 1 von 5 Zielen erreicht.'), findsOneWidget);
    expect(find.bySemanticsLabel('1 von 5 Zielen erreicht'), findsOneWidget);
    expect(find.textContaining('71,5'), findsOneWidget);
    expect(find.text('10 / 100 XP'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Streak: 1 Tag in Folge, öffnen'),
      findsOneWidget,
    );
    // The saving flow owns the feedback; the dashboard shows only the data.
    expect(fixture.feedback.events, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'deleting the entry and undoing it restores every number (Create/Delete/'
    'Undo, C04)',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness, realWeightCard: true);
      final weights = fixture.container.read(weightRepositoryProvider);
      final created = (await tester.runCommand(
        () => weights.create(
          commandId: 'w1',
          draft: _weight(harness.clock.nowUtc()),
        ),
      ));
      await settle(tester);
      expect(find.text('1 von 5'), findsOneWidget);

      final deleted = await tester.runCommand(
        () => weights.delete(commandId: 'd1', id: created.entityId!),
      );
      await settle(tester);
      expect(find.text('0 von 5'), findsOneWidget);
      expect(find.text('0 / 100 XP'), findsOneWidget);
      expect(find.text('Noch keine Messung'), findsOneWidget);

      expect(deleted.undo, isNotNull);
      await tester.runCommand(() => deleted.undo!.run('u1'));
      await settle(tester);
      expect(find.text('1 von 5'), findsOneWidget);
      expect(find.text('10 / 100 XP'), findsOneWidget);
      expect(find.textContaining('71,5'), findsOneWidget);
    },
  );

  testWidgets(
    '(AT23) correcting the past changes ring, streak and the longest streak '
    'consistently',
    (tester) async {
      final harness = await createHarness(
        tester,
        startedOn: LocalDate(2026, 9, 20),
      );
      final fixture = await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      final weights = fixture.container.read(weightRepositoryProvider);
      final ids = <String, String>{};
      for (final (name, at) in [
        ('today', DateTime.utc(2026, 10, 3, 6)),
        ('yesterday', DateTime.utc(2026, 10, 2, 6)),
        ('before', DateTime.utc(2026, 10, 1, 6)),
      ]) {
        final outcome = await tester.runCommand(
          () => weights.create(commandId: name, draft: _weight(at)),
        );
        ids[name] = outcome.entityId!;
      }
      await settle(tester);
      expect(
        find.bySemanticsLabel('Streak: 3 Tage in Folge, öffnen'),
        findsOneWidget,
      );
      expect(find.text('30 / 100 XP'), findsOneWidget);

      // The entry of yesterday turns out to be wrong and is deleted.
      await tester.runCommand(
        () => weights.delete(commandId: 'fix', id: ids['yesterday']!),
      );
      await settle(tester);
      expect(
        find.bySemanticsLabel('Streak: 1 Tag in Folge, öffnen'),
        findsOneWidget,
      );
      expect(find.text('20 / 100 XP'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);

      fixture.router.go('/streak');
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.bySemanticsLabel('1 Tag in Folge'), findsOneWidget);
      expect(find.bySemanticsLabel('Längste Streak, 1 Tag'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Aktive Tage gesamt, 2 Tage'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    '(AT13) completing, reopening and completing a task again does not pile up XP',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final fixture = await pumpHome(tester, harness);
      final tasks = fixture.container.read(taskRepositoryProvider);
      final created = await tester.runCommand(
        () => tasks.create(
          commandId: 't1',
          draft: const TaskDraft(title: 'Steuer machen'),
        ),
      );
      final id = created.entityId!;
      expect(find.text('0 / 100 XP'), findsOneWidget);

      await tester.runCommand(
        () => tasks.setCompleted(commandId: 'c1', id: id, completed: true),
      );
      await settle(tester);
      expect(find.text('10 / 100 XP'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);

      await tester.runCommand(
        () => tasks.setCompleted(commandId: 'c2', id: id, completed: false),
      );
      await settle(tester);
      expect(find.text('0 / 100 XP'), findsOneWidget);
      expect(find.text('0 von 5'), findsOneWidget);

      await tester.runCommand(
        () => tasks.setCompleted(commandId: 'c3', id: id, completed: true),
      );
      await settle(tester);
      expect(find.text('10 / 100 XP'), findsOneWidget);
      expect(find.text('1 von 5'), findsOneWidget);
    },
  );

  testWidgets('(AT20) a logged workout adds its XP but neither changes the day ring nor the '
      'streak', (tester) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    final fixture = await pumpHome(tester, harness);
    final semantics = tester.ensureSemantics();
    await tester.runCommand(
      () => fixture.container
          .read(workoutRepositoryProvider)
          .create(
            commandId: 'wo1',
            draft: WorkoutDraft(
              category: TrainingCategory.strength,
              durationMinutes: 45,
              occurredAtUtc: harness.clock.nowUtc(),
            ),
          ),
    );
    await settle(tester);
    expect(find.text('15 / 100 XP'), findsOneWidget);
    expect(find.text('0 von 5'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Streak: 0 Tage in Folge, öffnen'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('(AT10) water from a card: one tap, the numbers follow, undo takes amount and '
      'XP back', (tester) async {
    final harness = await createHarness(tester, startedOn: _secondDay);
    final fixture = await pumpHome(
      tester,
      harness,
      onWaterQuickAdd: (ref) async {
        final outcome = await ref
            .read(waterRepositoryProvider)
            .quickAdd(
              commandId: ref.read(idGeneratorProvider).newId(),
              amountMl: 250,
            );
        ref
            .read(feedbackServiceProvider)
            .showSaved('+250 ml hinzugefügt', undo: outcome.undo);
      },
    );
    expect(find.text('0 / 100 XP'), findsOneWidget);

    // One action from the dashboard to the commit.
    await tester.tap(find.text('+250 ml'));
    await settle(tester);
    expect(fixture.feedback.last?.kind, 'saved');
    expect(find.text('5 / 100 XP'), findsOneWidget);
    expect(fixture.log.entries, ['quick:water']);

    await tester.runCommand(() => fixture.feedback.last!.undo!.perform());
    await settle(tester);
    expect(find.text('0 / 100 XP'), findsOneWidget);
  });

  testWidgets('(date change, AT22) a new day updates the date, restarts the ring and keeps the streak that '
      'is still alive', (tester) async {
    final harness = await createHarness(
      tester,
      startedOn: LocalDate(2026, 9, 20),
    );
    final fixture = await pumpHome(tester, harness);
    final semantics = tester.ensureSemantics();
    await tester.runCommand(
      () => fixture.container
          .read(weightRepositoryProvider)
          .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
    );
    await settle(tester);
    expect(find.text('Samstag, 3. Oktober'), findsOneWidget);
    expect(find.text('1 von 5'), findsOneWidget);

    harness.clock.advance(const Duration(days: 1));
    fixture.container.read(todayProvider.notifier).refresh();
    await settle(tester);

    expect(find.text('Sonntag, 4. Oktober'), findsOneWidget);
    expect(find.text('Samstag, 3. Oktober'), findsNothing);
    expect(find.text('0 von 5'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Streak: 1 Tag in Folge, öffnen'),
      findsOneWidget,
    );
    expect(find.text('10 / 100 XP'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
    '(AT22) a day without a fulfilled goal ends the streak after the day change',
    (tester) async {
      final harness = await createHarness(
        tester,
        startedOn: LocalDate(2026, 9, 20),
      );
      final fixture = await pumpHome(tester, harness);
      final semantics = tester.ensureSemantics();
      await tester.runCommand(
        () => fixture.container
            .read(weightRepositoryProvider)
            .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
      );
      await settle(tester);

      harness.clock.advance(const Duration(days: 2));
      fixture.container.read(todayProvider.notifier).refresh();
      await settle(tester);
      expect(find.text('Montag, 5. Oktober'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Streak: 0 Tage in Folge, öffnen'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    '(AT02, C04) after a restart module state, card order and numbers are the same',
    (tester) async {
      final harness = await createHarness(tester, startedOn: _secondDay);
      final first = await pumpHome(tester, harness);
      final repository = first.container.read(dashboardCardRepositoryProvider);
      await tester.runCommand(
        () => repository.move(commandId: 'm1', cardId: 'tasks', toIndex: 0),
      );
      await tester.runCommand(
        () => repository.setVisible(
          commandId: 'v1',
          cardId: 'focus',
          visible: false,
        ),
      );
      await tester.runCommand(
        () => first.container
            .read(moduleManagerProvider)
            .setEnabled(
              commandId: 'off',
              module: ModuleId.nutrition,
              enabled: false,
            ),
      );
      await tester.runCommand(
        () => first.container
            .read(weightRepositoryProvider)
            .create(commandId: 'w1', draft: _weight(harness.clock.nowUtc())),
      );

      // The process ends; a new one opens the same database.
      final second = await pumpHome(tester, harness);
      Offset at(String title) => tester.getTopLeft(find.text(title));
      expect(find.text('Fokus'), findsNothing);
      expect(find.text('Wasser'), findsNothing);
      expect(find.text('Ernährung'), findsNothing);
      expect(at('Aufgaben').dy, lessThan(at('Schritte').dy));
      expect(find.text('1 von 4'), findsOneWidget);
      expect(find.text('10 / 100 XP'), findsOneWidget);
      expect(identical(first.container, second.container), isFalse);
    },
  );
}
