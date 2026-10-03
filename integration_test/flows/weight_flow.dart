import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// The weight card of the dashboard (the card with the title "Gewicht").
Finder _weightCardTitle() => find.descendant(
  of: find.widgetWithText(MetricCard, 'Gewicht'),
  matching: find.text('Gewicht'),
);

/// Opens the weight screen from the dashboard card and checks the value.
Future<void> _expectWeightOnWeightScreen(FlowContext ctx, String value) async {
  await ctx.tap(_weightCardTitle(), reason: 'the weight card of the dashboard');
  await ctx.waitForText('Mein Gewicht');
  await ctx.waitForText('Aktuell');
  await ctx.waitFor(
    find.text('$value kg'),
    reason: 'the saved weight $value kg on the weight screen',
  );
  await goBack(ctx);
  await ctx.waitForText('Dein Tag im Überblick');
}

/// F2 (AT02, AT06): a weight saved through the plus menu shows on the weight
/// screen and is still there, with the onboarding state, after the app was
/// killed and started again on the same data.
Future<void> weightPersistsFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F2: save 71,5 kg through the plus menu');
  await saveWeightFromPlusMenu(ctx, '71,5');

  // With the first record the dashboard leaves the first-day welcome.
  await ctx.waitForText('Dein Tag im Überblick');
  expect(find.text('Willkommen!'), findsNothing);
  await ctx.waitFor(
    find.text('71,5 kg'),
    reason: 'the saved value on the weight card',
  );

  ctx.log('F2: the value on the weight screen');
  await _expectWeightOnWeightScreen(ctx, '71,5');

  ctx.log('F2: kill the app and start it again on the same data');
  await ctx.restart();

  // The onboarding state survived: tabs, no onboarding.
  expect(
    find.byType(AppBottomNavBar),
    findsOneWidget,
    reason: 'after the restart the app opens the tabs, not the onboarding',
  );
  expect(find.text('Los geht’s'), findsNothing);
  await ctx.waitForText('Dein Tag im Überblick');

  ctx.log('F2: the value is still there after the restart');
  await ctx.waitFor(
    find.text('71,5 kg'),
    reason: 'the saved value on the weight card after the restart',
  );
  await _expectWeightOnWeightScreen(ctx, '71,5');
}
