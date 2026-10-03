import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/features/onboarding/application/onboarding_state.dart';

import '../../../support/pump_app.dart';
import '../support/onboarding_steps.dart';
import '../support/onboarding_test_env.dart';

/// The last visible element of every step: it must be reachable by scrolling.
final Map<OnboardingStep, Finder Function()> _lastElement =
    <OnboardingStep, Finder Function()>{
      OnboardingStep.welcome: () => find.text('Dranbleiben mit deiner Streak'),
      OnboardingStep.goals: () => find.text('Gute Gewohnheiten'),
      OnboardingStep.modules: () => find.text('Gamification'),
      OnboardingStep.body: () => find.textContaining('nicht als Messung'),
      OnboardingStep.dailyGoals: () =>
          find.textContaining('Erinnerungen sind ausgeschaltet'),
    };

void main() {
  group('semantics (Q02)', () {
    testSemantics('each step is announced as a header with its number', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('App-Name')),
        isSemantics(isHeader: true),
      );
      final titles = <String>[
        'Schritt 1 von 4: Was ist dein Ziel?',
        'Schritt 2 von 4: Was willst du nutzen?',
        'Schritt 3 von 4: Erzähl uns von dir',
        'Schritt 4 von 4: Deine Tagesziele',
      ];
      for (final title in titles) {
        await tapPrimary(tester);
        expect(
          tester.getSemantics(find.bySemanticsLabel(title)),
          isSemantics(isHeader: true, isLiveRegion: true),
          reason: title,
        );
      }
    });

    testSemantics('goal cards are checkable controls with a spoken state', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.goals);
      final card = find.bySemanticsLabel(
        'Abnehmen, Gewicht reduzieren und halten',
      );
      expect(
        tester.getSemantics(card),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          value: 'nicht ausgewählt',
          hasTapAction: true,
        ),
      );
      await tester.tap(card);
      await tester.pump();
      expect(
        tester.getSemantics(card),
        isSemantics(isChecked: true, value: 'ausgewählt'),
      );
    });

    testSemantics('module cards are toggles that say on or off', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.modules);
      final card = find.bySemanticsLabel(RegExp('^Gamification'));
      expect(
        tester.getSemantics(card),
        isSemantics(hasToggledState: true, isToggled: true, hasTapAction: true),
      );
      await tester.tap(card);
      await tester.pump();
      expect(tester.getSemantics(card), isSemantics(isToggled: false));
    });

    testSemantics(
      'body fields are labelled text fields; errors are announced next to them (C05)',
      (tester) async {
        await pumpOnboarding(tester);
        await goToStep(tester, OnboardingStep.body);
        for (final label in <String>[
          'Name, optional',
          'Alter in Jahren, optional',
          'Größe in Zentimetern, optional',
          'Startgewicht in Kilogramm, optional',
        ]) {
          expect(
            tester.getSemantics(find.bySemanticsLabel(label)),
            isSemantics(isTextField: true),
            reason: label,
          );
        }

        await typeInto(tester, 'age', '17');
        await tapPrimary(tester);
        const message = 'Bitte gib ein Alter zwischen 18 und 120 Jahren ein.';
        expect(
          tester.getSemantics(find.bySemanticsLabel(message)),
          isSemantics(isLiveRegion: true),
        );
      },
    );

    testSemantics('the goal steppers have spoken buttons and values', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await goToStep(tester, OnboardingStep.dailyGoals);
      for (final label in <String>[
        'Schrittziel erhöhen',
        'Schrittziel verringern',
        'Wasserziel erhöhen',
        'Fokusziel verringern',
        'Wochenziel für Workouts erhöhen',
      ]) {
        expect(
          tester.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(isButton: true, hasTapAction: true),
          reason: label,
        );
      }
      expect(
        tester.getSemantics(find.bySemanticsLabel('10.000 Schritte pro Tag')),
        isSemantics(isLiveRegion: true),
      );
      expect(find.bySemanticsLabel('2,5 Liter pro Tag'), findsOneWidget);
      expect(find.bySemanticsLabel('25 Minuten Fokus pro Tag'), findsOneWidget);
      expect(find.bySemanticsLabel('3 Workouts pro Woche'), findsOneWidget);

      // The end of a range is spoken as disabled.
      await tapStepper(tester, 'Workouts', plus: true, times: 20);
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Wochenziel für Workouts erhöhen'),
        ),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      expect(find.bySemanticsLabel('14 Workouts pro Woche'), findsOneWidget);
    });

    testSemantics('back and skip are labelled buttons; decoration is hidden', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await tapPrimary(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Zurück')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Überspringen')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      // The progress segments carry no semantics: "Schritt N von 4" does.
      expect(find.bySemanticsLabel(RegExp(r'^\d von 4$')), findsNothing);
    });
  });

  group('tap targets and labels (Q02)', () {
    for (final (size, scale) in <(Size, double)>[
      (const Size(393, 852), 1.0),
      (const Size(320, 640), 2.0),
    ]) {
      testSemantics(
        'every step meets the Android tap target and label guidelines at ${size.width.toInt()} px, text ${scale}x',
        (tester) async {
          await pumpOnboarding(tester, size: size, textScale: scale);
          for (final step in OnboardingStep.values) {
            if (step != OnboardingStep.welcome) {
              await tapPrimary(tester);
            }
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
              reason: '${step.name}: tap targets',
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
              reason: '${step.name}: labels',
            );
          }
        },
      );
    }
  });

  group('responsive layout (Q02)', () {
    for (final size in responsiveSizes) {
      for (final scale in <double>[1.0, 2.0]) {
        testWidgets(
          'all five screens fit ${size.width.toInt()} x ${size.height.toInt()} at text ${scale}x: no overflow, content scrolls, the primary action stays reachable',
          (tester) async {
            await pumpOnboarding(tester, size: size, textScale: scale);
            for (final step in OnboardingStep.values) {
              if (step != OnboardingStep.welcome) {
                await tapPrimary(tester);
              }
              expect(
                tester.takeException(),
                isNull,
                reason: '${step.name}: no layout exception',
              );
              // The pinned primary action is fully on screen, 56 or higher.
              final button = tester.getRect(primaryButton);
              expect(button.left, greaterThanOrEqualTo(0));
              expect(button.right, lessThanOrEqualTo(size.width));
              expect(button.bottom, lessThanOrEqualTo(size.height));
              expect(button.height, greaterThanOrEqualTo(56));

              // The last element is reachable by scrolling and ends above the
              // button.
              final last = _lastElement[step]!();
              await tester.ensureVisible(last);
              await tester.pumpAndSettle();
              final rect = tester.getRect(last);
              expect(
                rect.bottom,
                lessThanOrEqualTo(tester.getRect(primaryButton).top + 1),
                reason: '${step.name}: last element above the primary action',
              );
              expect(rect.right, lessThanOrEqualTo(size.width));
              expect(rect.left, greaterThanOrEqualTo(0));
            }
          },
        );
      }
    }

    for (final (size, scale) in <(Size, double)>[
      (const Size(360, 800), 1.0),
      (const Size(320, 640), 2.0),
    ]) {
      testWidgets(
        'the primary action sits above the keyboard on the body step at ${size.width.toInt()} px, text ${scale}x (C05)',
        (tester) async {
          const keyboard = 280.0;
          await pumpOnboarding(
            tester,
            size: size,
            textScale: scale,
            viewInsets: const EdgeInsets.only(bottom: keyboard),
          );
          await goToStep(tester, OnboardingStep.body);
          await tester.ensureVisible(bodyField('weight'));
          await tester.pumpAndSettle();
          await tester.tap(bodyField('weight'));
          await tester.pump();
          await typeInto(tester, 'weight', '71,5');
          final button = tester.getRect(primaryButton);
          expect(button.bottom, lessThanOrEqualTo(size.height - keyboard + 1));
          await tester.tap(primaryButton);
          await tester.pumpAndSettle();
          expect(find.text('Deine Tagesziele'), findsOneWidget);
        },
      );
    }

    testWidgets(
      'the goal rows stack their stepper on a narrow screen instead of clipping (C07)',
      (tester) async {
        await pumpOnboarding(tester, size: const Size(320, 640));
        await goToStep(tester, OnboardingStep.dailyGoals);
        expect(tester.takeException(), isNull);
        for (final title in <String>[
          'Schritte',
          'Wasser',
          'Fokus',
          'Workouts',
        ]) {
          final row = tester.getRect(goalRow(title));
          final plus = tester.getRect(stepperButton(title, plus: true));
          final minus = tester.getRect(stepperButton(title, plus: false));
          expect(plus.right, lessThanOrEqualTo(row.right), reason: title);
          expect(minus.left, greaterThanOrEqualTo(row.left), reason: title);
        }
      },
    );
  });

  group('themes (C06)', () {
    for (final theme in AppThemeVariant.values) {
      testWidgets('all five screens render in ${theme.name} without errors', (
        tester,
      ) async {
        await pumpOnboarding(tester, theme: theme);
        for (final step in OnboardingStep.values) {
          if (step != OnboardingStep.welcome) {
            await tapPrimary(tester);
          }
          expect(tester.takeException(), isNull, reason: step.name);
          expect(primaryButton, findsOneWidget);
        }
        expect(find.text('Deine Tagesziele'), findsOneWidget);
      });
    }
  });

  group('motion (C06)', () {
    testWidgets('steps change at once with reduced motion', (tester) async {
      await pumpOnboarding(tester, reducedMotion: true);
      await tester.tap(primaryButton);
      await tester.pump();
      await tester.pump();
      expect(find.text('Was ist dein Ziel?'), findsOneWidget);
      expect(find.text('App-Name'), findsNothing, reason: 'no cross fade');
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('steps cross fade within 200 ms without reduced motion', (
      tester,
    ) async {
      await pumpOnboarding(tester);
      await tester.tap(primaryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('App-Name'), findsOneWidget, reason: 'still fading out');
      expect(find.text('Was ist dein Ziel?'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('App-Name'), findsNothing);
    });
  });
}
