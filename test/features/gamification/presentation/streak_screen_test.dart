import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/streak.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../../dashboard/support/dashboard_test_kit.dart';

/// The profile started on 20 September, today is Saturday 3 October 2026.
final LocalDate _start = LocalDate(2026, 9, 20);
final LocalDate _today = LocalDate(2026, 10, 3);

Future<HomeFixture> _pump(
  WidgetTester tester, {
  LocalDate? startedOn,
  List<LocalDate> active = const <LocalDate>[],
  Size size = const Size(393, 852),
  double scale = 1.0,
  List<Override> overrides = const <Override>[],
}) async {
  final harness = await createHarness(tester, startedOn: startedOn ?? _start);
  final fixture = await pumpHome(
    tester,
    harness,
    size: size,
    textScale: scale,
    initialLocation: '/streak',
    overrides: overrides,
  );
  if (active.isNotEmpty) {
    await seedActiveDays(tester, fixture, active);
  }
  return fixture;
}

void main() {
  // Active: 20-24 September (5 days), 27 September, 30 September to today.
  final activeDays = <LocalDate>[
    ..._start.rangeTo(LocalDate(2026, 9, 24)),
    LocalDate(2026, 9, 27),
    ...LocalDate(2026, 9, 30).rangeTo(_today),
  ];

  testWidgets(
    '(G02) shows the running streak, the week with dates and status and the figures',
    (tester) async {
      await _pump(tester, active: activeDays);
      final semantics = tester.ensureSemantics();

      expect(find.text('Deine Streak'), findsOneWidget);
      expect(find.bySemanticsLabel('4 Tage in Folge'), findsOneWidget);
      expect(find.text('Noch 1 Tag bis zu deinem Rekord.'), findsOneWidget);

      // The last seven days: concrete dates, status in words.
      for (final label in const <String>[
        'Sonntag, 27. September: aktiver Tag',
        'Montag, 28. September: kein Ziel erreicht',
        'Dienstag, 29. September: kein Ziel erreicht',
        'Mittwoch, 30. September: aktiver Tag',
        'Donnerstag, 1. Oktober: aktiver Tag',
        'Freitag, 2. Oktober: aktiver Tag',
        'Heute, Samstag, 3. Oktober: aktiver Tag',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      for (final date in const <String>[
        '27.9.',
        '28.9.',
        '29.9.',
        '30.9.',
        '1.10.',
        '2.10.',
        '3.10.',
      ]) {
        expect(find.text(date), findsOneWidget, reason: date);
      }
      expect(find.text('Heute'), findsOneWidget);

      expect(find.bySemanticsLabel('Längste Streak, 5 Tage'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Aktive Tage gesamt, 10 Tage'),
        findsOneWidget,
      );
      expect(find.text('7 Tage – neuer Rekord'), findsOneWidget);
      expect(find.text('4 / 7'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Nächster Meilenstein: 7 Tage, aktuell 4 von 7'),
        findsOneWidget,
      );
      expect(find.text('So hältst du deine Streak'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('an open today keeps the streak and says so (AT22)', (
    tester,
  ) async {
    await _pump(
      tester,
      active: [LocalDate(2026, 10, 1), LocalDate(2026, 10, 2)],
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('2 Tage in Folge'), findsOneWidget);
    expect(
      find.text(
        'Erreiche heute noch ein Tagesziel, damit deine Serie weiterläuft.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Heute, Samstag, 3. Oktober: noch offen'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'the first day shows honest zeros and days before the start (AT01)',
    (tester) async {
      await _pump(tester, startedOn: _today);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('0 Tage in Folge'), findsOneWidget);
      expect(
        find.text(
          'Erreiche heute ein Tagesziel, um deine erste Serie zu starten.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Längste Streak, 0 Tage'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Aktive Tage gesamt, 0 Tage'),
        findsOneWidget,
      );
      expect(find.text('3 Tage – neuer Rekord'), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('vor dem Start, zählt nicht')),
        findsNWidgets(6),
      );
      expect(
        find.bySemanticsLabel('Heute, Samstag, 3. Oktober: noch offen'),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets('the next milestone follows the rule 3/7/14/30/60/100 (G02)', (
    tester,
  ) async {
    await _pump(
      tester,
      active: LocalDate(2026, 9, 27).rangeTo(_today).toList(),
    );
    // Seven days in a row: the next milestone is 14, a new record.
    expect(find.text('14 Tage – neuer Rekord'), findsOneWidget);
    expect(find.text('7 / 14'), findsOneWidget);
    expect(find.text('Das ist deine bisher längste Serie.'), findsOneWidget);
  });

  testWidgets('a deletion in the past lowers the streak at once (AT23)', (
    tester,
  ) async {
    final fixture = await _pump(
      tester,
      active: [
        LocalDate(2026, 10, 1),
        LocalDate(2026, 10, 2),
        LocalDate(2026, 10, 3),
      ],
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('3 Tage in Folge'), findsOneWidget);

    final weights = fixture.container.read(weightRepositoryProvider);
    final entries = await tester.runAsync(() => weights.watchActive().first);
    final yesterday = entries!.firstWhere(
      (entry) => entry.localDate == LocalDate(2026, 10, 2),
    );
    await tester.runCommand(
      () => weights.delete(commandId: 'fix', id: yesterday.id),
    );
    await settle(tester);

    expect(find.bySemanticsLabel('1 Tag in Folge'), findsOneWidget);
    expect(find.bySemanticsLabel('Längste Streak, 1 Tag'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Freitag, 2. Oktober: kein Ziel erreicht'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a day change moves the week and keeps the streak alive (AT22)', (
    tester,
  ) async {
    final fixture = await _pump(tester, active: [LocalDate(2026, 10, 3)]);
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('1 Tag in Folge'), findsOneWidget);
    fixture.harness.clock.advance(const Duration(days: 1));
    fixture.container.read(todayProvider.notifier).refresh();
    await settle(tester);
    expect(find.bySemanticsLabel('1 Tag in Folge'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Heute, Sonntag, 4. Oktober: noch offen'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Samstag, 3. Oktober: aktiver Tag'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'a failed read shows the error state and retry loads the page (AT27)',
    (tester) async {
      var reads = 0;
      await _pump(
        tester,
        active: const <LocalDate>[],
        overrides: [
          streakProvider.overrideWith((ref) {
            reads++;
            if (reads == 1) {
              return Stream<StreakSummary?>.error(StateError('read failed'));
            }
            ref.watch(todayProvider);
            return ref.watch(dayStatusRepositoryProvider).watchStreak();
          }),
        ],
      );
      expect(find.text('Daten konnten nicht geladen werden'), findsOneWidget);
      await tester.tap(find.text('Erneut versuchen'));
      await settle(tester);
      expect(find.text('Daten konnten nicht geladen werden'), findsNothing);
      expect(find.text('So hältst du deine Streak'), findsOneWidget);
      expect(reads, 2);
    },
  );

  testWidgets('shows a neutral hint while the first read is slow', (
    tester,
  ) async {
    await _pump(
      tester,
      overrides: [
        streakProvider.overrideWith(
          (ref) => const Stream<StreakSummary?>.empty(),
        ),
      ],
    );
    expect(find.text('Daten werden geladen …'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Daten werden geladen …'), findsOneWidget);
    expect(find.text('Deine Streak'), findsOneWidget);
  });

  testWidgets(
    'without a streak summary it says so instead of showing numbers',
    (tester) async {
      await _pump(
        tester,
        overrides: [
          streakProvider.overrideWith(
            (ref) => Stream<StreakSummary?>.value(null),
          ),
        ],
      );
      expect(find.text('Noch keine Streak-Daten'), findsOneWidget);
      expect(find.textContaining('Tage in Folge'), findsNothing);
    },
  );

  testWidgets(
    'back leads to the dashboard even when the page was opened directly (C02)',
    (tester) async {
      await _pump(tester);
      await tester.tap(find.byIcon(AppIcon.back.data));
      await tester.pumpAndSettle();
      expect(find.text('Mein Dashboard'), findsOneWidget);
    },
  );

  testWidgets(
    '(AT33) at large text the week becomes a list with full dates and visible '
    'status words',
    (tester) async {
      await _pump(tester, active: activeDays, scale: 2.0);
      expect(find.text('Sonntag, 27. September'), findsOneWidget);
      expect(find.text('Heute – Samstag, 3. Oktober'), findsOneWidget);
      expect(find.text('Aktiver Tag'), findsNWidgets(5));
      expect(find.text('Kein Ziel erreicht'), findsNWidgets(2));
    },
  );

  for (final size in responsiveSizes) {
    for (final scale in const <double>[1.0, 2.0]) {
      testWidgets(
        '(Q02, AT33) fits ${size.width.toInt()} px at text scale $scale with reachable '
        'content and tap targets',
        (tester) async {
          await _pump(tester, active: activeDays, size: size, scale: scale);
          final semantics = tester.ensureSemantics();
          expect(tester.takeException(), isNull);
          for (final target in [
            find.text('Nächster Meilenstein'),
            find.text('So hältst du deine Streak'),
          ]) {
            await tester.ensureVisible(target);
            await tester.pump();
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width + 0.5));
            expect(rect.bottom, lessThanOrEqualTo(size.height + 0.5));
          }
          tester.view.physicalSize = Size(size.width, 9000);
          await tester.pump();
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
        },
      );
    }
  }
}
