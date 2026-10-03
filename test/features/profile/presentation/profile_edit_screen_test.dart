import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/design/design.dart';
import 'package:self_improvement/core/providers/core_providers.dart';
import 'package:self_improvement/features/body/application/weight_providers.dart';
import 'package:self_improvement/features/profile/presentation/profile_routes.dart';

import '../../../support/pump_app.dart';
import '../support/screen_env.dart';

Finder iconButton(String label) => find.byWidgetPredicate(
  (widget) => widget is AppIconButton && widget.semanticLabel == label,
);

/// The text field below the label [label] of an `AppTextField`.
Finder field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AppTextField)),
  matching: find.byType(TextField),
);

String textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

Finder get saveButton => find.widgetWithText(PrimaryButton, 'Profil speichern');

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await settle(tester);
}

Future<void> seedFullProfile(WidgetTester tester, ScreenEnv env) async {
  await saveProfile(
    tester,
    env,
    name: 'Max Mustermann',
    heightCm: 180,
    ageYears: 22,
    startWeightGrams: 74000,
    targetWeightGrams: 68000,
  );
  env.profileCommands.commandIds.clear();
}

void main() {
  group('opening', () {
    testWidgets('an empty profile shows empty optional fields', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      expect(find.text('Profil bearbeiten'), findsOneWidget);
      for (final label in [
        'Name',
        'Größe in cm',
        'Alter in Jahren',
        'Startgewicht in kg',
        'Zielgewicht in kg',
      ]) {
        expect(textOf(tester, label), isEmpty, reason: label);
      }
      expect(
        find.text('optional'),
        findsNWidgets(5),
        reason: 'nothing is required',
      );
      expect(find.text('Pflichtfeld'), findsNothing);
      expect(
        find.text('Alle Angaben bleiben lokal auf deinem Gerät.'),
        findsOneWidget,
      );
      expect(find.textContaining('BMI'), findsNothing);
      expect(
        find.text('Geburtsjahr'),
        findsNothing,
        reason: 'age, not a birth date',
      );
      expect(
        tester.widget<PrimaryButton>(saveButton).onPressed,
        isNull,
        reason: 'nothing changed yet',
      );
    });

    testWidgets('shows the stored values', (tester) async {
      final env = await createScreenEnv(tester);
      await seedFullProfile(tester, env);
      await openScreen(tester, env, ProfileRoutes.edit);
      expect(textOf(tester, 'Name'), 'Max Mustermann');
      expect(textOf(tester, 'Größe in cm'), '180');
      expect(textOf(tester, 'Alter in Jahren'), '22');
      expect(textOf(tester, 'Startgewicht in kg'), '74,0');
      expect(textOf(tester, 'Zielgewicht in kg'), '68,0');
      await savePng(tester, 'build/profile_shots/profile_edit.png');
    });

    testWidgets('the initials preview follows the name while typing', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      expect(
        find.text('Ohne Namen zeigt dein Profil ein neutrales Symbol'),
        findsOneWidget,
      );

      await tester.enterText(field('Name'), 'Max Mustermann');
      await tester.pump();
      expect(find.text('MM'), findsOneWidget);
      expect(
        find.text('Initialen werden aus dem Namen erzeugt'),
        findsOneWidget,
      );

      await tester.enterText(field('Name'), 'mia');
      await tester.pump();
      expect(find.text('M'), findsOneWidget);

      await tester.enterText(field('Name'), '   ');
      await tester.pump();
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    });

    testWidgets('the name field takes at most 40 characters', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Name'), 'n' * 45);
      await tester.pump();
      expect(textOf(tester, 'Name').length, 40);
    });
  });

  group('saving', () {
    testWidgets(
      'saves valid input, confirms after the commit and closes (AT02)',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), '  Max Mustermann ');
        await tester.enterText(field('Größe in cm'), '180');
        await tester.enterText(field('Alter in Jahren'), '22');
        await tester.enterText(field('Startgewicht in kg'), '74.0');
        await tester.enterText(field('Zielgewicht in kg'), '68,0');
        await tester.pump();
        expect(
          env.feedback.events,
          isEmpty,
          reason: 'nothing before the commit',
        );

        await save(tester);

        expect(env.feedback.last!.kind, 'saved');
        expect(env.feedback.last!.message, 'Profil gespeichert');
        expect(
          find.text('Seite /'),
          findsOneWidget,
          reason: 'the editor closed',
        );
        final profile = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(profile.displayName, 'Max Mustermann');
        expect(profile.heightCm, 180);
        expect(profile.ageYears, 22);
        expect(profile.startWeightGrams, 74000);
        expect(profile.targetWeightGrams, 68000);
      },
    );

    testWidgets('the saved profile is shown again after a restart (AT02)', (
      tester,
    ) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Name'), 'Mia');
      await tester.enterText(field('Größe in cm'), '170');
      await save(tester);

      // The process is killed (the widget tree is gone) and started again.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      env.newContainer();
      await openScreen(tester, env, ProfileRoutes.edit);
      expect(textOf(tester, 'Name'), 'Mia');
      expect(textOf(tester, 'Größe in cm'), '170');
      expect(textOf(tester, 'Alter in Jahren'), isEmpty);
    });

    testWidgets('an optional profile can be emptied again', (tester) async {
      final env = await createScreenEnv(tester);
      await seedFullProfile(tester, env);
      await openScreen(tester, env, ProfileRoutes.edit);
      for (final label in [
        'Name',
        'Größe in cm',
        'Alter in Jahren',
        'Startgewicht in kg',
        'Zielgewicht in kg',
      ]) {
        await tester.enterText(field(label), '');
      }
      await tester.pump();
      await save(tester);
      expect(env.feedback.last!.message, 'Profil gespeichert');
      final profile = (await tester.runAsync(
        () => env.container.read(profileRepositoryProvider).get(),
      ))!;
      expect(profile.displayName, isNull);
      expect(profile.heightCm, isNull);
      expect(profile.targetWeightGrams, isNull);
    });
  });

  group('validation', () {
    testWidgets(
      'an invalid value shows its hint at the field and keeps all input',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), 'Max');
        await tester.enterText(field('Größe in cm'), '99');
        await tester.enterText(field('Alter in Jahren'), '30');
        await tester.pump();
        await save(tester);

        expect(
          find.text('Bitte gib eine Größe zwischen 100 und 250 cm ein.'),
          findsOneWidget,
        );
        expect(
          find.text('Bitte prüfe die markierten Angaben.'),
          findsOneWidget,
        );
        expect(textOf(tester, 'Größe in cm'), '99', reason: 'the input stays');
        expect(textOf(tester, 'Name'), 'Max');
        expect(textOf(tester, 'Alter in Jahren'), '30');
        expect(env.feedback.events.where((e) => e.kind == 'saved'), isEmpty);
        expect(
          env.profileCommands.commandIds,
          isEmpty,
          reason: 'nothing was sent',
        );
        expect(
          tester.widget<TextField>(field('Größe in cm')).focusNode!.hasFocus,
          isTrue,
          reason: 'the first invalid field gets the focus',
        );
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.heightCm, isNull);
        expect(stored.displayName, isNull);

        // The hint disappears when the user corrects the value; then it saves.
        await tester.enterText(field('Größe in cm'), '180');
        await tester.pump();
        expect(
          find.text('Bitte gib eine Größe zwischen 100 und 250 cm ein.'),
          findsNothing,
        );
        await save(tester);
        expect(env.feedback.last!.message, 'Profil gespeichert');
      },
    );

    testWidgets('weight hints name the decimals and the range', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Startgewicht in kg'), '71,55');
      await tester.enterText(field('Zielgewicht in kg'), '19,9');
      await tester.pump();
      await save(tester);
      expect(
        find.text(
          'Bitte gib höchstens eine Nachkommastelle an, zum Beispiel 71,5.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Bitte gib ein Gewicht zwischen 20,0 und 350,0 kg ein.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'Startgewicht in kg'), '71,55');
    });

    testWidgets('age below 18 is rejected next to the field', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Alter in Jahren'), '17');
      await tester.pump();
      await save(tester);
      expect(
        find.text('Bitte gib ein Alter zwischen 18 und 120 Jahren ein.'),
        findsOneWidget,
      );
    });
  });

  group('cancelling', () {
    testWidgets('leaving without a change does not ask', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.tap(iconButton('Zurück'));
      await settle(tester);
      expect(find.text('Änderungen verwerfen?'), findsNothing);
      expect(find.text('Seite /'), findsOneWidget);
    });

    testWidgets(
      'leaving with a change asks; "Weiter bearbeiten" keeps the input',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), 'Max');
        await tester.pump();
        await tester.tap(iconButton('Zurück'));
        await settle(tester);
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);

        await tester.tap(find.text('Weiter bearbeiten'));
        await settle(tester);
        expect(find.text('Änderungen verwerfen?'), findsNothing);
        expect(textOf(tester, 'Name'), 'Max');
        expect(find.text('Profil bearbeiten'), findsOneWidget);
      },
    );

    testWidgets('"Verwerfen" leaves and saves nothing', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Name'), 'Max');
      await tester.pump();
      await tester.tap(iconButton('Zurück'));
      await settle(tester);
      await tester.tap(find.text('Verwerfen'));
      await settle(tester);

      expect(find.text('Seite /'), findsOneWidget);
      expect(env.profileCommands.commandIds, isEmpty);
      final stored = (await tester.runAsync(
        () => env.container.read(profileRepositoryProvider).get(),
      ))!;
      expect(stored.displayName, isNull);
    });

    testWidgets(
      'Android back asks too, and a second back closes the question',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), 'Max');
        await tester.pump();

        await tester.binding.handlePopRoute();
        await settle(tester);
        expect(find.text('Änderungen verwerfen?'), findsOneWidget);
        expect(find.text('Weiter bearbeiten'), findsOneWidget);

        await tester.binding.handlePopRoute(); // back closes the sheet only
        await settle(tester);
        expect(find.text('Änderungen verwerfen?'), findsNothing);
        expect(textOf(tester, 'Name'), 'Max');
      },
    );
  });

  group('failures', () {
    testWidgets(
      'a failed save keeps the input; the retry saves once with the same id',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), 'Max');
        await tester.enterText(field('Größe in cm'), '180');
        await tester.pump();

        env.projection.failure = StateError('disk full');
        await save(tester);
        expect(env.feedback.last!.kind, 'error');
        expect(
          env.feedback.last!.message,
          'Speichern fehlgeschlagen. Deine Eingaben bleiben erhalten.',
        );
        expect(env.feedback.last!.onRetry, isNotNull);
        expect(textOf(tester, 'Name'), 'Max');
        expect(textOf(tester, 'Größe in cm'), '180');
        expect(
          find.text('Profil bearbeiten'),
          findsOneWidget,
          reason: 'still open',
        );

        env.projection.failure = null;
        env.feedback.last!.onRetry!();
        await settle(tester);
        expect(env.feedback.last!.kind, 'saved');
        expect(env.profileCommands.commandIds, hasLength(2));
        expect(
          env.profileCommands.commandIds[0],
          env.profileCommands.commandIds[1],
        );
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.displayName, 'Max');
        expect(stored.rowVersion, 2, reason: 'written once');
      },
    );

    testWidgets(
      'a retry offered after the editor was left does nothing and does not crash',
      (tester) async {
        final env = await createScreenEnv(tester);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Name'), 'Max');
        await tester.pump();
        env.projection.failure = StateError('disk full');
        await save(tester);
        expect(env.feedback.last!.kind, 'error');

        await tester.tap(iconButton('Zurück'));
        await settle(tester);
        await tester.tap(find.text('Verwerfen'));
        await settle(tester);
        expect(find.text('Seite /'), findsOneWidget);

        env.projection.failure = null;
        env.feedback.last!.onRetry!(); // the snack bar is still on screen
        await settle(tester);
        expect(
          env.profileCommands.commandIds,
          hasLength(1),
          reason: 'only the failed attempt',
        );
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.displayName, isNull);
      },
    );

    testWidgets('a double tap on save sends one command', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Name'), 'Max');
      await tester.pump();
      await tester.tap(saveButton);
      await tester.tap(saveButton);
      await settle(tester);
      expect(env.profileCommands.commandIds, hasLength(1));
      expect(env.feedback.events.where((e) => e.kind == 'saved'), hasLength(1));
    });
  });

  group('start weight proposal (W02)', () {
    testWidgets(
      'setting a target proposes the last measurement; it needs a tap',
      (tester) async {
        final env = await createScreenEnv(tester);
        await addWeight(tester, env, 71500);
        await openScreen(tester, env, ProfileRoutes.edit);
        expect(find.text('Als Startgewicht übernehmen'), findsNothing);

        await tester.enterText(field('Zielgewicht in kg'), '68,0');
        await tester.pump();
        expect(
          find.text(
            'Deine letzte Messung ist 71,5 kg. Möchtest du sie als Startgewicht übernehmen?',
          ),
          findsOneWidget,
        );
        expect(
          textOf(tester, 'Startgewicht in kg'),
          isEmpty,
          reason: 'not applied',
        );

        await tester.ensureVisible(find.text('Als Startgewicht übernehmen'));
        await tester.tap(find.text('Als Startgewicht übernehmen'));
        await tester.pump();
        expect(textOf(tester, 'Startgewicht in kg'), '71,5');
        expect(find.text('Als Startgewicht übernehmen'), findsNothing);

        await save(tester);
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.startWeightGrams, 71500);
        expect(stored.targetWeightGrams, 68000);
        final entries = (await tester.runAsync(
          () =>
              env.container.read(weightRepositoryProvider).watchActive().first,
        ))!;
        expect(
          entries,
          hasLength(1),
          reason: 'the profile did not add a measurement',
        );
        expect(entries.single.weightGrams, 71500);
      },
    );

    testWidgets(
      'ignoring the proposal saves the target without a start weight',
      (tester) async {
        final env = await createScreenEnv(tester);
        await addWeight(tester, env, 71500);
        await openScreen(tester, env, ProfileRoutes.edit);
        await tester.enterText(field('Zielgewicht in kg'), '68,0');
        await tester.pump();
        await save(tester);
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.targetWeightGrams, 68000);
        expect(stored.startWeightGrams, isNull);
      },
    );

    testWidgets('without a measurement there is no proposal', (tester) async {
      final env = await createScreenEnv(tester);
      await openScreen(tester, env, ProfileRoutes.edit);
      await tester.enterText(field('Zielgewicht in kg'), '68,0');
      await tester.pump();
      expect(find.text('Als Startgewicht übernehmen'), findsNothing);
    });
  });

  group('modules', () {
    testWidgets(
      'with the body module off the body fields are hidden and kept',
      (tester) async {
        final env = await createScreenEnv(tester, enabledModules: {'tasks'});
        await saveProfile(
          tester,
          env,
          name: 'Max',
          heightCm: 180,
          targetWeightGrams: 68000,
        );
        await openScreen(tester, env, ProfileRoutes.edit);
        expect(find.text('Größe in cm'), findsNothing);
        expect(find.text('Zielgewicht in kg'), findsNothing);
        expect(find.textContaining('Körpermodul'), findsOneWidget);

        await tester.enterText(field('Name'), 'Maxi');
        await tester.pump();
        await save(tester);
        final stored = (await tester.runAsync(
          () => env.container.read(profileRepositoryProvider).get(),
        ))!;
        expect(stored.displayName, 'Maxi');
        expect(stored.heightCm, 180, reason: 'hidden values stay');
        expect(stored.targetWeightGrams, 68000);
      },
    );
  });

  testWidgets('every control has a spoken German label (AT34)', (tester) async {
    final handle = tester.ensureSemantics();
    final env = await createScreenEnv(tester);
    await openScreen(tester, env, ProfileRoutes.edit);
    expect(find.bySemanticsLabel('Zurück'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Name')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('^Größe in cm')), findsWidgets);
    expect(find.bySemanticsLabel('Profil speichern'), findsOneWidget);
    handle.dispose();
  });
}
