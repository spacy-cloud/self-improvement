import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/core/design/design.dart' hide HabitIcon;
import 'package:self_improvement/features/tasks/application/habit_day_providers.dart';
import 'package:self_improvement/features/tasks/application/habit_providers.dart';
import 'package:self_improvement/features/tasks/domain/task_priority.dart';
import 'package:self_improvement/features/tasks/domain/today_checklist.dart';
import 'package:self_improvement/features/tasks/presentation/checklist_row.dart';
import 'package:self_improvement/features/tasks/presentation/habits_day_view.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_dashboard_card.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/task_test_support.dart';
import '../support/ui_support.dart';

/// The habits on the Home card "Heute abhaken" (BS-110): shown, ticked with
/// one tap through the commands of the habits tab, in step with the tab,
/// told apart from the tasks, and the states of the card.
void main() {
  setUpAll(allowMultipleDatabases);

  final today = LocalDate(2026, 10, 3);
  final yesterday = LocalDate(2026, 10, 2);

  Future<TasksUiEnv> envWithHabits(
    WidgetTester tester, {
    List<String> titles = const ['Lesen', 'Dehnen'],
  }) async {
    final env = await createTasksUiEnv(tester);
    env.moveTo(LocalDate(2026, 9, 28));
    for (final title in titles) {
      await env.addHabit(tester, title);
    }
    env.moveTo(today);
    return env;
  }

  Future<GoRouter> pumpCard(
    WidgetTester tester,
    TasksUiEnv env, {
    Size size = const Size(393, 852),
    double textScale = 1.0,
    bool readOnly = false,
  }) => pumpTasksRouter(
    tester,
    env,
    initialLocation: '/',
    home: cardHost(readOnly: readOnly),
    size: size,
    textScale: textScale,
  );

  Future<void> waitForFeedback(
    WidgetTester tester,
    TasksUiEnv env, [
    int count = 1,
  ]) async {
    await tester.pumpUntil(() => env.feedback.events.length >= count);
    await pumpData(tester);
  }

  /// The box of the row with [label] ("Gewohnheit Lesen", "Aufgabe Steuer").
  Finder boxOf(String label) => find.byWidgetPredicate(
    (widget) => widget is RoundCheckbox && widget.semanticLabel == label,
    description: 'the box "$label"',
  );

  bool isChecked(WidgetTester tester, String label) =>
      tester.widget<RoundCheckbox>(boxOf(label)).value;

  Future<String> habitId(
    WidgetTester tester,
    TasksUiEnv env,
    String title,
  ) async =>
      (await env.allHabits(tester)).firstWhere((h) => h.title == title).id;

  group('habits on the card', () {
    testWidgets(
      'a created habit shows on the card with its series and its kind (T02, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester);
        final lesen = await habitId(tester, env, 'Lesen');
        for (final date in [
          LocalDate(2026, 9, 30),
          LocalDate(2026, 10, 1),
          yesterday,
        ]) {
          await env.checkHabit(tester, lesen, date);
        }
        await pumpCard(tester, env);

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(find.text('0 von 2 erledigt'), findsOneWidget);
        expect(find.text('Lesen'), findsOneWidget);
        expect(find.text('Dehnen'), findsOneWidget);
        // Series of "Lesen": three days in a row, today is still open and
        // does not break it.
        expect(find.text('3 Tage in Folge'), findsOneWidget);
        expect(find.text('Noch keine Serie'), findsOneWidget);
        expect(find.text('Gewohnheit'), findsNWidgets(2), reason: 'type chips');
        expect(find.byType(RoundCheckbox), findsNWidgets(2));
      },
    );

    testWidgets(
      'one tap checks the habit on the card, offers undo, and undo takes it back (AT21, T02, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpCard(tester, env);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        final saved = env.feedback.last!;
        expect(saved.kind, 'saved');
        expect(saved.message, 'Abgehakt');
        expect(saved.undo, isNotNull);
        final id = await habitId(tester, env, 'Lesen');
        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNotNull,
          reason: 'a real check in the database',
        );
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(find.text('1 von 1 erledigt'), findsOneWidget);
        expect(find.text('1 Tag in Folge · erledigt'), findsOneWidget);
        expect(await tester.runAsync(env.harness.totalXp), 5);

        final result = await tester.runAsync(saved.undo!.perform);
        expect(result, isNotNull);
        await pumpData(tester);
        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNull,
        );
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
        expect(find.text('0 von 1 erledigt'), findsOneWidget);
        expect(await tester.runAsync(env.harness.totalXp), 0);
      },
    );

    testWidgets(
      'a habit that is already checked is drawn checked, struck through and in words (T02, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
        final lesen = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, lesen, yesterday);
        await env.checkHabit(tester, lesen, today);
        await pumpCard(tester, env);

        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isFalse);
        expect(
          tester.widget<Text>(find.text('Lesen')).style!.decoration,
          TextDecoration.lineThrough,
        );
        expect(
          tester.widget<Text>(find.text('Dehnen')).style!.decoration,
          isNull,
        );
        expect(find.text('2 Tage in Folge · erledigt'), findsOneWidget);
        expect(find.text('1 von 2 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'the box of a checked habit removes the check, with undo (AT21, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        final id = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, id, today);
        await pumpCard(tester, env);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        expect(env.feedback.last!.message, 'Haken entfernt');
        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNull,
        );
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);

        await tester.runAsync(env.feedback.last!.undo!.perform);
        await pumpData(tester);
        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNotNull,
        );
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
      },
    );

    testWidgets(
      'a double tap runs one command with one id and checks once (AT12, C05, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpCard(tester, env);
        final gate = Completer<void>();
        env.habits.gate = gate;

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await tester.pump();
        await tester.tap(boxOf('Gewohnheit Lesen'), warnIfMissed: false);
        await tester.pump();
        gate.complete();
        await waitForFeedback(tester, env);

        expect(env.habits.commandIds, hasLength(1));
        expect(env.feedback.events, hasLength(1));
        final id = await habitId(tester, env, 'Lesen');
        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNotNull,
        );
        expect(await tester.runAsync(env.harness.totalXp), 5);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
      },
    );

    testWidgets(
      'while the command runs the box is locked, so a second tap cannot start another (AT12, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpCard(tester, env);
        final gate = Completer<void>();
        env.habits.gate = gate;

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await tester.pump();

        expect(
          tester.widget<RoundCheckbox>(boxOf('Gewohnheit Lesen')).onChanged,
          isNull,
        );
        gate.complete();
        await waitForFeedback(tester, env);
        expect(
          tester.widget<RoundCheckbox>(boxOf('Gewohnheit Lesen')).onChanged,
          isNotNull,
        );
      },
    );

    testWidgets(
      'a failed check keeps the habit open; the retry reuses the command id and checks once (AT27, AT12, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpCard(tester, env);
        env.habits.failNext = 1;

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        final error = env.feedback.last!;
        expect(error.kind, 'error');
        expect(error.message, contains('Speichern fehlgeschlagen'));
        expect(error.onRetry, isNotNull);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
        expect(find.text('0 von 1 erledigt'), findsOneWidget);
        expect(await tester.runAsync(env.harness.totalXp), 0);

        error.onRetry!();
        await waitForFeedback(tester, env, 2);

        expect(env.habits.commandIds, hasLength(2));
        expect(env.habits.commandIds[0], env.habits.commandIds[1]);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(await tester.runAsync(env.harness.totalXp), 5);
      },
    );

    testWidgets('tapping the title opens the habit (BS-110)', (tester) async {
      final env = await envWithHabits(tester, titles: ['Lesen']);
      final router = await pumpCard(tester, env);

      await tester.tap(find.text('Lesen'));
      await tester.pumpAndSettle();

      expect(find.text('Archivieren'), findsOneWidget, reason: 'the detail');
      expect(router.canPop(), isTrue);
    });

    testWidgets(
      'a new day shows the habit open again without a restart (AT25, AT21, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        final id = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, id, today);
        await pumpCard(tester, env);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);

        env.moveTo(today.addDays(1));
        await pumpData(tester);

        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
        expect(find.text('0 von 1 erledigt'), findsOneWidget);
        expect(find.text('1 Tag in Folge'), findsOneWidget);
      },
    );

    testWidgets(
      'a habit that is archived from tomorrow still shows, with the hint (T02, BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        final id = await habitId(tester, env, 'Lesen');
        await tester.runAsync(
          () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
        );
        await pumpCard(tester, env);

        expect(find.text('Lesen'), findsOneWidget);
        expect(
          find.text('Noch keine Serie · Ab morgen archiviert'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a load error of the habits shows the error state with a retry (BS-110)',
      (tester) async {
        var calls = 0;
        final env = await createTasksUiEnv(
          tester,
          extraOverrides: [
            habitsProvider.overrideWith((ref) {
              calls++;
              return calls == 1
                  ? Stream.error(StateError('disk'))
                  : ref.watch(habitRepositoryProvider).watchAll();
            }),
          ],
        );
        env.moveTo(LocalDate(2026, 9, 28));
        await env.addHabit(tester, 'Lesen');
        env.moveTo(today);
        await pumpCard(tester, env);

        expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
        await tester.tap(find.text('Erneut versuchen'));
        await pumpData(tester);
        await pumpData(tester);
        expect(find.text('Lesen'), findsOneWidget);
      },
    );
  });

  group('in step with the habits tab', () {
    /// The card above the habit list of the tab, on one tall screen: both read
    /// the same streams, so one reacts to a tick in the other without a
    /// navigation.
    Widget cardAboveTab() => Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: const <Widget>[
            TasksDashboardCard(),
            SizedBox(height: 900, child: HabitsDayView()),
          ],
        ),
      ),
    );

    Future<void> pumpBoth(WidgetTester tester, TasksUiEnv env) async {
      await pumpApp(
        tester,
        cardAboveTab(),
        container: env.container,
        size: const Size(393, 2400),
      );
      await pumpData(tester);
    }

    testWidgets(
      'a tick on the card shows in the habit list at once (BS-110, AT21, C04)',
      (tester) async {
        final env = await envWithHabits(tester);
        await pumpBoth(tester, env);
        expect(isChecked(tester, 'Lesen'), isFalse, reason: 'the tab');
        expect(
          isChecked(tester, 'Gewohnheit Lesen'),
          isFalse,
          reason: 'the card',
        );

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(isChecked(tester, 'Lesen'), isTrue, reason: 'the tab follows');
        expect(isChecked(tester, 'Dehnen'), isFalse);
        expect(
          find.text('1 von 2 erledigt', findRichText: true),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'a tick in the habit list shows on the card at once (BS-110, AT21, C04)',
      (tester) async {
        final env = await envWithHabits(tester);
        await pumpBoth(tester, env);

        await tester.tap(boxOf('Dehnen'));
        await waitForFeedback(tester, env);

        expect(isChecked(tester, 'Dehnen'), isTrue, reason: 'the tab');
        expect(
          isChecked(tester, 'Gewohnheit Dehnen'),
          isTrue,
          reason: 'the card',
        );
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
        expect(
          find.text('1 von 2 erledigt', findRichText: true),
          findsNWidgets(2),
        );
      },
    );

    testWidgets(
      'the undo of a tick on the card is seen in the habit list, and the other way round (BS-110, AT21)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpBoth(tester, env);

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);
        await tester.runAsync(env.feedback.last!.undo!.perform);
        await pumpData(tester);
        expect(isChecked(tester, 'Lesen'), isFalse);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);

        await tester.tap(boxOf('Lesen'));
        await waitForFeedback(tester, env, 2);
        await tester.runAsync(env.feedback.last!.undo!.perform);
        await pumpData(tester);
        expect(isChecked(tester, 'Lesen'), isFalse);
        expect(isChecked(tester, 'Gewohnheit Lesen'), isFalse);
      },
    );

    testWidgets(
      'a tick on the card is there when the habits tab opens, and the tick of the tab is there when Home opens again (BS-110, AT21)',
      (tester) async {
        final env = await envWithHabits(tester);
        final router = await pumpTasksRouter(
          tester,
          env,
          initialLocation: '/',
          home: cardHost(),
        );

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);
        router.go('/habits');
        await tester.pumpAndSettle();
        await pumpData(tester);

        expect(
          find.text('1 von 2 erledigt', findRichText: true),
          findsOneWidget,
        );
        expect(isChecked(tester, 'Lesen'), isTrue);
        expect(isChecked(tester, 'Dehnen'), isFalse);

        await tester.tap(boxOf('Dehnen'));
        await waitForFeedback(tester, env, 2);
        router.go('/');
        await tester.pumpAndSettle();
        await pumpData(tester);

        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isTrue);
        expect(find.text('2 von 2 erledigt'), findsOneWidget);
      },
    );

    testWidgets(
      'the card shows today and ticks today, whatever day the habits tab shows (BS-110, AT21)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        final id = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, id, yesterday);
        env.container.read(selectedHabitDayProvider.notifier).select(yesterday);
        await pumpCard(tester, env);

        expect(
          isChecked(tester, 'Gewohnheit Lesen'),
          isFalse,
          reason: 'yesterday is checked, today is not',
        );
        expect(find.text('0 von 1 erledigt'), findsOneWidget);

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        expect(
          await tester.runAsync(() => env.habits.findCheck(id, today)),
          isNotNull,
          reason: 'the tick belongs to today',
        );
        expect(
          env.container.read(selectedHabitDayProvider),
          yesterday,
          reason: 'the selection of the tab is not touched',
        );
      },
    );
  });

  group('tasks and habits are told apart', () {
    Future<TasksUiEnv> mixedEnv(WidgetTester tester) async {
      final env = await envWithHabits(tester, titles: ['Lesen']);
      final lesen = await habitId(tester, env, 'Lesen');
      for (final date in [
        LocalDate(2026, 9, 28),
        LocalDate(2026, 9, 29),
        LocalDate(2026, 9, 30),
        LocalDate(2026, 10, 1),
        yesterday,
      ]) {
        await env.checkHabit(tester, lesen, date);
      }
      await env.addTask(
        tester,
        'Steuer machen',
        priority: TaskPriority.high,
        dueDate: today,
      );
      return env;
    }

    testWidgets(
      'a task has a square box and a habit a round one, and each wears its kind as a word (BS-110, AT34)',
      (tester) async {
        final env = await mixedEnv(tester);
        await pumpCard(tester, env);

        expect(
          tester.widget<RoundCheckbox>(boxOf('Aufgabe Steuer machen')).squared,
          isTrue,
        );
        expect(
          tester.widget<RoundCheckbox>(boxOf('Gewohnheit Lesen')).squared,
          isFalse,
        );
        expect(find.byType(EntryTypeChip), findsNWidgets(2));
        expect(find.text('Aufgabe'), findsOneWidget);
        expect(find.text('Gewohnheit'), findsOneWidget);
        expect(find.byIcon(AppIcon.task.data), findsOneWidget);
        expect(find.byIcon(AppIcon.habit.data), findsOneWidget);
      },
    );

    testWidgets(
      'the tasks come first, the habits below them, the chips on the right of the text (BS-110)',
      (tester) async {
        final env = await mixedEnv(tester);
        await pumpCard(tester, env);

        final task = tester.getTopLeft(find.text('Steuer machen'));
        final habit = tester.getTopLeft(find.text('Lesen'));
        expect(habit.dy, greaterThan(task.dy));
        final chip = tester.getTopLeft(find.text('Gewohnheit'));
        expect(chip.dx, greaterThan(habit.dx + 60));
        expect(
          (tester.getCenter(find.text('Gewohnheit')).dy -
                  tester.getCenter(find.text('Lesen')).dy)
              .abs(),
          lessThan(20),
          reason: 'the chip sits in the line of its row',
        );
      },
    );

    testWidgets(
      'the kind is part of what a screen reader says: box and row (BS-110, AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await mixedEnv(tester);
        await pumpCard(tester, env);

        // The box of a habit: name with kind, state with the day.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Gewohnheit Lesen')),
          isSemantics(
            hasCheckedState: true,
            isChecked: false,
            hasEnabledState: true,
            isEnabled: true,
            value: 'heute offen',
          ),
        );
        // The row of a habit: one sentence with the series, and what a tap does.
        final row = tester.getSemantics(
          find.bySemanticsLabel(
            'Gewohnheit Lesen, heute offen, 5 Tage in Folge',
          ),
        );
        expect(row, isSemantics(isButton: true, hasTapAction: true));
        expect(row.getSemanticsData().hint, 'Öffnet die Gewohnheit');
        // The box and the row of a task.
        expect(
          tester.getSemantics(find.bySemanticsLabel('Aufgabe Steuer machen')),
          isSemantics(hasCheckedState: true, isChecked: false, value: 'offen'),
        );
        expect(
          find.bySemanticsLabel(
            'Aufgabe Steuer machen, Priorität Hoch, Heute fällig, offen',
          ),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Heute abhaken'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets(
      'a checked habit is spoken as done today, the state changes with the tick (BS-110, AT34)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = await mixedEnv(tester);
        await pumpCard(tester, env);

        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env);

        expect(
          tester.getSemantics(find.bySemanticsLabel('Gewohnheit Lesen')),
          isSemantics(
            hasCheckedState: true,
            isChecked: true,
            value: 'heute erledigt',
          ),
        );
        expect(
          find.bySemanticsLabel(
            'Gewohnheit Lesen, heute erledigt, 6 Tage in Folge',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'both kinds can be ticked in the same list, each through its own command (BS-110, T01, T02)',
      (tester) async {
        final env = await mixedEnv(tester);
        await pumpCard(tester, env);
        final before = (await tester.runAsync(env.harness.totalXp))!;

        await tester.tap(boxOf('Aufgabe Steuer machen'));
        await waitForFeedback(tester, env);
        await tester.tap(boxOf('Gewohnheit Lesen'));
        await waitForFeedback(tester, env, 2);

        expect(env.feedback.events.map((e) => e.message), [
          'Aufgabe erledigt',
          'Abgehakt',
        ]);
        expect(env.tasks.commandIds, hasLength(1));
        expect(env.habits.commandIds, hasLength(1));
        expect(find.text('2 von 2 erledigt'), findsOneWidget);
        expect(
          await tester.runAsync(env.harness.totalXp),
          before + 15,
          reason: 'a task is worth 10 XP, a habit check 5',
        );
      },
    );
  });

  group('states of the card', () {
    testWidgets(
      'tasks but no habit yet: the way to the first habit is on the card (BS-110)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await env.addTask(tester, 'Steuer machen');
        final router = await pumpCard(tester, env);

        expect(find.text('Steuer machen'), findsOneWidget);
        expect(find.text('Noch keine Gewohnheit'), findsOneWidget);
        expect(
          find.text(
            'Lege eine tägliche Gewohnheit an und hake sie hier mit einem '
            'Tipp ab.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Gewohnheit anlegen'));
        await tester.pumpAndSettle();

        expect(find.text('Neue Gewohnheit'), findsOneWidget);
        expect(router.canPop(), isTrue);
      },
    );

    testWidgets(
      'only archived habits: the card says so and offers a new one (BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Alt']);
        final id = await habitId(tester, env, 'Alt');
        await tester.runAsync(
          () => env.habits.archive(commandId: env.harness.ids.newId(), id: id),
        );
        env.moveTo(today.addDays(1));
        await env.addTask(tester, 'Steuer machen');
        await pumpCard(tester, env);

        expect(find.text('Alt'), findsNothing);
        expect(find.text('Keine aktive Gewohnheit'), findsOneWidget);
        expect(find.text('Gewohnheit anlegen'), findsOneWidget);
      },
    );

    testWidgets(
      'neither task nor habit: one text and both ways to add (BS-110)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        final router = await pumpCard(tester, env);

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(find.byType(RoundCheckbox), findsNothing);
        expect(find.text('Aufgabe anlegen'), findsOneWidget);
        expect(find.text('Gewohnheit anlegen'), findsOneWidget);

        await tester.tap(find.text('Gewohnheit anlegen'));
        await tester.pumpAndSettle();
        expect(find.text('Neue Gewohnheit'), findsOneWidget);
        expect(router.canPop(), isTrue);
      },
    );

    testWidgets(
      'many habits: five are listed, the rest is one line that opens the habit list (BS-110)',
      (tester) async {
        final env = await envWithHabits(
          tester,
          titles: [for (var i = 1; i <= 8; i++) 'Gewohnheit $i'],
        );
        final id = await habitId(tester, env, 'Gewohnheit 7');
        await env.checkHabit(tester, id, today);
        final router = await pumpCard(tester, env);

        expect(find.byType(RoundCheckbox), findsNWidgets(dashboardHabitLimit));
        for (var i = 1; i <= 5; i++) {
          expect(find.text('Gewohnheit $i'), findsOneWidget);
        }
        expect(find.text('Gewohnheit 6'), findsNothing);
        expect(find.text('und 3 weitere Gewohnheiten'), findsOneWidget);
        // The count is about all of today's habits, listed or not.
        expect(find.text('1 von 8 erledigt'), findsOneWidget);

        await tester.tap(find.text('und 3 weitere Gewohnheiten'));
        await tester.pumpAndSettle();
        await pumpData(tester);

        expect(locationOf(router), '/habits');
        expect(find.text('Gewohnheit 8'), findsOneWidget);
      },
    );

    testWidgets(
      'one hidden habit says "weitere Gewohnheit", not "weitere Gewohnheiten" (BS-110)',
      (tester) async {
        final env = await envWithHabits(
          tester,
          titles: [for (var i = 1; i <= 6; i++) 'Gewohnheit $i'],
        );
        await pumpCard(tester, env);

        expect(find.text('und 1 weitere Gewohnheit'), findsOneWidget);
      },
    );

    testWidgets('exactly five habits show no rest line (BS-110)', (
      tester,
    ) async {
      final env = await envWithHabits(
        tester,
        titles: [for (var i = 1; i <= 5; i++) 'Gewohnheit $i'],
      );
      await pumpCard(tester, env);

      expect(find.byType(RoundCheckbox), findsNWidgets(5));
      expect(find.textContaining('weitere'), findsNothing);
    });

    testWidgets(
      'the rest lines of tasks and habits are two lines that open two lists (BS-110)',
      (tester) async {
        final env = await envWithHabits(
          tester,
          titles: [for (var i = 1; i <= 7; i++) 'Gewohnheit $i'],
        );
        for (var i = 1; i <= 5; i++) {
          await env.addTask(tester, 'Aufgabe $i');
        }
        final router = await pumpCard(tester, env, size: const Size(393, 2000));

        expect(find.text('und 2 weitere Aufgaben'), findsOneWidget);
        expect(find.text('und 2 weitere Gewohnheiten'), findsOneWidget);
        expect(find.text('0 von 12 erledigt'), findsOneWidget);

        await tester.tap(find.text('und 2 weitere Aufgaben'));
        await tester.pumpAndSettle();
        expect(locationOf(router), '/habits?tab=tasks');
      },
    );

    testWidgets(
      'everything done: every box is checked and the count says so (BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
        for (final habit in await env.allHabits(tester)) {
          await env.checkHabit(tester, habit.id, today);
        }
        await env.addTask(tester, 'Steuer machen');
        await pumpCard(tester, env);
        await tester.tap(boxOf('Aufgabe Steuer machen'));
        await waitForFeedback(tester, env);

        expect(
          tester
              .widgetList<RoundCheckbox>(find.byType(RoundCheckbox))
              .map((box) => box.value),
          [true, true, true],
        );
        expect(find.text('3 von 3 erledigt'), findsOneWidget);
        final colors = AppThemeVariant.light.colors;
        expect(
          tester.widget<Text>(find.text('3 von 3 erledigt')).style!.color,
          colors.primaryText,
        );
        final heading = find.ancestor(
          of: find.text('3 von 3 erledigt'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(
            of: heading.first,
            matching: find.byIcon(AppIcon.check.data),
          ),
          findsOneWidget,
          reason: 'a check mark next to the count, not only the colour',
        );
      },
    );

    testWidgets(
      'one missing is not "all done": no check mark, quiet colour (BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
        final lesen = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, lesen, today);
        await pumpCard(tester, env);

        final colors = AppThemeVariant.light.colors;
        expect(
          tester.widget<Text>(find.text('1 von 2 erledigt')).style!.color,
          colors.textSecondary,
        );
        final heading = find.ancestor(
          of: find.text('1 von 2 erledigt'),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(
            of: heading.first,
            matching: find.byIcon(AppIcon.check.data),
          ),
          findsNothing,
        );
      },
    );
  });

  group('read only (a day that cannot be changed, BS-93 later)', () {
    testWidgets(
      'the state is shown, no box can be changed and no command runs (BS-110)',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen', 'Dehnen']);
        final lesen = await habitId(tester, env, 'Lesen');
        await env.checkHabit(tester, lesen, today);
        await env.addTask(tester, 'Steuer machen');
        await pumpCard(tester, env, readOnly: true);

        expect(isChecked(tester, 'Gewohnheit Lesen'), isTrue);
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isFalse);
        expect(find.text('1 von 3 erledigt'), findsOneWidget);
        for (final box in tester.widgetList<RoundCheckbox>(
          find.byType(RoundCheckbox),
        )) {
          expect(box.onChanged, isNull, reason: box.semanticLabel);
        }

        await tester.tap(boxOf('Gewohnheit Dehnen'), warnIfMissed: false);
        await tester.tap(boxOf('Aufgabe Steuer machen'), warnIfMissed: false);
        await pumpData(tester);

        expect(env.habits.commandIds, isEmpty);
        expect(env.tasks.commandIds, isEmpty);
        expect(env.feedback.events, isEmpty);
        expect(isChecked(tester, 'Gewohnheit Dehnen'), isFalse);
      },
    );

    testWidgets('a read only box says it cannot be changed (BS-110, AT34)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final env = await envWithHabits(tester, titles: ['Lesen']);
      await pumpCard(tester, env, readOnly: true);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Gewohnheit Lesen')),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          hasEnabledState: true,
          isEnabled: false,
          value: 'heute offen',
        ),
      );
      handle.dispose();
    });

    testWidgets(
      'a read only card offers nothing to create, the rows still open (BS-110)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await env.addTask(tester, 'Steuer machen');
        final router = await pumpCard(tester, env, readOnly: true);

        expect(find.text('Gewohnheit anlegen'), findsNothing);
        expect(find.text('Noch keine Gewohnheit'), findsNothing);
        await tester.tap(find.text('Steuer machen'));
        await tester.pumpAndSettle();
        expect(find.text('Aufgabe bearbeiten'), findsOneWidget);
        expect(router.canPop(), isTrue);
      },
    );

    testWidgets(
      'a read only card without anything has no create actions either (BS-110)',
      (tester) async {
        final env = await createTasksUiEnv(tester);
        await pumpCard(tester, env, readOnly: true);

        expect(find.text('Heute abhaken'), findsOneWidget);
        expect(find.text('Aufgabe anlegen'), findsNothing);
        expect(find.text('Gewohnheit anlegen'), findsNothing);
      },
    );
  });

  group('layout (AT33, BS-110)', () {
    testWidgets(
      'at 200 % text the box and the chip share the first line and the title has the full width below',
      (tester) async {
        final env = await envWithHabits(
          tester,
          titles: ['Ein sehr langer Name einer Gewohnheit der umbrechen muss'],
        );
        await pumpCard(tester, env, size: const Size(320, 640), textScale: 2.0);

        expect(tester.takeException(), isNull);
        final box = tester.getCenter(find.byType(RoundCheckbox));
        final chip = tester.getCenter(find.byType(EntryTypeChip));
        final title = tester.getTopLeft(
          find.textContaining('Ein sehr langer Name'),
        );
        expect((chip.dy - box.dy).abs(), lessThan(24), reason: 'one line');
        expect(chip.dx, greaterThan(box.dx + 100));
        expect(title.dy, greaterThan(box.dy + 24), reason: 'title below');
        // One tap still checks the habit.
        await tester.tap(find.byType(RoundCheckbox));
        await waitForFeedback(tester, env);
        expect(env.feedback.last!.message, 'Abgehakt');
      },
    );

    testWidgets(
      'at normal text a row is 64 high and the box has a 48 by 48 target',
      (tester) async {
        final env = await envWithHabits(tester, titles: ['Lesen']);
        await pumpCard(tester, env);

        expect(tester.getSize(find.byType(RoundCheckbox)), const Size(48, 48));
        final row = find.byKey(
          ValueKey<String>(
            'checklist-habit-${await habitId(tester, env, 'Lesen')}',
          ),
        );
        expect(
          tester.getSize(row).height,
          greaterThanOrEqualTo(checklistRowMinHeight),
        );
      },
    );

    testWidgets('a long title wraps and keeps the chip (BS-110)', (
      tester,
    ) async {
      final env = await envWithHabits(
        tester,
        titles: [
          'Ein sehr langer Name einer Gewohnheit der über mehrere Zeilen läuft',
        ],
      );
      await pumpCard(tester, env, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('Gewohnheit'), findsOneWidget);
    });
  });
}
