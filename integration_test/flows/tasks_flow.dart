import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

const String _title = 'Präsentation vorbereiten';

/// The round check box of the (only) task row.
Finder _taskCheckbox() => find.byType(RoundCheckbox);

bool _taskIsChecked(WidgetTester tester) =>
    tester.widget<RoundCheckbox>(_taskCheckbox()).value;

/// F4 (AT13): create a task, complete it, reopen it, complete it again. The
/// XP of the completion are given back by the reopening and awarded once.
Future<void> taskFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F4: create the task through the plus menu');
  await openPlusEntry(ctx, 'task');
  await ctx.waitForText('Neue Aufgabe');
  await ctx.enterText(find.byType(TextField).first, _title);
  await ctx.tapText('Aufgabe speichern');
  await ctx.waitGone(
    find.text('Aufgabe speichern'),
    reason: 'the task form should close after saving',
  );

  ctx.log('F4: the task is in the list of open tasks');
  await switchTab(ctx, 'Habits');
  await ctx.tapText('Aufgaben');
  await ctx.waitForText(_title);
  expect(_taskIsChecked(ctx.tester), isFalse);

  ctx.log('F4: complete it');
  await ctx.tap(_taskCheckbox(), reason: 'the check box of the task');
  await ctx.waitForText('Alles erledigt');
  expect(find.text(_title), findsNothing, reason: 'done tasks leave "Offen"');

  ctx.log('F4: it is in the list of done tasks, reopen it');
  await ctx.tapText('Erledigt');
  await ctx.waitForText(_title);
  expect(_taskIsChecked(ctx.tester), isTrue);
  await ctx.tap(_taskCheckbox(), reason: 'the check box of the done task');
  await ctx.waitForText('Noch nichts erledigt');

  ctx.log('F4: it is open again, complete it a second time');
  await ctx.tapText('Offen');
  await ctx.waitForText(_title);
  expect(_taskIsChecked(ctx.tester), isFalse);
  await ctx.tap(_taskCheckbox(), reason: 'the check box of the reopened task');
  await ctx.waitForText('Alles erledigt');

  ctx.log('F4: one completion is worth 10 XP, not 20');
  await switchTab(ctx, 'Home');
  await ctx.waitFor(
    find.textContaining('Gesamt: 10 XP'),
    reason: 'completed, reopened and completed again: 10 XP in total',
  );
  expect(find.textContaining('Gesamt: 20 XP'), findsNothing);
}
