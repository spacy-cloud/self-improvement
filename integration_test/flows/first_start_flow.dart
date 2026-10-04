import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// F1 (AT01): a fresh install shows the onboarding, nothing typed leads through
/// its five screens to the home screen with the four tabs, and nothing on any
/// tab pretends to be a measurement.
///
/// Starts on a fresh install (the onboarding is on screen).
Future<void> firstStartFlow(FlowContext ctx) async {
  ctx.log('F1: a fresh install starts with the onboarding');
  await ctx.waitForText('Los geht’s');
  expect(
    find.byType(AppBottomNavBar),
    findsNothing,
    reason: 'no tab may show before the onboarding is done',
  );
  expect(find.text('Überspringen'), findsOneWidget);
  // The app has no accounts and no sign-in.
  expect(find.textContaining('Konto'), findsNothing);
  expect(find.textContaining('anmelden'), findsNothing);

  // The shortest way through the five screens needs no input at all: every
  // field is optional and the suggested defaults apply.
  await ctx.tapText('Los geht’s');
  for (var step = 1; step <= 3; step++) {
    await ctx.waitForText('Schritt $step von 4');
    await ctx.tapText('Weiter');
  }
  await ctx.waitForText('Schritt 4 von 4');
  await ctx.tapText('Fertig – los geht’s');

  ctx.log('F1: the home screen, the first day shows no invented values');
  await ctx.waitFor(
    find.byType(AppBottomNavBar),
    reason: 'the tabs after the onboarding',
  );
  await ctx.waitForText('Mein Dashboard');
  await ctx.waitForText('Ersten Eintrag hinzufügen');
  expect(find.text('Willkommen!'), findsOneWidget);
  expect(find.text('Dein Tag im Überblick'), findsNothing);
  expect(find.textContaining(' kg'), findsNothing);
  expect(find.textContaining('Level'), findsNothing);
  expect(find.textContaining('XP'), findsNothing);
  expect(find.textContaining('Streak'), findsNothing);
  expect(find.text('Los geht’s'), findsNothing);

  // The four tabs, each with an honest empty state.
  for (final label in <String>['Home', 'Analyse', 'Habits', 'Profil']) {
    expect(navTab(label), findsOneWidget, reason: 'tab $label');
  }
  expect(plusButton(), findsOneWidget);

  await switchTab(ctx, 'Analyse');
  await ctx.waitForText('Noch keine Daten');

  await switchTab(ctx, 'Habits');
  await ctx.waitForText('Noch keine Gewohnheit');

  await switchTab(ctx, 'Profil');
  await ctx.waitForText('Mein Profil');
  expect(find.textContaining(' kg'), findsNothing);

  await switchTab(ctx, 'Home');
  await ctx.waitForText('Willkommen!');
}
