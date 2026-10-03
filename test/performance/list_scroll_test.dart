import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/body/presentation/weight_history_screen.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/db_fixtures.dart';
import '../support/pump_app.dart';

/// "Alle Messungen" with several thousand entries (BS-75, AT36): rows are built
/// lazily, so only the visible ones exist, and the list can be scrolled to its
/// very end. Host test with a synthetic history, not a device measurement.
void main() {
  testWidgets('3.000 measurements: lazy rows and a scroll to the end (AT36)', (
    tester,
  ) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final harness = await createTestHarness(tester);
    final first = LocalDate(2018, 10, 1);
    await tester.runAsync(() async {
      await harness.database.batch((batch) {
        for (var i = 0; i < 3000; i++) {
          final day = first.addDays(i ~/ 2);
          batch.insert(
            harness.database.weightEntries,
            weightRow(
              id: 'scroll-$i',
              grams: 70000 + (i % 50) * 100,
              at: DateTime.utc(day.year, day.month, day.day, i.isEven ? 6 : 18),
            ).copyWith(localDate: Value(day)),
          );
        }
      });
    });
    final container = harness.createContainer();
    final watch = Stopwatch()..start();
    await pumpApp(tester, const WeightHistoryScreen(), container: container);
    await tester.pumpAndSettle();
    final firstRender = watch.elapsedMilliseconds;

    expect(find.byType(EntryListTile).evaluate().length, lessThan(40));

    watch
      ..reset()
      ..start();
    await tester.dragUntilVisible(
      find.textContaining('Tippe auf einen Eintrag'),
      find.byType(Scrollable).first,
      const Offset(0, -2500),
      maxIteration: 400,
    );
    final scrollToEnd = watch.elapsedMilliseconds;

    expect(find.byType(EntryListTile).evaluate().length, lessThan(40));
    // ignore: avoid_print
    print(
      'LOAD list first render $firstRender ms, scroll to the end of 3000 '
      'entries $scrollToEnd ms (host, widget test)',
    );
  });
}
