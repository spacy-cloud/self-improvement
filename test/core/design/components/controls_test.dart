import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart'
    show TextInputAction, TextInputFormatter, TextInputType;
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';

import '../support/design_test_harness.dart';

const Key _knob = ValueKey<String>('app_switch_knob');

/// Hosts a stateful value so that taps change the displayed state.
class _Host extends StatefulWidget {
  const _Host({required this.builder});

  final Widget Function(bool value, ValueChanged<bool> onChanged) builder;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  bool value = false;

  @override
  Widget build(BuildContext context) {
    return widget.builder(value, (v) => setState(() => value = v));
  }
}

void main() {
  setUpAll(loadInterFont);

  group('AppSwitch', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: on and off look and speak as designed', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          Column(
            children: <Widget>[
              AppSwitch(
                key: const ValueKey<String>('on'),
                value: true,
                onChanged: (_) {},
                semanticLabel: 'Erinnerung',
              ),
              AppSwitch(
                key: const ValueKey<String>('off'),
                value: false,
                onChanged: (_) {},
                semanticLabel: 'Haptik',
              ),
            ],
          ),
          variant: variant,
        );
        final on = find.byKey(const ValueKey<String>('on'));
        final off = find.byKey(const ValueKey<String>('off'));
        expect(tester.getSize(on), const Size(48, 48));
        expect(tester.getSize(off), const Size(48, 48));

        BoxDecoration trackOf(Finder switchFinder) {
          final container = find.descendant(
            of: switchFinder,
            matching: find.byType(AnimatedContainer),
          );
          return tester.widget<AnimatedContainer>(container).decoration!
              as BoxDecoration;
        }

        expect(trackOf(on).color, colors.toggleOn);
        expect(trackOf(off).color, colors.borderInput);
        final track = find.descendant(
          of: on,
          matching: find.byType(AnimatedContainer),
        );
        expect(tester.getSize(track), const Size(44, 26));
        expect(
          tester.getSize(find.descendant(of: on, matching: find.byKey(_knob))),
          const Size(22, 22),
        );

        final onNode = tester.getSemantics(on);
        expect(onNode.label, 'Erinnerung');
        expect(onNode.flagsCollection.isToggled, Tristate.isTrue);
        expect(onNode.flagsCollection.isEnabled, Tristate.isTrue);
        expect(
          onNode.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          tester.getSemantics(off).flagsCollection.isToggled,
          Tristate.isFalse,
        );
      });
    }

    testWidgets('a tap flips the value through onChanged', (tester) async {
      final seen = <bool>[];
      await pumpDesign(
        tester,
        _Host(
          builder: (value, onChanged) => AppSwitch(
            value: value,
            onChanged: (v) {
              seen.add(v);
              onChanged(v);
            },
            semanticLabel: 'Haptik',
          ),
        ),
      );
      await tester.tap(find.byType(AppSwitch));
      await settle(tester);
      await tester.tap(find.byType(AppSwitch));
      await settle(tester);
      expect(seen, <bool>[true, false]);
    });

    testWidgets(
      'the knob moves in 150 ms with motion and immediately when reduced',
      (tester) async {
        Widget switchUnderTest() => _Host(
          builder: (value, onChanged) => AppSwitch(
            value: value,
            onChanged: onChanged,
            semanticLabel: 'Haptik',
          ),
        );

        // Normal motion: after a short pump the knob is still on its way.
        await pumpDesign(tester, switchUnderTest());
        final left = tester.getTopLeft(find.byKey(_knob)).dx;
        await tester.tap(find.byType(AppSwitch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final mid = tester.getTopLeft(find.byKey(_knob)).dx;
        expect(mid, greaterThan(left));
        expect(mid, lessThan(left + 18));
        await settle(tester);
        expect(tester.getTopLeft(find.byKey(_knob)).dx, left + 18);

        // Reduced motion (app setting): one frame is enough.
        await pumpDesign(tester, switchUnderTest(), reduceMotion: true);
        final startLeft = tester.getTopLeft(find.byKey(_knob)).dx;
        await tester.tap(find.byType(AppSwitch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.getTopLeft(find.byKey(_knob)).dx, startLeft + 18);

        // Reduced motion (system flag): the same.
        await pumpDesign(tester, switchUnderTest(), disableAnimations: true);
        final systemLeft = tester.getTopLeft(find.byKey(_knob)).dx;
        await tester.tap(find.byType(AppSwitch));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.getTopLeft(find.byKey(_knob)).dx, systemLeft + 18);
      },
    );

    testSemantics('disabled switch is not tappable', (tester) async {
      await pumpDesign(
        tester,
        const AppSwitch(
          value: true,
          onChanged: null,
          semanticLabel: 'Gesperrt',
        ),
      );
      final node = tester.getSemantics(find.byType(AppSwitch));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      await tester.tap(find.byType(AppSwitch), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      // The knob stays on the right: nothing happened.
      final track = tester.getTopLeft(find.byType(AnimatedContainer)).dx;
      expect(tester.getTopLeft(find.byKey(_knob)).dx, track + 20);
    });
  });

  group('RoundCheckbox', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: checked and unchecked look and speak as designed',
        (tester) async {
          await pumpDesign(
            tester,
            Column(
              children: <Widget>[
                RoundCheckbox(
                  key: const ValueKey<String>('on'),
                  value: true,
                  onChanged: (_) {},
                  semanticLabel: '10 Min. lesen',
                  checkedStateLabel: 'erledigt',
                  uncheckedStateLabel: 'offen',
                ),
                RoundCheckbox(
                  key: const ValueKey<String>('off'),
                  value: false,
                  onChanged: (_) {},
                  semanticLabel: '5 Min. dehnen',
                  checkedStateLabel: 'erledigt',
                  uncheckedStateLabel: 'offen',
                ),
              ],
            ),
            variant: variant,
          );
          final on = find.byKey(const ValueKey<String>('on'));
          final off = find.byKey(const ValueKey<String>('off'));
          expect(tester.getSize(on), const Size(48, 48));

          BoxDecoration boxOf(Finder f) =>
              tester
                      .widget<AnimatedContainer>(
                        find.descendant(
                          of: f,
                          matching: find.byType(AnimatedContainer),
                        ),
                      )
                      .decoration!
                  as BoxDecoration;

          expect(boxOf(on).color, colors.primaryButton);
          expect(boxOf(on).shape, BoxShape.circle);
          expect(boxOf(on).border, isNull);
          expect(boxOf(off).color, colors.surface);
          final border = boxOf(off).border! as Border;
          expect(border.top.color, colors.borderInput);
          expect(border.top.width, 2);
          expect(
            tester.getSize(
              find.descendant(of: on, matching: find.byType(AnimatedContainer)),
            ),
            const Size(28, 28),
          );
          final checkIcon = tester.widget<Icon>(
            find.descendant(of: on, matching: find.byIcon(Icons.check_rounded)),
          );
          expect(checkIcon.color, colors.onPrimary);
          final opacity = tester.widget<AnimatedOpacity>(
            find.descendant(of: off, matching: find.byType(AnimatedOpacity)),
          );
          expect(opacity.opacity, 0);

          final onNode = tester.getSemantics(on);
          expect(onNode.label, '10 Min. lesen');
          expect(onNode.value, 'erledigt');
          expect(onNode.flagsCollection.isChecked, CheckedState.isTrue);
          final offNode = tester.getSemantics(off);
          expect(offNode.value, 'offen');
          expect(offNode.flagsCollection.isChecked, CheckedState.isFalse);
        },
      );
    }

    testWidgets('a tap flips the value', (tester) async {
      final seen = <bool>[];
      await pumpDesign(
        tester,
        _Host(
          builder: (value, onChanged) => RoundCheckbox(
            value: value,
            onChanged: (v) {
              seen.add(v);
              onChanged(v);
            },
            semanticLabel: 'Aufgabe',
          ),
        ),
      );
      await tester.tap(find.byType(RoundCheckbox));
      await settle(tester);
      await tester.tap(find.byType(RoundCheckbox));
      await settle(tester);
      expect(seen, <bool>[true, false]);
    });

    testSemantics('without state labels the platform checked state is used', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        RoundCheckbox(value: true, onChanged: (_) {}, semanticLabel: 'Aufgabe'),
      );
      final node = tester.getSemantics(find.byType(RoundCheckbox));
      expect(node.value, isEmpty);
      expect(node.flagsCollection.isChecked, CheckedState.isTrue);
    });

    testWidgets('reduced motion changes the box immediately', (tester) async {
      await pumpDesign(
        tester,
        _Host(
          builder: (value, onChanged) => RoundCheckbox(
            value: value,
            onChanged: onChanged,
            semanticLabel: 'Aufgabe',
          ),
        ),
        reduceMotion: true,
      );
      await tester.tap(find.byType(RoundCheckbox));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1);
      final decoration =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect(decoration.color, AppColors.light.primaryButton);
    });
  });

  group('chips', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: AppChoiceChip selected and unselected', (
        tester,
      ) async {
        await pumpDesign(
          tester,
          Wrap(
            children: <Widget>[
              AppChoiceChip(
                key: const ValueKey<String>('on'),
                label: 'Kraft',
                selected: true,
                onSelected: (_) {},
              ),
              AppChoiceChip(
                key: const ValueKey<String>('off'),
                label: 'Cardio',
                selected: false,
                onSelected: (_) {},
              ),
            ],
          ),
          variant: variant,
        );
        final on = find.byKey(const ValueKey<String>('on'));
        final off = find.byKey(const ValueKey<String>('off'));

        ShapeDecoration decorationOf(Finder f) =>
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: f,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as ShapeDecoration;

        final onDecoration = decorationOf(on);
        expect(onDecoration.color, colors.primaryTint);
        final onShape = onDecoration.shape as StadiumBorder;
        expect(onShape.side.color, colors.primaryButton);
        expect(onShape.side.width, 1.5);
        final offDecoration = decorationOf(off);
        expect(offDecoration.color, colors.surface);
        final offShape = offDecoration.shape as StadiumBorder;
        expect(offShape.side.color, colors.borderInput);
        expect(offShape.side.width, 1);

        // Selection is not colour only: a check mark and a heavier label.
        expect(
          find.descendant(of: on, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: off, matching: find.byIcon(Icons.check_rounded)),
          findsNothing,
        );
        final onStyle = tester
            .widget<Text>(find.descendant(of: on, matching: find.text('Kraft')))
            .style!;
        final offStyle = tester
            .widget<Text>(
              find.descendant(of: off, matching: find.text('Cardio')),
            )
            .style!;
        expect(onStyle.fontWeight, FontWeight.w600);
        expect(onStyle.color, colors.primaryText);
        expect(offStyle.fontWeight, FontWeight.w500);
        expect(offStyle.color, colors.textPrimary);

        expect(tester.getSize(on).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(off).height, greaterThanOrEqualTo(48));

        final onNode = tester.getSemantics(on);
        expect(onNode.label, 'Kraft');
        expect(onNode.flagsCollection.isSelected, Tristate.isTrue);
        expect(onNode.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(
          tester.getSemantics(off).flagsCollection.isSelected,
          Tristate.isFalse,
        );
      });
    }

    testWidgets('a choice chip always reports true, a filter chip toggles', (
      tester,
    ) async {
      final choice = <bool>[];
      final filter = <bool>[];
      await pumpDesign(
        tester,
        Wrap(
          children: <Widget>[
            AppChoiceChip(
              label: 'Kraft',
              selected: true,
              onSelected: choice.add,
            ),
            AppFilterChip(
              label: 'Mobility',
              selected: true,
              onSelected: filter.add,
            ),
            AppFilterChip(
              label: 'Sport',
              selected: false,
              onSelected: filter.add,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Kraft'));
      await tester.tap(find.text('Mobility'));
      await tester.tap(find.text('Sport'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(choice, <bool>[true]);
      expect(filter, <bool>[false, true]);
    });

    testSemantics('a filter chip is not in an exclusive group', (tester) async {
      await pumpDesign(
        tester,
        AppFilterChip(label: 'Mobility', selected: true, onSelected: (_) {}),
      );
      final node = tester.getSemantics(find.byType(AppFilterChip));
      expect(node.flagsCollection.isInMutuallyExclusiveGroup, isFalse);
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
    });

    testSemantics('a disabled chip is not tappable', (tester) async {
      await pumpDesign(
        tester,
        const AppChoiceChip(label: 'Kraft', selected: false, onSelected: null),
      );
      final node = tester.getSemantics(find.byType(AppChoiceChip));
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
    });

    testWidgets('the label wraps on large text without overflow', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        AppChoiceChip(
          label: 'Ganzkörper und Beweglichkeit',
          selected: true,
          onSelected: (_) {},
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PeriodSelector', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics(
        '${variant.name}: the selected segment is raised and announced selected',
        (tester) async {
          await pumpDesign(
            tester,
            PeriodSelector<int>(
              options: PeriodSelector.dayOptions,
              selected: 7,
              onChanged: (_) {},
              semanticLabel: 'Zeitraum',
            ),
            variant: variant,
          );
          final track = tester.widget<DecoratedBox>(
            find
                .descendant(
                  of: find.byType(PeriodSelector<int>),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect((track.decoration as BoxDecoration).color, colors.track);

          final selected = tester.getSemantics(find.text('7 Tage'));
          expect(selected.label, '7 Tage');
          expect(selected.flagsCollection.isSelected, Tristate.isTrue);
          expect(selected.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
          expect(
            tester
                .getSemantics(find.text('30 Tage'))
                .flagsCollection
                .isSelected,
            Tristate.isFalse,
          );
          expect(
            tester
                .getSemantics(find.text('90 Tage'))
                .flagsCollection
                .isSelected,
            Tristate.isFalse,
          );

          expect(textColor(tester, '7 Tage'), colors.textPrimary);
          expect(textColor(tester, '30 Tage'), colors.textSecondary);
          for (final label in <String>['7 Tage', '30 Tage', '90 Tage']) {
            expect(
              tester.getSemantics(find.text(label)).rect.height,
              greaterThanOrEqualTo(48),
            );
            expect(
              tester.getSemantics(find.text(label)).rect.width,
              greaterThanOrEqualTo(48),
            );
          }
        },
      );
    }

    testWidgets('tapping a segment reports its value', (tester) async {
      final seen = <int>[];
      await pumpDesign(
        tester,
        PeriodSelector.days(selectedDays: 7, onChanged: seen.add),
      );
      await tester.tap(find.text('30 Tage'));
      await tester.tap(find.text('90 Tage'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(seen, <int>[30, 90]);
    });

    testWidgets('works with generic options and wraps on large text', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        PeriodSelector<String>(
          options: const <PeriodOption<String>>[
            PeriodOption<String>(value: 'a', label: 'Aufgaben'),
            PeriodOption<String>(value: 'g', label: 'Gewohnheiten'),
          ],
          selected: 'g',
          onChanged: (_) {},
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('QuantityStepper', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testSemantics('${variant.name}: buttons, value and labels', (
        tester,
      ) async {
        var plus = 0;
        var minus = 0;
        await pumpDesign(
          tester,
          QuantityStepper(
            valueText: '71,5',
            unit: 'kg',
            onIncrease: () => plus++,
            onDecrease: () => minus++,
          ),
          variant: variant,
        );
        expect(find.text('71,5 kg'), findsOneWidget);
        expect(textColor(tester, '71,5 kg'), colors.textPrimary);
        expect(tester.widget<Text>(find.text('71,5 kg')).style?.fontSize, 34);

        final increase = tester.getSemantics(find.bySemanticsLabel('erhöhen'));
        final decrease = tester.getSemantics(
          find.bySemanticsLabel('verringern'),
        );
        expect(increase.rect.size, const Size(48, 48));
        expect(decrease.rect.size, const Size(48, 48));
        expect(increase.flagsCollection.isButton, isTrue);
        final value = tester.getSemantics(find.bySemanticsLabel('71,5 kg'));
        expect(value.flagsCollection.isLiveRegion, isTrue);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.pump(const Duration(milliseconds: 400));
        expect(plus, 1);
        expect(minus, 2);
      });
    }

    testSemantics('a missing callback disables its button', (tester) async {
      await pumpDesign(
        tester,
        const QuantityStepper(
          valueText: '400',
          unit: 'kg',
          onIncrease: null,
          onDecrease: _noop,
        ),
      );
      final increase = tester.getSemantics(find.bySemanticsLabel('erhöhen'));
      expect(increase.flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('verringern'))
            .flagsCollection
            .isEnabled,
        Tristate.isTrue,
      );
    });

    testSemantics('labels and the spoken value can be customised', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const QuantityStepper(
          valueText: '250',
          unit: 'ml',
          onIncrease: _noop,
          onDecrease: _noop,
          increaseLabel: 'Menge erhöhen',
          decreaseLabel: 'Menge verringern',
          valueSemanticLabel: '250 Milliliter',
        ),
      );
      expect(find.bySemanticsLabel('Menge erhöhen'), findsOneWidget);
      expect(find.bySemanticsLabel('Menge verringern'), findsOneWidget);
      expect(find.bySemanticsLabel('250 Milliliter'), findsOneWidget);
    });

    testWidgets('the value wraps on large text without overflow', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const QuantityStepper(
          valueText: '71,5',
          unit: 'kg',
          onIncrease: _noop,
          onDecrease: _noop,
          expand: true,
        ),
        width: 320,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('AppTextField', () {
    for (final variant in allVariants) {
      final colors = variant.colors;

      testWidgets(
        '${variant.name}: permanent label, requirement hint and value',
        (tester) async {
          final controller = TextEditingController(text: '71,5');
          addTearDown(controller.dispose);
          await pumpDesign(
            tester,
            AppTextField(
              label: 'Gewicht in kg',
              requirementLabel: 'Pflichtfeld',
              controller: controller,
            ),
            variant: variant,
          );
          expect(find.text('Gewicht in kg'), findsOneWidget);
          expect(find.text('Pflichtfeld'), findsOneWidget);
          expect(textColor(tester, 'Gewicht in kg'), colors.textPrimary);
          expect(textColor(tester, 'Pflichtfeld'), colors.textSecondary);
          // The label stays visible while text is entered.
          await tester.enterText(find.byType(TextField), '72');
          await tester.pump();
          expect(find.text('Gewicht in kg'), findsOneWidget);
          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.style?.color, colors.textPrimary);
          expect(field.style?.fontSize, 15);
        },
      );

      testWidgets(
        '${variant.name}: error state shows the message with icon and error border',
        (tester) async {
          await pumpDesign(
            tester,
            const AppTextField(
              label: 'Gewicht in kg',
              helperText: 'Nur Zahlen',
              errorText: 'Bitte einen Wert zwischen 20 und 400 kg eingeben.',
            ),
            variant: variant,
          );
          expect(
            find.text('Bitte einen Wert zwischen 20 und 400 kg eingeben.'),
            findsOneWidget,
          );
          expect(
            textColor(
              tester,
              'Bitte einen Wert zwischen 20 und 400 kg eingeben.',
            ),
            colors.error,
          );
          expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
          expect(find.text('Nur Zahlen'), findsNothing);
          final decoration = tester
              .widget<TextField>(find.byType(TextField))
              .decoration!;
          final border = decoration.enabledBorder! as OutlineInputBorder;
          expect(border.borderSide.color, colors.error);
          expect(border.borderSide.width, 2);
          expect(border.borderRadius, AppRadii.controlBorder);
        },
      );
    }

    testWidgets(
      'default state: helper text instead of error, input grey border from the theme',
      (tester) async {
        await pumpDesign(
          tester,
          const AppTextField(label: 'Notiz', helperText: 'Optional'),
        );
        expect(find.text('Optional'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        final theme = AppTheme.light().inputDecorationTheme;
        final enabled = theme.enabledBorder! as OutlineInputBorder;
        expect(enabled.borderSide.color, AppColors.light.borderInput);
        expect(enabled.borderSide.width, 1.5);
        final focused = theme.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, AppColors.light.primaryButton);
        expect(focused.borderSide.width, 2);
      },
    );

    testWidgets(
      'the field is named by its label, the helper or the error is its hint',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpDesign(
          tester,
          Column(
            children: const [
              AppTextField(
                label: 'Notiz',
                requirementLabel: 'optional',
                helperText: 'Zum Beispiel: nach dem Training',
              ),
              AppTextField(label: 'Größe', errorText: 'Bitte prüfen'),
            ],
          ),
        );

        final note = tester.getSemantics(find.byType(TextField).first);
        expect(note.getSemanticsData().label, contains('Notiz, optional'));
        expect(note.getSemanticsData().hint, 'Zum Beispiel: nach dem Training');
        final size = tester.getSemantics(find.byType(TextField).last);
        expect(size.getSemanticsData().hint, 'Bitte prüfen');
        expect(find.bySemanticsLabel('Bitte prüfen'), findsNothing);
        handle.dispose();
      },
    );

    testWidgets('a unit suffix in a scrolling form does not break semantics', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpDesign(
        tester,
        Column(
          children: [
            for (var i = 0; i < 12; i++)
              AppTextField(
                label: 'Feld $i',
                controller: TextEditingController(text: '18$i'),
                suffixText: 'cm',
                errorText: i.isEven ? 'Bitte prüfen' : null,
              ),
          ],
        ),
        height: 500,
      );
      for (var i = 0; i < 4; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump();
      }
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });

    testWidgets('focus is shown through the decorator', (tester) async {
      await pumpDesign(tester, const AppTextField(label: 'Notiz'));
      final decorator = find.byType(InputDecorator);
      expect(tester.widget<InputDecorator>(decorator).isFocused, isFalse);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.widget<InputDecorator>(decorator).isFocused, isTrue);
    });

    testWidgets(
      'numeric uses the decimal keyboard and only accepts digits and separators',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpDesign(
          tester,
          AppTextField(
            label: 'Gewicht in kg',
            numeric: true,
            controller: controller,
          ),
        );
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(
          field.keyboardType,
          const TextInputType.numberWithOptions(decimal: true),
        );
        await tester.enterText(find.byType(TextField), 'a71,5kg');
        expect(controller.text, '71,5');
        await tester.enterText(find.byType(TextField), '71.5');
        expect(controller.text, '71.5');
      },
    );

    testWidgets('custom formatters replace the numeric default', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpDesign(
        tester,
        AppTextField(
          label: 'Code',
          numeric: true,
          controller: controller,
          inputFormatters: const <TextInputFormatter>[],
        ),
      );
      await tester.enterText(find.byType(TextField), 'ab1');
      expect(controller.text, 'ab1');
    });

    testWidgets('callbacks, max length and suffix', (tester) async {
      final changes = <String>[];
      final submits = <String>[];
      await pumpDesign(
        tester,
        AppTextField(
          label: 'Name',
          suffixText: 'kg',
          maxLength: 5,
          onChanged: changes.add,
          onSubmitted: submits.add,
          textInputAction: TextInputAction.done,
        ),
      );
      expect(find.text('kg'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'abcdefgh');
      expect(changes.last, 'abcde');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submits, <String>['abcde']);
      // No character counter is drawn.
      expect(find.text('5/5'), findsNothing);
    });

    testSemantics('label, hint and error are part of the field semantics', (
      tester,
    ) async {
      await pumpDesign(
        tester,
        const AppTextField(
          label: 'Gewicht in kg',
          requirementLabel: 'Pflichtfeld',
          errorText: 'Bitte einen Wert zwischen 20 und 400 kg eingeben.',
        ),
      );
      final node = tester.getSemantics(find.byType(TextField));
      expect(node.flagsCollection.isTextField, isTrue);
      final spoken = '${node.label} ${node.value} ${node.hint}';
      expect(spoken, contains('Gewicht in kg'));
      expect(spoken, contains('Pflichtfeld'));
      expect(
        spoken,
        contains('Bitte einen Wert zwischen 20 und 400 kg eingeben.'),
      );
    });

    testWidgets('read only and disabled fields do not accept input', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'fix');
      addTearDown(controller.dispose);
      await pumpDesign(
        tester,
        AppTextField(label: 'Datum', readOnly: true, controller: controller),
      );
      await tester.enterText(find.byType(TextField), 'neu');
      expect(controller.text, 'fix');
    });
  });
}

void _noop() {}
