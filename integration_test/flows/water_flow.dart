import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// The quick add "250 ml" of the water card on the dashboard.
Finder _cardQuickAdd250() => find.widgetWithText(MetricCardAction, '250 ml');

/// F3 (AT10): +250 ml is two actions from the first-day home screen and one
/// from the water card; the home screen shows the new amount and the XP, and
/// "Rückgängig" takes both back, once.
Future<void> waterQuickAddFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F3: first action, the starting point "Wasser eintragen"');
  await ctx.tapText('Wasser eintragen');
  await ctx.waitForText('Schnell hinzufügen');
  await ctx.waitForText('Noch nichts getrunken');

  ctx.log('F3: second action, +250 ml with one tap');
  await ctx.tapText('Glas');
  await ctx.waitForText('250 ml hinzugefügt');
  await ctx.waitForText('1 Eintrag');
  await ctx.waitFor(
    find.text('0,25 / 2,5 l'),
    reason: 'the day total on the water screen',
  );
  expect(find.text('Noch nichts getrunken'), findsNothing);

  ctx.log('F3: the home screen shows 250 ml and the XP');
  await ctx.tapText('Fertig');
  await ctx.waitForText('Dein Tag im Überblick');
  await ctx.waitFor(
    find.text('0,25 / 2,5 l'),
    reason: 'the water card shows 0,25 of 2,5 litres',
  );
  await ctx.waitFor(
    find.textContaining('Gesamt: 5 XP'),
    reason: 'one water entry earns 5 XP',
  );

  // The undo offer of the first add (8 s) must be gone, so the next "Rückgängig"
  // belongs to the next add and to nothing else.
  ctx.log('F3: wait until the undo offer of the first add has run out');
  await ctx.waitGone(
    find.text('Rückgängig'),
    reason: 'the undo offer of the first add should run out',
  );

  ctx.log('F3: +250 ml again from the card, then undo it');
  await ctx.tap(
    _cardQuickAdd250(),
    reason: 'the 250 ml action of the water card',
  );
  await ctx.waitFor(
    find.text('0,5 / 2,5 l'),
    reason: 'the water card shows 0,5 of 2,5 litres',
  );
  await ctx.waitFor(find.textContaining('Gesamt: 10 XP'));
  await ctx.waitForText('Rückgängig');
  await ctx.tapText('Rückgängig');
  await ctx.waitForText('Rückgängig gemacht.');
  await ctx.waitFor(
    find.text('0,25 / 2,5 l'),
    reason: 'the undo takes the second glass back',
  );
  await ctx.waitFor(
    find.textContaining('Gesamt: 5 XP'),
    reason: 'the undo takes the XP of the second glass back',
  );
  // One undo per saved action: the message of the undo offers no second one.
  expect(find.text('Rückgängig'), findsNothing);
}
