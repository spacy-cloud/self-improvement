import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/design/design.dart';

import 'flow_context.dart';
import 'flow_steps.dart';

/// The remaining time of the session screen in seconds, read from the countdown
/// text ("24:56", or "1:02:05" from one hour on).
int _remainingSeconds() {
  final pattern = RegExp(r'^(?:(\d+):)?(\d{2}):(\d{2})$');
  for (final element in find.byType(Text).evaluate()) {
    final data = (element.widget as Text).data;
    final match = data == null ? null : pattern.firstMatch(data);
    if (match != null) {
      return int.parse(match.group(1) ?? '0') * 3600 +
          int.parse(match.group(2)!) * 60 +
          int.parse(match.group(3)!);
    }
  }
  fail('no countdown (MM:SS) on screen.\nTexts on screen: ${describeScreen()}');
}

/// F5 (AT16): start a focus session, pause and resume it, kill the app in the
/// middle of the session and start it again later: the session is still there,
/// still running, and the time that passed meanwhile is caught up. Ends by
/// saving the session.
///
/// How much time passes differs: the host moves its fake clock by minutes, the
/// emulator waits a few real seconds. The expectations follow the time that
/// really passed ([FlowContext.letTimePass]).
Future<void> focusSessionFlow(FlowContext ctx) async {
  await skipOnboarding(ctx);

  ctx.log('F5: the setup offers 25 minutes, start the session');
  await openPlusEntry(ctx, 'focus');
  await ctx.waitForText('Fokus starten');
  await ctx.waitForText('25:00');
  await ctx.tapText('Fokus starten');
  await ctx.waitForText('Läuft · Sonstiges');
  final started = _remainingSeconds();
  expect(
    started,
    inInclusiveRange(1480, 1500),
    reason: 'a session that just started has about 25 minutes left',
  );

  ctx.log('F5: the remaining time runs down while the session runs');
  final ranFor = await ctx.letTimePass(const Duration(seconds: 30));
  await ctx.pumpUntil(
    () => started - _remainingSeconds() >= ranFor.inSeconds - 2,
    reason:
        'the countdown did not run down by the ${ranFor.inSeconds} s that '
        'passed (started at $started s)',
  );

  ctx.log('F5: pause');
  await ctx.tapText('Pausieren');
  await ctx.waitForText('Pausiert · Sonstiges');
  await ctx.waitForText('Fortsetzen');
  final pausedAt = _remainingSeconds();
  expect(
    started - pausedAt,
    greaterThanOrEqualTo(ranFor.inSeconds - 2),
    reason: 'the time before the pause is kept',
  );

  ctx.log('F5: paused time does not count');
  await ctx.letTimePass(const Duration(minutes: 1));
  expect(
    _remainingSeconds(),
    pausedAt,
    reason: 'the remaining time of a paused session must not change',
  );

  ctx.log('F5: resume');
  await ctx.tapText('Fortsetzen');
  await ctx.waitForText('Läuft · Sonstiges');
  final beforeRestart = _remainingSeconds();
  expect(
    pausedAt - beforeRestart,
    inInclusiveRange(0, 5),
    reason: 'resuming continues where the pause stopped',
  );

  ctx.log('F5: kill the app mid-session, start it again later');
  final passed = await ctx.restart(closedFor: const Duration(minutes: 10));

  ctx.log('F5: the plus menu offers to continue the session');
  await ctx.tap(plusButton(), reason: 'the plus button of the navigation bar');
  await ctx.waitFor(
    plusEntry('focus'),
    reason: 'the focus entry of the plus menu',
  );
  // The menu asks the database whether a session is open; until the answer is
  // there the entry still reads "Fokus".
  await ctx.waitFor(
    find.descendant(
      of: plusEntry('focus'),
      matching: find.text('Fokus fortsetzen'),
    ),
    reason: 'an open session turns "Fokus" into "Fokus fortsetzen"',
  );
  await ctx.tap(plusEntry('focus'), reason: 'the focus entry of the plus menu');

  ctx.log('F5: still running, with the time that passed caught up');
  await ctx.waitForText('Läuft · Sonstiges');
  final afterRestart = _remainingSeconds();
  final caughtUp = beforeRestart - afterRestart;
  ctx.log(
    'F5: remaining $beforeRestart s before the restart, $afterRestart s after '
    'it, ${passed.inSeconds} s passed while the app was closed',
  );
  expect(
    caughtUp,
    greaterThanOrEqualTo(passed.inSeconds - 2),
    reason:
        'the ${passed.inSeconds} s the app was closed are caught up '
        '(remaining before $beforeRestart s, after $afterRestart s)',
  );
  expect(
    caughtUp,
    lessThanOrEqualTo(passed.inSeconds + 90),
    reason: 'only the time that really passed is caught up',
  );
  expect(afterRestart, greaterThan(0), reason: 'the session is not over yet');

  ctx.log('F5: finish cleanly, save the time');
  await ctx.tapText('Beenden');
  await ctx.waitForText('Sitzung beenden?');
  await ctx.tapText('Zeit speichern');
  await ctx.waitGone(
    find.text('Läuft · Sonstiges'),
    reason: 'the session screen should close after saving',
  );

  ctx.log('F5: no session is open any more');
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
    reason: 'after saving, the plus menu starts a new session again',
  );
  await ctx.tap(
    find.descendant(
      of: find.byType(PlusSheet),
      matching: find.byIcon(AppIcon.close.data),
    ),
    reason: 'the close button of the plus menu',
  );
}
