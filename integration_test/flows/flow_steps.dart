import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';

/// Steps that several flows share: leaving the onboarding, the plus menu, the
/// tabs, the back button. They only use finders and German texts of the app.

/// The plus button of the navigation bar.
Finder plusButton() => find.descendant(
  of: find.byType(AppBottomNavBar),
  matching: find.byIcon(AppIcon.plus.data),
);

/// The navigation tab with [label] (Home, Analyse, Habits, Profil).
Finder navTab(String label) => find.descendant(
  of: find.byType(AppBottomNavBar),
  matching: find.text(label),
);

/// The entry [id] of the open plus menu (weight, workout, water, steps, focus,
/// task, habit, meal).
Finder plusEntry(String id) => find.byKey(ValueKey<String>('plus-entry-$id'));

/// The filled back button of a sub page.
Finder backButton() => find.widgetWithIcon(AppIconButton, AppIcon.back.data);

/// Leaves the onboarding with "Überspringen" on the welcome screen: with
/// nothing typed this saves the defaults at once (all five modules, the
/// suggested goals). The shortest way to the tabs.
Future<void> skipOnboarding(FlowContext ctx) async {
  ctx.log('onboarding: skip with the defaults');
  await ctx.waitForText('Überspringen');
  await ctx.tapText('Überspringen');
  await ctx.waitFor(
    find.byType(AppBottomNavBar),
    reason: 'the tabs after the onboarding',
  );
  await ctx.waitForText('Mein Dashboard');
  await ctx.settle();
}

/// Opens the plus menu and picks the entry [id].
Future<void> openPlusEntry(FlowContext ctx, String id) async {
  ctx.log('plus menu: open "$id"');
  await ctx.tap(plusButton(), reason: 'the plus button of the navigation bar');
  await ctx.waitFor(plusEntry(id), reason: 'the plus menu entry "$id"');
  await ctx.tap(plusEntry(id), reason: 'the plus menu entry "$id"');
}

/// Switches to the tab [label] and waits until its page title is shown.
Future<void> switchTab(FlowContext ctx, String label) async {
  ctx.log('tab: $label');
  await ctx.tap(navTab(label), reason: 'the tab "$label"');
  // The page title of the Home tab is "Mein Dashboard", the others carry
  // their own name.
  final title = label == 'Home' ? 'Mein Dashboard' : label;
  await ctx.waitFor(
    find.descendant(of: find.byType(AppScaffold), matching: find.text(title)),
    reason: 'the page title "$title"',
  );
}

/// Presses the back button of the sub page on top.
Future<void> goBack(FlowContext ctx) async {
  ctx.log('back');
  await ctx.tap(backButton(), reason: 'the back button of the page header');
}

/// Saves one weight measurement from the plus menu and returns to the page the
/// user started from. [text] is typed as the user would type it.
Future<void> saveWeightFromPlusMenu(FlowContext ctx, String text) async {
  await openPlusEntry(ctx, 'weight');
  await ctx.waitForText('Eintrag speichern');
  await ctx.enterText(find.byType(TextField).first, text);
  await ctx.tapText('Eintrag speichern');
  await ctx.waitGone(
    find.text('Eintrag speichern'),
    reason: 'the weight form should close after saving',
  );
  await ctx.settle();
}

/// Starts a focus session with the defaults (25 minutes, "Sonstiges") from the
/// plus menu and waits until the running session is shown.
Future<void> startFocusSession(FlowContext ctx) async {
  await openPlusEntry(ctx, 'focus');
  await ctx.waitForText('Fokus starten');
  await ctx.tapText('Fokus starten');
  await ctx.waitForText('Läuft · Sonstiges');
}
