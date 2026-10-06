import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/app/shell/plus_entries.dart';
import 'package:self_improvement/app/shell/plus_sheet.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/goals/application/goal_providers.dart';
import 'package:self_improvement/core/goals/domain/goal_type.dart';
import 'package:self_improvement/core/goals/domain/goal_version.dart';
import 'package:self_improvement/core/onboarding/onboarding_repository.dart';
import 'package:self_improvement/core/providers/command_providers.dart';
import 'package:self_improvement/features/modules/presentation/neutral_loading.dart';
import 'package:self_improvement/shared/local_date.dart';

import '../support/db_fixtures.dart';
import '../support/pump_app.dart';
import 'support/app_harness.dart';
import 'support/fake_modules.dart';

/// The plus menu against the goals of "Meine Ziele" (BS-117) in the running app
/// on a real in-memory database (clock 2026-10-03 10:00 Europe/Berlin): an
/// entry is offered when its module is on AND the goal it belongs to is on;
/// habit and meal have no goal. The goals follow live, a hint says where to
/// change them and an empty state leads to "Meine Ziele".

const String _hint =
    'Nicht dabei? Unter Profil · Meine Ziele legst du fest, was hier erscheint.';
const String _emptyTitle = 'Noch nichts zum Eintragen';
const String _emptyMessage =
    'Lege unter Profil · Meine Ziele fest, was du hier eintragen möchtest. '
    'Deine bisherigen Daten bleiben erhalten.';
const String _emptyAction = 'Meine Ziele öffnen';

/// The two modules whose goals can all be switched off in the empty state tests
/// (habit and meal live in modules that are off then).
const Set<String> _bodyAndFocus = <String>{'body', 'focus', 'gamification'};

/// The goals of body and focus: every goal-bound entry of those two modules.
const Set<GoalType> _bodyAndFocusGoals = <GoalType>{
  GoalType.weightEntry,
  GoalType.steps,
  GoalType.focusMinutes,
  GoalType.workoutWeekly,
};

Future<void> _openPlus(AppFixture app) async {
  await app.tester.tap(plusButton());
  await app.tester.pump();
  await app.settle();
}

Future<void> _closePlus(AppFixture app) async {
  await app.tester.tap(
    find.descendant(of: plusSheet(), matching: find.byIcon(AppIcon.close.data)),
  );
  await app.tester.pump();
  await app.settle();
}

Finder _entry(String id) => find.byKey(ValueKey<String>('plus-entry-$id'));

Finder _inSheet(Finder finder) =>
    find.descendant(of: plusSheet(), matching: finder);

/// The ids of the offered entries in the order they are shown (rows top to
/// bottom, left to right).
List<String> _shown(WidgetTester tester) {
  final found = <(String, Offset)>[];
  for (final id in plusEntryIds) {
    final finder = _entry(id);
    if (finder.evaluate().isNotEmpty) {
      found.add((id, tester.getTopLeft(finder)));
    }
  }
  found.sort((a, b) {
    final byRow = a.$2.dy.compareTo(b.$2.dy);
    return byRow != 0 ? byRow : a.$2.dx.compareTo(b.$2.dx);
  });
  return [for (final entry in found) entry.$1];
}

List<String> _without(Iterable<String> ids) => [
  for (final id in plusEntryIds)
    if (!ids.contains(id)) id,
];

/// What "Meine Ziele" does when the user saves: the new switches are stored for
/// tomorrow.
Future<void> _setGoals(AppFixture app, Map<GoalType, bool> enabled) => app.run(
  () => app.container
      .read(goalsCommandsProvider)
      .update(
        commandId: app.harness.ids.newId(),
        changes: {
          for (final entry in enabled.entries)
            entry.key: GoalSetting(enabled: entry.value),
        },
      ),
);

Future<void> _setGoal(AppFixture app, GoalType type, {required bool on}) =>
    _setGoals(app, {type: on});

Future<void> _switchOff(AppFixture app, Iterable<GoalType> types) =>
    _setGoals(app, {for (final type in types) type: false});

void main() {
  group('filtering by goals (BS-117)', () {
    testWidgets(
      '(BS-117, C02) with every goal on the menu offers all eight entries, '
      'nothing is hidden and there is no hint',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _openPlus(app);
        expect(_shown(tester), plusEntryIds);
        expect(_inSheet(find.text(_hint)), findsNothing);
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);
      },
    );

    for (final id in plusEntryIds.where((id) => plusGoalFor(id) != null)) {
      testWidgets(
        '(BS-117, C02) switching off the goal of "$id" hides exactly its '
        'entry, the others stay in order and a hint says where to change it',
        (tester) async {
          final app = await pumpFullApp(tester, modules: fullFakeModules());
          await _setGoal(app, plusGoalFor(id)!, on: false);
          await _openPlus(app);
          expect(_shown(tester), _without([id]));
          expect(_inSheet(find.text(_hint)), findsOneWidget);
          expect(_inSheet(find.text(_emptyTitle)), findsNothing);
        },
      );
    }

    testWidgets(
      '(BS-117, C02) a goal switched on again brings its entry back at its '
      'usual position, the next time the menu opens',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _setGoal(app, GoalType.water, on: false);
        await _openPlus(app);
        expect(_shown(tester), _without(['water']));
        await _closePlus(app);

        await _setGoal(app, GoalType.water, on: true);
        await _openPlus(app);
        expect(_shown(tester), plusEntryIds, reason: 'Wasser is third again');
        expect(_inSheet(find.text(_hint)), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, C02) a goal switched off is gone the next time the menu opens, '
      'without a restart',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _openPlus(app);
        expect(_shown(tester), plusEntryIds);
        await _closePlus(app);

        await _setGoal(app, GoalType.weightEntry, on: false);
        await _openPlus(app);
        expect(_shown(tester), _without(['weight']));
      },
    );

    testWidgets(
      '(BS-117, C02) the open menu follows goals that change: entries leave '
      'and return, and the hint comes and goes',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _openPlus(app);
        expect(_entry('weight'), findsOneWidget);

        await _setGoal(app, GoalType.weightEntry, on: false);
        await app.settle();
        expect(_shown(tester), _without(['weight']));
        expect(_inSheet(find.text(_hint)), findsOneWidget);

        await _switchOff(app, [GoalType.steps, GoalType.taskCompletion]);
        await app.settle();
        expect(_shown(tester), _without(['weight', 'steps', 'task']));

        await _setGoals(app, {
          GoalType.weightEntry: true,
          GoalType.steps: true,
          GoalType.taskCompletion: true,
        });
        await app.settle();
        expect(_shown(tester), plusEntryIds);
        expect(_inSheet(find.text(_hint)), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, AT24) the menu follows the saved goal at once, while the goal '
      'of today keeps counting for today',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _setGoal(app, GoalType.weightEntry, on: false);

        final versions = (await tester.runAsync(
          () => app.container.read(goalVersionRepositoryProvider).all(),
        ))!;
        final today = LocalDate(2026, 10, 3);
        expect(
          resolveGoalVersion(versions, GoalType.weightEntry, today)!.enabled,
          isTrue,
          reason: 'today the goal is still on (the day ring is not touched)',
        );
        expect(
          resolveGoalVersion(
            versions,
            GoalType.weightEntry,
            nextEffectiveDate(today),
          )!.enabled,
          isFalse,
          reason: 'the saved switch applies from tomorrow',
        );
        await _openPlus(app);
        expect(_entry('weight'), findsNothing);
      },
    );

    for (final moduleOn in <bool>[true, false]) {
      for (final goalOn in <bool>[true, false]) {
        testWidgets('(BS-117, C02, C03) Gewicht with its module '
            '${moduleOn ? 'on' : 'off'} and its goal ${goalOn ? 'on' : 'off'} '
            'is ${moduleOn && goalOn ? 'offered' : 'hidden'}', (tester) async {
          final app = await pumpFullApp(
            tester,
            modules: fullFakeModules(),
            enabledModules: moduleOn
                ? null
                : const <String>{'nutrition', 'focus', 'tasks', 'gamification'},
          );
          if (!goalOn) {
            await _setGoal(app, GoalType.weightEntry, on: false);
          }
          await _openPlus(app);
          expect(
            _entry('weight'),
            moduleOn && goalOn ? findsOneWidget : findsNothing,
          );
          // Schritte share the module, but follow their own goal.
          expect(_entry('steps'), moduleOn ? findsOneWidget : findsNothing);
          // A module off hides its entries as before, whatever the goals say.
          expect(_entry('water'), findsOneWidget);
        });
      }
    }

    testWidgets(
      '(BS-117, C02) habit and meal have no goal: with every goal off they '
      'stay, with the hint and without the empty state',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await _switchOff(app, GoalType.values);
        await _openPlus(app);
        expect(_shown(tester), <String>['habit', 'meal']);
        expect(_inSheet(find.text(_hint)), findsOneWidget);
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, C02) a running focus session follows the goal of Fokus like '
      'Fokus itself',
      (tester) async {
        final app = await pumpFullApp(tester, modules: fullFakeModules());
        await app.run(
          () => app.harness.database
              .into(app.harness.database.focusSessions)
              .insert(focusRow(status: 'paused')),
        );
        await _openPlus(app);
        expect(_inSheet(find.text('Fokus fortsetzen')), findsOneWidget);
        await _closePlus(app);

        await _setGoal(app, GoalType.focusMinutes, on: false);
        await _openPlus(app);
        expect(_inSheet(find.text('Fokus fortsetzen')), findsNothing);
        expect(_inSheet(find.text('Fokus')), findsNothing);
        expect(_shown(tester), _without(['focus']));
      },
    );
  });

  group('empty state (BS-117)', () {
    testWidgets(
      '(BS-117, C02) when the goals hide every entry the menu shows an empty '
      'state with the way to Meine Ziele, not an empty list',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _switchOff(app, _bodyAndFocusGoals);
        await _openPlus(app);

        expect(_shown(tester), isEmpty);
        expect(_inSheet(find.text(_emptyTitle)), findsOneWidget);
        expect(_inSheet(find.text(_emptyMessage)), findsOneWidget);
        expect(_inSheet(find.text(_emptyAction)), findsOneWidget);
        // The title of the menu stays; the hint and the module choice do not
        // belong here.
        expect(find.text('Was möchtest du eintragen?'), findsOneWidget);
        expect(_inSheet(find.text(_hint)), findsNothing);
        expect(_inSheet(find.text('Module verwalten')), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, C02) "Meine Ziele öffnen" closes the menu and opens Meine '
      'Ziele on top of the tab',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _switchOff(app, _bodyAndFocusGoals);
        await _openPlus(app);
        await tester.tap(find.text(_emptyAction));
        await tester.pump();
        await app.settle();

        expect(plusSheet(), findsNothing);
        expect(app.location, '/goals');
        expect(find.text('Ziele'), findsWidgets);
        // Leaving returns to the tab the user started from.
        await tester.tap(find.byIcon(AppIcon.back.data));
        await app.settle();
        expect(app.location, '/');
      },
    );

    testWidgets(
      '(BS-117, C02) the open menu turns into the empty state when the last '
      'goal goes and back into entries when one returns',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _openPlus(app);
        expect(_shown(tester), <String>['weight', 'workout', 'steps', 'focus']);

        await _switchOff(app, _bodyAndFocusGoals);
        await app.settle();
        expect(_shown(tester), isEmpty);
        expect(_inSheet(find.text(_emptyTitle)), findsOneWidget);

        await _setGoal(app, GoalType.steps, on: true);
        await app.settle();
        expect(_shown(tester), <String>['steps']);
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);
        expect(_inSheet(find.text(_hint)), findsOneWidget);
      },
    );

    testWidgets(
      '(BS-117, AT04) with every module off the module choice stays, the '
      'goals do not matter',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: const <String>{},
        );
        await _switchOff(app, GoalType.values);
        await _openPlus(app);
        expect(
          _inSheet(find.textContaining('Alle Module sind ausgeschaltet')),
          findsOneWidget,
        );
        expect(_inSheet(find.text('Module verwalten')), findsOneWidget);
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);
        expect(_inSheet(find.text(_emptyAction)), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, AT04) modules that offer nothing keep their own message, the '
      'goals empty state is only for entries the goals hid',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: const <String>{'gamification'},
        );
        await _switchOff(app, GoalType.values);
        await _openPlus(app);
        expect(
          _inSheet(find.textContaining('gibt es gerade nichts zu erfassen')),
          findsOneWidget,
        );
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);
      },
    );

    testWidgets(
      '(BS-117, AT35) with reduced motion the menu appears in place, also in '
      'the empty state',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          animations: true,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _switchOff(app, _bodyAndFocusGoals);
        await app.run(
          () => app.container
              .read(settingsCommandsProvider)
              .setReduceMotion(commandId: app.harness.ids.newId(), value: true),
        );
        await app.settle();
        await tester.tap(plusButton());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final early = tester.getTopLeft(find.byType(PlusSheet)).dy;
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(PlusSheet)).dy, early);
        expect(_inSheet(find.text(_emptyTitle)), findsOneWidget);
      },
    );
  });

  group('loading and failing goals (BS-117)', () {
    testWidgets(
      '(BS-117, C02) while the goals load the menu waits, no entry flashes up '
      'that is hidden a moment later',
      (tester) async {
        final goals = StreamController<List<GoalVersion>>();
        addTearDown(goals.close);
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          overrides: [goalVersionsProvider.overrideWith((ref) => goals.stream)],
        );
        await _openPlus(app);
        expect(_shown(tester), isEmpty);
        expect(_inSheet(find.byType(NeutralLoading)), findsOneWidget);
        expect(_inSheet(find.text(_emptyTitle)), findsNothing);

        // The first goals arrive: Wasser is off from tomorrow.
        goals.add(<GoalVersion>[
          GoalVersion(
            type: GoalType.water,
            target: GoalType.water.defaultTarget,
            enabled: false,
            effectiveFrom: LocalDate(2026, 10, 4),
          ),
        ]);
        await app.settle();
        expect(_shown(tester), _without(['water']));
      },
    );

    testWidgets(
      '(BS-117, C02) when the goals cannot be read the menu still offers the '
      'entries of the active modules, never a dead end',
      (tester) async {
        final goals = StreamController<List<GoalVersion>>();
        addTearDown(goals.close);
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          overrides: [goalVersionsProvider.overrideWith((ref) => goals.stream)],
        );
        await _openPlus(app);
        goals.addError(StateError('read failed'));
        await app.settle();
        expect(_shown(tester), plusEntryIds);
        expect(_inSheet(find.text(_hint)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('accessibility (BS-117)', () {
    testSemantics(
      '(BS-117, AT34) the empty state is read as one block, the action is a '
      'labelled button of 48 or more and the hint is plain text',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _setGoal(app, GoalType.weightEntry, on: false);
        await _openPlus(app);
        // The filtered menu: entries are labelled buttons, the hint is read.
        for (final label in <String>['Workout', 'Schritte', 'Fokus']) {
          final node = tester.getSemantics(find.bySemanticsLabel(label));
          expect(node.flagsCollection.isButton, isTrue, reason: label);
        }
        expect(find.bySemanticsLabel(_hint), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await _closePlus(app);

        await _switchOff(app, _bodyAndFocusGoals);
        await _openPlus(app);
        final sheet = tester.getSemantics(find.byType(PlusSheet));
        expect(sheet.label, 'Was möchtest du eintragen?');
        expect(sheet.flagsCollection.scopesRoute, isTrue);
        expect(sheet.flagsCollection.namesRoute, isTrue);
        expect(
          find.bySemanticsLabel('$_emptyTitle. $_emptyMessage'),
          findsOneWidget,
        );
        final action = tester.getSemantics(find.bySemanticsLabel(_emptyAction));
        expect(action.flagsCollection.isButton, isTrue);
        expect(
          action.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester.getSize(find.widgetWithText(PrimaryButton, _emptyAction)),
          greaterThanOrEqualTo(const Size(48, 48)),
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      },
    );

    testWidgets(
      '(BS-117, AT33) the action of the empty state is reachable with the '
      'keyboard',
      (tester) async {
        final app = await pumpFullApp(
          tester,
          modules: fullFakeModules(),
          enabledModules: _bodyAndFocus,
        );
        await _switchOff(app, _bodyAndFocusGoals);
        await _openPlus(app);

        final node = Focus.of(tester.element(find.text(_emptyAction)));
        node.requestFocus();
        await tester.pump();
        expect(node.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await app.settle();
        expect(app.location, '/goals');
        expect(plusSheet(), findsNothing);
      },
    );

    for (final variant in AppThemeVariant.values) {
      testWidgets('(BS-117, AT35) the filtered menu and the empty state in the '
          '${variant.name} theme lay out and stay operable', (tester) async {
        final handle = tester.ensureSemantics();
        try {
          final app = await pumpFullApp(
            tester,
            modules: fullFakeModules(),
            enabledModules: _bodyAndFocus,
          );
          await app.run(
            () => app.container
                .read(settingsCommandsProvider)
                .setThemeMode(
                  commandId: app.harness.ids.newId(),
                  themeModeKey: variant.name,
                ),
          );
          await app.settle();
          await _setGoal(app, GoalType.weightEntry, on: false);
          await _openPlus(app);
          expect(
            tester.element(find.byType(PlusSheet)).tokens.variant,
            variant,
            reason: 'the theme of the setting is in effect',
          );
          expect(_inSheet(find.text(_hint)), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          await _switchOff(app, _bodyAndFocusGoals);
          await app.settle();
          expect(_inSheet(find.text(_emptyAction)), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        } finally {
          handle.dispose();
        }
      });
    }

    for (final size in responsiveSizes) {
      testWidgets(
        '(BS-117, AT33) the hint and the empty state at ${size.width.toInt()} '
        'px and 200 % text have no overflow and a reachable action',
        (tester) async {
          final app = await pumpFullApp(
            tester,
            size: size,
            textScale: 2.0,
            modules: fullFakeModules(),
            enabledModules: _bodyAndFocus,
          );
          await _setGoal(app, GoalType.weightEntry, on: false);
          await _openPlus(app);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(_hint));
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final id in <String>['workout', 'steps', 'focus']) {
            await tester.ensureVisible(_entry(id));
            final box = tester.getSize(_entry(id));
            expect(box.height, greaterThanOrEqualTo(48), reason: id);
          }

          // The rest of the goals goes while the menu is open.
          await _switchOff(app, _bodyAndFocusGoals);
          await app.settle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text(_emptyAction));
          await tester.pump();
          final button = tester.getSize(
            find.widgetWithText(PrimaryButton, _emptyAction),
          );
          expect(button.height, greaterThanOrEqualTo(48));
          expect(button.width, greaterThanOrEqualTo(48));
          await tester.tap(find.text(_emptyAction));
          await tester.pump();
          await app.settle();
          expect(app.location, '/goals');
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}
