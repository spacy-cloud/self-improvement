import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:self_improvement/app/router/app_routes.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/modules/module_registry.dart';
import 'package:self_improvement/features/body/presentation/weight_form_screen.dart';
import 'package:self_improvement/features/body/steps/presentation/steps_form_screen.dart';
import 'package:self_improvement/features/focus/presentation/workout_form_screen.dart';
import 'package:self_improvement/features/nutrition/presentation/meal_form_screen.dart';
import 'package:self_improvement/features/nutrition/presentation/water_custom_sheet.dart';
import 'package:self_improvement/features/nutrition/presentation/water_form_body.dart';
import 'package:self_improvement/features/nutrition/presentation/water_goal_sheet.dart';
import 'package:self_improvement/features/profile/presentation/goals_screen.dart';
import 'package:self_improvement/features/profile/presentation/profile_edit_screen.dart';
import 'package:self_improvement/features/settings/presentation/data_sheets.dart';
import 'package:self_improvement/features/tasks/presentation/habit_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/task_form_screen.dart';
import 'package:self_improvement/features/tasks/presentation/tasks_list_view.dart';

import 'support/app_harness.dart';

/// The forms of the running app close the keyboard on a tap beside the field
/// and on a drag, and the save button still works at the first tap (BS-112,
/// D-018, AT33).
///
/// A tester on an iPhone could not close the keyboard of any form: the number
/// pad has no Return key and iOS has no Back gesture. Every case opens a form
/// through the real router of the app (production theme, scaffold, sheets) on a
/// small phone with a simulated keyboard of 300 px (the worst case of the
/// responsive tests: every form overflows, so every form scrolls), and runs the
/// same four steps:
///
/// 1. a tap beside the field closes the keyboard,
/// 2. a drag that starts on the field, beside its caret, closes it (a touch
///    that goes down anywhere else closes it already by the tap beside the
///    field),
/// 3. a tap on the save button works the first time although the keyboard
///    goes away under the finger and the pinned button moves,
/// 4. moving to the next field of the form never hides the keyboard on the way.
///
/// "Android" and "iOS" are what the app runs as: the theme of the app carries
/// the platform of the test variant, so the scroll physics and the gestures of
/// the text fields are those of that platform (BS-98, R1-01). One case is
/// pinned as a limit and not as a wish: on iOS a drag that starts exactly on the
/// caret of a focused field moves the caret, neither the page scrolls nor the
/// keyboard closes (D-018). The big number fields of weight and water are
/// centered, so the caret of the empty field is in their middle, where a finger
/// goes down first; a tap beside the field closes the keyboard there as well.
///
/// The host has no keyboard: `testTextInput.isVisible` is what the app asked
/// the system for. Whether the iPhone keyboard follows is for the device check.
const Size _screen = Size(360, 640);
const double _keyboard = 300;

/// How far from the caret a touch still lands on the invisible handle that iOS
/// puts on the caret of a focused field: the framework gives it at least
/// [kMinInteractiveDimension] square (`_SelectionHandleOverlay`), centered on
/// the caret, and lets it win every drag that starts on it. A finger that goes
/// down farther away than this and a little more is a drag of the page.
const double _caretReach = kMinInteractiveDimension / 2 + 8;

/// One form: how to open it, which fields it has, how to fill it so that
/// saving works, and what shows that the save button did its work.
class _Form {
  const _Form({
    required this.name,
    required this.open,
    required this.first,
    required this.done,
    required this.outside,
    this.fill,
    this.save,
    this.second,
    this.textScale = 1.0,
    this.centered = false,
  });

  final String name;
  final Future<void> Function(AppFixture app) open;

  /// The field the steps start in.
  final Finder first;

  /// Another field of the same form, or null if there is none.
  final Finder? second;

  /// Fills the form so that it can be saved; ends with the keyboard open. Null
  /// for an input without a save button (the search of the task list).
  final Future<void> Function(WidgetTester tester)? fill;

  /// The save button, or null.
  final Finder? save;

  /// Present while the form is open, gone once it saved.
  final Finder done;

  /// A spot beside every field and every control.
  final Finder outside;
  final double textScale;

  /// Whether the field is a big, centered number field: the caret of the empty
  /// field is then in its middle (weight, water amount).
  final bool centered;
}

Finder _labelled(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _valueField(String label) =>
    find.descendant(of: _labelled(label), matching: find.byType(TextField));

Finder _inputOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AppTextField)),
  matching: find.byType(TextField),
);

Finder _header() => find.byType(AppHeader);

Finder _primary() => find.byType(PrimaryButton).last;

Future<void> _go(AppFixture app, String location) async {
  app.router.go(location);
  await app.settle();
}

EditableTextState _editableOf(WidgetTester tester, Finder field) =>
    tester.state<EditableTextState>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );

/// Where the caret of the focused [field] is, in global coordinates.
Offset _caretOf(WidgetTester tester, Finder field) {
  final editable = _editableOf(tester, field);
  final caret = editable.renderEditable.getLocalRectForCaret(
    editable.textEditingValue.selection.extent,
  );
  return editable.renderEditable.localToGlobal(caret.center);
}

/// The text area of [field] in global coordinates.
Rect _textAreaOf(WidgetTester tester, Finder field) {
  final render = _editableOf(tester, field).renderEditable;
  return MatrixUtils.transformRect(
    render.getTransformTo(null),
    Offset.zero & render.size,
  );
}

/// Where the finger goes down for a drag of the page that starts on [field]:
/// in the middle of the text area. On iOS, where the caret is in the middle (a
/// centered, empty number field) and its handle would take the drag, at the end
/// of the area that is farther from the caret: out of reach of the handle
/// ([_caretReach]). The test fails if the field has no such point.
Offset _besideCaret(WidgetTester tester, Finder field) {
  final area = _textAreaOf(tester, field);
  final caret = _caretOf(tester, field);
  if (defaultTargetPlatform != TargetPlatform.iOS ||
      (area.center - caret).dx.abs() >= _caretReach) {
    return area.center;
  }
  final left = Offset(area.left + 8, caret.dy);
  final right = Offset(area.right - 8, caret.dy);
  final start = (right - caret).dx.abs() >= (left - caret).dx.abs()
      ? right
      : left;
  expect(
    (start - caret).dx.abs(),
    greaterThanOrEqualTo(_caretReach),
    reason: 'a point on the field that is out of reach of the caret',
  );
  return start;
}

/// Whether a touch at [point] lands on the text of [field] (and so does not
/// count as a tap beside it).
bool _landsOn(WidgetTester tester, Finder field, Offset point) {
  final target = _editableOf(tester, field).renderEditable;
  return tester
      .hitTestOnBinding(point)
      .path
      .any((entry) => entry.target == target);
}

final List<_Form> _forms = <_Form>[
  _Form(
    name: 'weight',
    open: (app) => _go(app, '/weight/new'),
    first: find.byType(TextField).at(0),
    second: find.byType(TextField).at(1),
    fill: (tester) async {
      await tester.enterText(find.byType(TextField).at(0), '72,5');
    },
    save: find.widgetWithText(PrimaryButton, 'Eintrag speichern'),
    done: find.byType(WeightFormScreen),
    outside: _header(),
    centered: true,
  ),
  _Form(
    name: 'steps',
    open: (app) => _go(app, '/steps/new'),
    first: find.byType(TextField).at(0),
    fill: (tester) async {
      await tester.enterText(find.byType(TextField).at(0), '8000');
    },
    save: _primary(),
    done: find.byType(StepsFormScreen),
    outside: _header(),
  ),
  _Form(
    name: 'water, own amount',
    open: (app) async {
      await _go(app, '/water');
      await app.tester.ensureVisible(find.text('Eigene Menge').first);
      await app.tester.pumpAndSettle();
      await app.tester.tap(find.text('Eigene Menge').first);
      await app.settle();
    },
    first: find.byKey(waterAmountFieldKey),
    second: find.byType(TextField).last,
    fill: (tester) async {
      await tester.enterText(find.byKey(waterAmountFieldKey), '330');
    },
    save: find.descendant(
      of: find.byType(WaterCustomSheet),
      matching: find.byType(PrimaryButton),
    ),
    done: find.byType(WaterCustomSheet),
    outside: find.descendant(
      of: find.byType(WaterCustomSheet),
      matching: find.text('Eigene Menge'),
    ),
    centered: true,
  ),
  _Form(
    name: 'water, daily goal',
    open: (app) async {
      await _go(app, '/water');
      final tile = find.byWidgetPredicate(
        (widget) => widget is EntryListTile && widget.title == 'Tagesziel',
      );
      await app.tester.ensureVisible(tile);
      await app.tester.pumpAndSettle();
      await app.tester.tap(tile);
      await app.settle();
    },
    first: find.descendant(
      of: find.byType(WaterGoalSheet),
      matching: find.byType(TextField),
    ),
    fill: (tester) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(WaterGoalSheet),
          matching: find.byType(TextField),
        ),
        '2600',
      );
    },
    save: find.descendant(
      of: find.byType(WaterGoalSheet),
      matching: find.byType(PrimaryButton),
    ),
    done: find.byType(WaterGoalSheet),
    outside: find.descendant(
      of: find.byType(WaterGoalSheet),
      matching: find.text('Tagesziel ändern'),
    ),
    // At 100 % the whole sheet fits above the keyboard and there is nothing to
    // drag; at 200 % text (also a criterion of the ticket) it scrolls.
    textScale: 2.0,
  ),
  _Form(
    name: 'meal',
    open: (app) => _go(app, '/nutrition/new'),
    first: find.byKey(mealNameFieldKey),
    second: find.byKey(mealKcalFieldKey),
    fill: (tester) async {
      await tester.enterText(find.byKey(mealNameFieldKey), 'Haferflocken');
    },
    save: _primary(),
    done: find.byType(MealFormScreen),
    outside: _header(),
  ),
  _Form(
    name: 'workout',
    open: (app) => _go(app, '/workouts/new'),
    first: find.byType(TextField).at(0),
    second: find.byType(TextField).at(1),
    fill: (tester) async {
      await tester.ensureVisible(find.widgetWithText(AppChoiceChip, 'Kraft'));
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Kraft'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), '45');
    },
    save: find.byType(PrimaryButton),
    done: find.byType(WorkoutFormScreen),
    outside: _header(),
  ),
  _Form(
    name: 'task',
    open: (app) => _go(app, '/tasks/new'),
    first: find.byType(TextField).at(0),
    second: find.byType(TextField).at(1),
    fill: (tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'Einkaufen');
    },
    save: _primary(),
    done: find.byType(TaskFormScreen),
    outside: _header(),
  ),
  _Form(
    name: 'habit',
    open: (app) => _go(app, '/habits/new'),
    first: find.byType(TextField).at(0),
    fill: (tester) async {
      await tester.enterText(find.byType(TextField).at(0), 'Lesen');
    },
    save: _primary(),
    done: find.byType(HabitFormScreen),
    outside: _header(),
  ),
  _Form(
    name: 'goals',
    open: (app) => _go(app, '/goals'),
    first: _valueField('Schrittziel pro Tag'),
    second: _valueField('Fokusziel in Minuten'),
    fill: (tester) async {
      await tester.enterText(_valueField('Schrittziel pro Tag'), '12000');
    },
    save: find.widgetWithText(PrimaryButton, 'Ziele speichern'),
    done: find.byType(GoalsScreen),
    outside: _header(),
  ),
  _Form(
    name: 'profile',
    open: (app) => _go(app, '/profile/edit'),
    first: _inputOf('Name'),
    second: _inputOf('Größe in cm'),
    fill: (tester) async {
      await tester.enterText(_inputOf('Name'), 'Max Mustermann');
    },
    save: find.widgetWithText(PrimaryButton, 'Profil speichern'),
    done: find.byType(ProfileEditScreen),
    outside: _header(),
  ),
  _Form(
    name: 'task search',
    open: (app) async {
      await _go(app, AppRoutes.habitsTasks);
      await app.tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is AppIconButton &&
              widget.semanticLabel == 'Suche und Filter einblenden',
        ),
      );
      await app.settle();
    },
    first: _inputOf('Suche'),
    done: find.byType(TasksListView),
    outside: _header(),
  ),
  _Form(
    name: 'reset sheet',
    open: (app) async {
      await _go(app, '/settings/data');
      final reset = find.text('Zurücksetzen …');
      await app.tester.ensureVisible(reset);
      await app.tester.pumpAndSettle();
      await app.tester.tap(reset);
      await app.settle();
    },
    first: find.descendant(
      of: find.byType(ResetSheet),
      matching: find.byType(TextField),
    ),
    fill: (tester) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(ResetSheet),
          matching: find.byType(TextField),
        ),
        'LÖSCHEN',
      );
    },
    save: find.descendant(
      of: find.byType(ResetSheet),
      matching: find.text('Alles löschen'),
    ),
    done: find.byType(ResetSheet),
    outside: find.descendant(
      of: find.byType(ResetSheet),
      matching: find.text('Wirklich alles zurücksetzen?'),
    ),
  ),
];

/// The paths of [routes] and of their children (as in the route sweep).
Iterable<String> _paths(List<RouteBase> routes, [String prefix = '']) sync* {
  for (final route in routes) {
    if (route is! GoRoute) {
      continue;
    }
    final full = route.path.startsWith('/')
        ? route.path
        : '${prefix == '/' ? '' : prefix}/${route.path}';
    yield full;
    yield* _paths(route.routes, full);
  }
}

/// Every page of the app that has no id in its path: the core pages and the
/// pages of all bundled modules, found from the route tables themselves.
final List<String> _pages = <String>{
  AppRoutes.home,
  AppRoutes.analysis,
  AppRoutes.habits,
  AppRoutes.habitsTasks,
  AppRoutes.profile,
  AppRoutes.profileEdit,
  AppRoutes.goals,
  AppRoutes.settings,
  AppRoutes.modules,
  AppRoutes.data,
  AppRoutes.licenses,
  for (final module in bundledModules) ..._paths(module.routes),
}.where((path) => !path.contains(':')).toList()..sort();

/// What the scroll view around [element] does with the keyboard on a drag, or
/// `null` when no scroll view is around it.
ScrollViewKeyboardDismissBehavior? _dismissBehaviorAbove(Element element) {
  ScrollViewKeyboardDismissBehavior? found;
  var inside = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is SingleChildScrollView) {
      inside = true;
      found = widget.keyboardDismissBehavior;
    } else if (widget is ScrollView) {
      inside = true;
      found = widget.keyboardDismissBehavior;
    }
    return !inside;
  });
  return inside ? (found ?? ScrollViewKeyboardDismissBehavior.manual) : null;
}

void main() {
  // The keyboard of an iPhone is the case of the ticket; Android keeps working.
  const platforms = TargetPlatformVariant(<TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
  });

  bool keyboardShown(WidgetTester tester) => tester.testTextInput.isVisible;

  bool anyFieldHasFocus(WidgetTester tester) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .any((field) => field.focusNode.hasFocus);

  /// Opens [form] in the running app and runs [body]. The app is taken down
  /// again when [body] throws: a failed expectation while a form is open would
  /// otherwise hang the test run in its tear down instead of failing it.
  Future<void> inForm(
    WidgetTester tester,
    _Form form,
    Future<void> Function(AppFixture app) body,
  ) async {
    final app = await pumpFullApp(
      tester,
      size: _screen,
      textScale: form.textScale,
    );
    try {
      await form.open(app);
      expect(form.done, findsOneWidget, reason: '${form.name} is open');
      expect(
        Theme.of(tester.element(form.done)).platform,
        defaultTargetPlatform,
        reason: 'the app runs as the platform of the variant (BS-98, R1-01)',
      );
      // The keyboard comes after the form: the layout shrinks around it.
      tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
      await tester.pumpAndSettle();
      await body(app);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await app.settle();
    }
  }

  /// The scroll position of the page around [field].
  ScrollPosition pageOf(WidgetTester tester, Finder field) => tester
      .state<ScrollableState>(
        find.ancestor(of: field, matching: find.byType(Scrollable)).first,
      )
      .position;

  /// Scrolls [field] into view and taps it, then lets the scroll view come to
  /// rest: it brings the caret into view with a short animation during which it
  /// ignores touches.
  Future<void> tapField(WidgetTester tester, Finder field) async {
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.tap(field);
    await tester.pumpAndSettle();
  }

  for (final form in _forms) {
    group(form.name, () {
      testWidgets('a tap beside the field closes the keyboard (BS-112, AT33)', (
        tester,
      ) async {
        await inForm(tester, form, (app) async {
          await tapField(tester, form.first);
          expect(keyboardShown(tester), isTrue, reason: 'the tap opened it');
          expect(anyFieldHasFocus(tester), isTrue);

          await tester.ensureVisible(form.outside.first);
          await tester.pumpAndSettle();
          await tester.tapAt(tester.getCenter(form.outside.first));
          await tester.pump();

          expect(keyboardShown(tester), isFalse);
          expect(anyFieldHasFocus(tester), isFalse);
          expect(form.done, findsOneWidget, reason: 'the form stays open');
        });
      }, variant: platforms);

      testWidgets(
        'a drag that starts on the field, beside its caret, closes it (BS-112, AT33)',
        (tester) async {
          await inForm(tester, form, (app) async {
            await tapField(tester, form.first);
            expect(keyboardShown(tester), isTrue);
            final start = _besideCaret(tester, form.first);
            expect(
              _landsOn(tester, form.first, start),
              isTrue,
              reason:
                  'the touch must go down ON the field, or the tap beside '
                  'the field would close the keyboard and not the drag',
            );

            // A drag against the end of the page does not scroll and so does
            // not count as a drag of the page: go the way the page can move.
            final page = pageOf(tester, form.first);
            expect(
              page.maxScrollExtent,
              greaterThan(0),
              reason: 'the form scrolls',
            );
            final before = page.pixels;
            final toEnd = before < page.maxScrollExtent;
            await tester.dragFrom(start, Offset(0, toEnd ? -120 : 120));
            await tester.pump();

            expect(page.pixels, isNot(before), reason: 'the page scrolled');
            expect(keyboardShown(tester), isFalse);
            expect(anyFieldHasFocus(tester), isFalse);
          });
        },
        variant: platforms,
      );

      if (form.centered) {
        testWidgets(
          'a drag that starts exactly on the caret of the centered, empty field moves the caret on iOS and does not scroll or close; on Android it closes (BS-112, R1-01, AT33)',
          (tester) async {
            await inForm(tester, form, (app) async {
              await tapField(tester, form.first);
              expect(keyboardShown(tester), isTrue);
              expect(
                _editableOf(tester, form.first).textEditingValue.text,
                isEmpty,
                reason: 'the field is empty: its caret is in the middle',
              );
              final caret = _caretOf(tester, form.first);
              expect(
                (caret.dx - tester.getCenter(form.first).dx).abs(),
                lessThan(8),
                reason: 'the caret of a centered field is in its middle',
              );
              expect(_landsOn(tester, form.first, caret), isTrue);

              final page = pageOf(tester, form.first);
              expect(page.maxScrollExtent, greaterThan(0));
              final before = page.pixels;
              final toEnd = before < page.maxScrollExtent;
              await tester.dragFrom(caret, Offset(0, toEnd ? -120 : 120));
              await tester.pump();

              if (defaultTargetPlatform == TargetPlatform.iOS) {
                expect(
                  page.pixels,
                  before,
                  reason: 'the drag moved the caret, the page stayed',
                );
                expect(keyboardShown(tester), isTrue);
                expect(anyFieldHasFocus(tester), isTrue);

                // The tap beside the field closes it always.
                await tester.ensureVisible(form.outside.first);
                await tester.pumpAndSettle();
                await tester.tapAt(tester.getCenter(form.outside.first));
                await tester.pump();
                expect(keyboardShown(tester), isFalse);
                expect(anyFieldHasFocus(tester), isFalse);
              } else {
                expect(page.pixels, isNot(before), reason: 'the page scrolled');
                expect(keyboardShown(tester), isFalse);
                expect(anyFieldHasFocus(tester), isFalse);
              }
            });
          },
          variant: platforms,
        );
      }

      if (form.save != null) {
        testWidgets(
          'a tap on the save button works the first time, although the keyboard goes away under the finger (BS-112, AT33)',
          (tester) async {
            await inForm(tester, form, (app) async {
              await form.fill!(tester);
              await tester.pumpAndSettle();
              expect(keyboardShown(tester), isTrue);
              await tester.ensureVisible(form.save!);
              await tester.pumpAndSettle();

              final finger = await tester.startGesture(
                tester.getCenter(form.save!.first),
              );
              await tester.pump();
              expect(
                keyboardShown(tester),
                isFalse,
                reason: 'closed at the touch',
              );

              // The system takes the keyboard away: the pinned button moves
              // while the finger is on it.
              tester.view.viewInsets = FakeViewPadding.zero;
              await tester.pump(const Duration(milliseconds: 50));
              await finger.up();
              await app.settle();
              await app.settle();

              expect(
                form.done,
                findsNothing,
                reason: 'one tap saved the form: ${form.name}',
              );
            });
          },
        );
      }

      if (form.second != null) {
        testWidgets(
          'moving to the next field never hides the keyboard (BS-112, AT33)',
          (tester) async {
            await inForm(tester, form, (app) async {
              await tapField(tester, form.first);
              expect(keyboardShown(tester), isTrue);

              await tester.ensureVisible(form.second!);
              await tester.pumpAndSettle();
              tester.testTextInput.log.clear();
              await tester.tap(form.second!);
              await tester.pump();

              expect(keyboardShown(tester), isTrue);
              expect(anyFieldHasFocus(tester), isTrue);
              expect(
                <String>[
                  for (final call in tester.testTextInput.log) call.method,
                ],
                isNot(contains('TextInput.hide')),
                reason: 'a hide and a show in a row would flicker',
              );
            });
          },
        );
      }
    });
  }

  testWidgets(
    'a rejected save with the keyboard open puts the focus on the first invalid field and brings the keyboard back (BS-112, BS-90, AT33)',
    (tester) async {
      final app = await pumpFullApp(tester, size: _screen);
      try {
        app.router.go('/tasks/new');
        await app.settle();
        tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
        await tester.pumpAndSettle();
        final title = find.byType(TextField).at(0);
        final description = find.byType(TextField).at(2);

        // The keyboard is open on the description; the required title is empty.
        await tester.enterText(description, 'Belege sammeln');
        await tester.pumpAndSettle();
        expect(keyboardShown(tester), isTrue);
        expect(
          tester.widget<TextField>(description).focusNode!.hasFocus,
          isTrue,
        );

        final save = find.widgetWithText(PrimaryButton, 'Aufgabe speichern');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await app.settle();

        expect(find.text('Bitte gib einen Titel ein.'), findsOneWidget);
        expect(find.byType(TaskFormScreen), findsOneWidget);
        expect(
          tester.widget<TextField>(title).focusNode!.hasFocus,
          isTrue,
          reason: 'the first invalid field has the focus again',
        );
        expect(
          keyboardShown(tester),
          isTrue,
          reason: 'and the keyboard is back',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await app.settle();
      }
    },
  );

  testWidgets(
    'every text field on every page of the app closes the keyboard on a tap beside it and on a drag of its page (BS-112, AT33)',
    (tester) async {
      final app = await pumpFullApp(tester, size: _screen);
      final withFields = <String>[];
      final problems = <String>[];
      try {
        for (final page in _pages) {
          app.router.go(page);
          await app.settle();
          final fields = find.byType(TextField).evaluate().toList();
          if (fields.isEmpty) {
            continue;
          }
          withFields.add(page);
          for (final element in fields) {
            if ((element.widget as TextField).onTapOutside == null) {
              problems.add(
                '$page: a TextField does not close the keyboard on a tap beside it',
              );
            }
            final behavior = _dismissBehaviorAbove(element);
            if (behavior != null &&
                behavior != ScrollViewKeyboardDismissBehavior.onDrag) {
              problems.add(
                '$page: the scroll view around a TextField does not close the keyboard on a drag',
              );
            }
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await app.settle();
      }

      expect(problems, isEmpty);
      expect(
        withFields,
        containsAll(<String>[
          '/weight/new',
          '/steps/new',
          '/nutrition/new',
          '/workouts/new',
          '/tasks/new',
          '/habits/new',
          '/profile/edit',
          '/goals',
        ]),
        reason: 'the sweep finds the known forms',
      );
    },
  );
}
