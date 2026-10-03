import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

/// Layout at the narrowest width with the largest system font (320 px, 200 %).
void main() {
  testWidgets('a long single word in the header is not broken in the middle', (
    tester,
  ) async {
    await pumpDesign(
      tester,
      const AppHeader(title: 'Einstellungen', type: AppHeaderType.subpage),
      width: 320,
      textScale: 2.0,
      scrollable: false,
    );

    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Einstellungen'),
    );
    expect(
      paragraph.size.height,
      lessThan(80),
      reason: 'one line, not a word broken over two lines',
    );
    expect(paragraph.size.width, lessThanOrEqualTo(320));
  });

  testWidgets('a title of several words still wraps between words', (
    tester,
  ) async {
    await pumpDesign(
      tester,
      const AppHeader(
        title: 'Daten und Sicherung der Einträge',
        type: AppHeaderType.subpage,
      ),
      width: 320,
      textScale: 2.0,
      scrollable: false,
    );

    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Daten und Sicherung der Einträge'),
    );
    expect(paragraph.size.height, greaterThan(100));
  });

  testWidgets('a value row stacks its value instead of overflowing', (
    tester,
  ) async {
    await pumpDesign(
      tester,
      AppListGroup(
        children: [
          EntryListTile.value(
            title: 'Erinnerungen und Benachrichtigungen',
            subtitle: 'Wasser, Aufgaben und Fokus',
            value: 'Aus, Berechtigung fehlt',
            icon: Icons.notifications_none_rounded,
            onTap: () {},
          ),
        ],
      ),
      width: 320,
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Aus, Berechtigung fehlt'), findsOneWidget);
  });

  testWidgets('a value row keeps the value beside the title at normal size', (
    tester,
  ) async {
    await pumpDesign(
      tester,
      AppListGroup(
        children: [
          EntryListTile.value(title: 'Design', value: 'System', onTap: () {}),
        ],
      ),
    );

    final title = tester.getTopLeft(find.text('Design'));
    final value = tester.getTopLeft(find.text('System'));
    expect(value.dx, greaterThan(title.dx));
    expect((value.dy - title.dy).abs(), lessThan(8), reason: 'same line');
  });
}
