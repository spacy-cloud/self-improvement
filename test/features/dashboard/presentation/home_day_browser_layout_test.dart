import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/dashboard/presentation/widgets/day_navigator.dart';
import 'package:self_improvement/features/focus/domain/muscle_group.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../../../support/pump_app.dart';
import '../support/day_browser_kit.dart';

// BS-93: Home on a day before today, with a record in every card, at the four
// design widths with 100 and 200 % text and in the three themes: nothing
// overflows, every control is a 48 x 48 target with a label, the text is
// readable. Like the route sweep, but for the state that sweep cannot reach by
// itself.

final LocalDate _day = hostToday.addDays(-2);

/// Home on [_day], with a record in each card.
Future<RealHome> _pumpDay(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double scale = 1.0,
  AppThemeVariant theme = AppThemeVariant.light,
  LocalDate? day,
}) async {
  final home = await pumpRealHome(
    tester,
    size: size,
    textScale: scale,
    theme: theme,
    seed: (h) => seedHabitBeforeHome(
      h,
      'Lesen',
      startedOn: hostToday.addDays(-5),
      checked: <LocalDate>[_day],
    ),
  );
  await seedWater(tester, home, _day, 1500);
  await seedSteps(tester, home, _day, 7450);
  await seedWeight(tester, home, _day, 71500);
  await seedWorkout(
    tester,
    home,
    _day,
    groups: <MuscleGroup>[MuscleGroup.chest, MuscleGroup.shoulders],
  );
  await seedFocus(tester, home, _day, 20);
  await seedMeal(tester, home, _day, 'Frühstück', kcal: 400);
  await seedCompletedTask(tester, home, _day, 'Steuer machen');
  await showDay(tester, home, day ?? _day);
  await tester.pumpAndSettle();
  return home;
}

Future<void> _checkTargets(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  expect(tester.takeException(), isNull, reason: 'no overflow or exception');
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  semantics.dispose();
}

void main() {
  group('the widths and the text size (BS-93, AT33, Q02)', () {
    for (final size in responsiveSizes) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets('(BS-93, AT33, Q02) a day before today at '
            '${size.width.toInt()} px and ${(scale * 100).toInt()} % text '
            'lays out and is operable', (tester) async {
          await _pumpDay(tester, size: size, scale: scale);
          expect(find.byType(DayNavigator), findsOneWidget);
          expect(find.text('Nicht heute'), findsOneWidget);
          await _checkTargets(tester);
        });
      }
    }

    testWidgets('(BS-93, AT33) today with the arrows at the narrowest width '
        'and 200 % text', (tester) async {
      await _pumpDay(
        tester,
        size: const Size(320, 640),
        scale: 2.0,
        day: hostToday,
      );
      expect(find.text('Dein Tag im Überblick'), findsOneWidget);
      await _checkTargets(tester);
    });

    testWidgets('(BS-93, AT33) the oldest day with its arrow disabled at 200 % '
        'text', (tester) async {
      await _pumpDay(
        tester,
        size: const Size(320, 640),
        scale: 2.0,
        day: hostToday.addDays(-7),
      );
      expect(find.text('Samstag, 26. September'), findsOneWidget);
      await _checkTargets(tester);
    });

    testWidgets('(BS-93, Q02) every card of the day is reachable by scrolling '
        'at 200 % text', (tester) async {
      await _pumpDay(tester, size: const Size(320, 640), scale: 2.0);
      for (final title in <String>[
        'Schritte',
        'Wasser',
        'Gewicht',
        'Workout',
        'Fokus',
        'Aufgaben und Gewohnheiten',
        'Ernährung',
        'XP und Level',
        'Karten anpassen',
      ]) {
        await tester.ensureVisible(find.text(title));
        await tester.pump();
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the themes (BS-93, AT35, C06)', () {
    for (final theme in AppThemeVariant.values) {
      testWidgets('(BS-93, AT35, C06) a day before today in the ${theme.name} '
          'theme: readable text, targets and labels', (tester) async {
        await _pumpDay(tester, theme: theme);
        await _checkTargets(tester);
        final semantics = tester.ensureSemantics();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      });
    }
  });
}
