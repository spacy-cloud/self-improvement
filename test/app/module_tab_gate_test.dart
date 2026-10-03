import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/database/app_database.dart';
import 'package:self_improvement/core/testing/data_harness.dart';
import 'package:self_improvement/shared/local_date.dart';

import 'support/app_harness.dart';

/// The Habits tab is a core destination whose content belongs to the tasks
/// module (spec: it "bietet bei deaktiviertem Modul Aufgaben und Gewohnheiten
/// aktivieren"). While the module is off the tab shows no data and no write
/// action; switching it on brings the data back.
void main() {
  const modulesWithoutTasks = <String>{
    'body',
    'nutrition',
    'focus',
    'gamification',
  };

  Future<void> seedHabit(DataHarness harness) async {
    await harness.database
        .into(harness.database.habits)
        .insert(
          HabitsCompanion.insert(
            id: '11111111-1111-4111-8111-111111111111',
            title: 'Lesen',
            startedLocalDate: LocalDate(2026, 9, 1),
            createdAtUtc: DateTime.utc(2026, 9, 1),
            updatedAtUtc: DateTime.utc(2026, 9, 1),
          ),
        );
  }

  testWidgets(
    'AT03 the tab offers to switch the module on and shows no habit data '
    'while the module is off; switching it on brings the entries back',
    (tester) async {
      final app = await pumpFullApp(
        tester,
        enabledModules: modulesWithoutTasks,
        seed: seedHabit,
      );
      await tester.tap(navTab('Habits'));
      await app.settle();

      expect(
        find.text('Aufgaben und Gewohnheiten sind ausgeschaltet'),
        findsOneWidget,
      );
      expect(find.text('Aufgaben und Gewohnheiten aktivieren'), findsOneWidget);
      expect(find.text('Module verwalten'), findsOneWidget);
      expect(find.text('Lesen'), findsNothing, reason: 'no data while off');
      expect(
        find.text('Gewohnheit hinzufügen'),
        findsNothing,
        reason: 'no write action while off',
      );

      await tester.tap(find.text('Aufgaben und Gewohnheiten aktivieren'));
      for (var i = 0; i < 5; i++) {
        await app.settle();
      }

      expect(
        find.text('Aufgaben und Gewohnheiten sind ausgeschaltet'),
        findsNothing,
      );
      expect(
        find.text('Lesen'),
        findsOneWidget,
        reason: 'the entries were kept and are back',
      );
    },
  );

  testWidgets('with the module on the tab shows the content as before', (
    tester,
  ) async {
    final app = await pumpFullApp(tester, seed: seedHabit);
    await tester.tap(navTab('Habits'));
    await app.settle();
    expect(
      find.text('Aufgaben und Gewohnheiten sind ausgeschaltet'),
      findsNothing,
    );
    expect(find.text('Lesen'), findsOneWidget);
  });
}
