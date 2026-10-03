import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// The sentence of the reset sheet that names what is deleted ("Dein Profil,
/// 2 Einträge, deine Ziele und Einstellungen ..."), or null while the sheet is
/// not on screen.
String? _resetSheetSentence() {
  final elements = find.textContaining('Dein Profil').evaluate();
  return elements.length == 1 ? (elements.single.widget as Text).data : null;
}

/// The sentence once the sheet has counted the entries: the count is read a
/// moment after the sheet opens, before that the sentence has no number.
Future<String> _countedResetSentence(FlowContext ctx) async {
  await ctx.pumpUntil(
    () => (_resetSheetSentence() ?? '').contains('Eintr'),
    reason: 'the reset sheet should name the number of entries it deletes',
  );
  return _resetSheetSentence()!;
}

/// F6 (AT32): with data and a running focus session in the app, cancelling the
/// reset changes nothing; confirming it with the word deletes everything
/// (including the session) and the app returns to the onboarding, also after a
/// restart.
Future<void> resetFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F6: some data and a running timer');
  await saveWeightFromPlusMenu(ctx, '71,5');
  await startFocusSession(ctx);
  await goBack(ctx);
  await ctx.waitForText('Eine Sitzung läuft');
  await goBack(ctx);
  await ctx.waitForText('Dein Tag im Überblick');

  ctx.log('F6: Profil, Einstellungen, Daten & Sicherung');
  await switchTab(ctx, 'Profil');
  await ctx.tap(
    find.widgetWithIcon(AppIconButton, AppIcon.settings.data),
    reason: 'the settings button of the profile',
  );
  await ctx.waitForText('Einstellungen');
  await ctx.tapText('Daten & Sicherung');
  await ctx.waitForText('Zurücksetzen …');

  ctx.log('F6: cancel the reset, nothing changes');
  await ctx.tapText('Zurücksetzen …');
  await ctx.waitForText('Wirklich alles zurücksetzen?');
  final before = await _countedResetSentence(ctx);
  await ctx.tapText('Abbrechen');
  await ctx.waitGone(find.text('Wirklich alles zurücksetzen?'));
  await ctx.waitForText('Zurücksetzen …');
  await ctx.tapText('Zurücksetzen …');
  await ctx.waitForText('Wirklich alles zurücksetzen?');
  expect(
    await _countedResetSentence(ctx),
    before,
    reason: 'cancelling the reset must not change any data',
  );

  ctx.log('F6: confirm with the word');
  await ctx.enterText(find.byType(TextField).first, 'LÖSCHEN');
  await ctx.tapText('Alles löschen');

  ctx.log('F6: back to the onboarding');
  await ctx.waitForText('Los geht’s');
  expect(find.byType(AppBottomNavBar), findsNothing);

  ctx.log('F6: still the onboarding after a restart');
  // The reset still hands over to the system (cancels notifications, deletes
  // temporary files) for a moment after the screen has changed.
  await ctx.settle();
  await ctx.restart();
  await ctx.waitForText('Los geht’s');
  expect(find.byType(AppBottomNavBar), findsNothing);

  ctx.log('F6: a new start is empty, the timer is gone');
  await skipOnboarding(ctx);
  await ctx.waitForText('Willkommen!');
  expect(find.text('Dein Tag im Überblick'), findsNothing);
  expect(find.textContaining(' kg'), findsNothing);
  await ctx.tap(plusButton(), reason: 'the plus button of the navigation bar');
  await ctx.waitFor(
    plusEntry('focus'),
    reason: 'the focus entry of the plus menu',
  );
  // Give the menu time to read the sessions: "Fokus" is also what it shows
  // before the answer is there.
  await ctx.settle();
  expect(
    find.descendant(of: plusEntry('focus'), matching: find.text('Fokus')),
    findsOneWidget,
    reason: 'the running session is gone, the plus menu starts a new one',
  );
}
