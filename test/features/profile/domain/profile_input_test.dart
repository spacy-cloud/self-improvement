import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/features/profile/domain/profile_formatting.dart';
import 'package:self_improvement/features/profile/domain/profile_input.dart';
import 'package:self_improvement/shared/local_date.dart';

ProfileValues parsed(ProfileInput input) {
  final result = parseProfileInput(input);
  expect(result, isA<ProfileParsed>(), reason: '$result');
  return (result as ProfileParsed).values;
}

Map<String, String> errorsOf(ProfileInput input) {
  final result = parseProfileInput(input);
  expect(result, isA<ProfileInvalid>());
  return (result as ProfileInvalid).fieldErrors;
}

void main() {
  group('optional profile', () {
    test('an empty form is valid and invents nothing', () {
      final values = parsed(const ProfileInput());
      expect(values.displayName, isNull);
      expect(values.heightCm, isNull);
      expect(values.ageYears, isNull);
      expect(values.startWeightGrams, isNull);
      expect(values.targetWeightGrams, isNull);
    });

    test('blanks only count as empty', () {
      final values = parsed(
        const ProfileInput(
          name: '   ',
          heightText: ' ',
          ageText: ' ',
          startWeightText: ' ',
          targetWeightText: ' ',
        ),
      );
      expect(values.displayName, isNull);
      expect(values.heightCm, isNull);
      expect(values.startWeightGrams, isNull);
    });

    test('every field can be given on its own', () {
      expect(parsed(const ProfileInput(name: 'Mia')).displayName, 'Mia');
      expect(parsed(const ProfileInput(heightText: '170')).heightCm, 170);
      expect(parsed(const ProfileInput(ageText: '30')).ageYears, 30);
      expect(
        parsed(const ProfileInput(startWeightText: '74,0')).startWeightGrams,
        74000,
      );
      expect(
        parsed(const ProfileInput(targetWeightText: '68')).targetWeightGrams,
        68000,
      );
    });
  });

  group('name', () {
    test('is trimmed and limited to 40 characters', () {
      expect(
        parsed(const ProfileInput(name: '  Mia Muster  ')).displayName,
        'Mia Muster',
      );
      expect(
        parsed(ProfileInput(name: 'a' * 40)).displayName,
        'a' * 40,
        reason: 'exactly 40 is allowed',
      );
      expect(errorsOf(ProfileInput(name: 'a' * 41)).keys, [
        ProfileFields.displayName,
      ]);
    });

    test('the limit counts after trimming', () {
      expect(
        parsed(ProfileInput(name: '  ${'a' * 40}  ')).displayName,
        'a' * 40,
      );
    });
  });

  group('height', () {
    test('accepts 100 to 250 cm and rejects both sides of the limits', () {
      for (final ok in ['100', '170', '250']) {
        expect(parsed(ProfileInput(heightText: ok)).heightCm, int.parse(ok));
      }
      for (final bad in ['99', '251', '0', '1000']) {
        expect(errorsOf(ProfileInput(heightText: bad)).keys, [
          ProfileFields.heightCm,
        ], reason: bad);
      }
    });

    test('rejects text, decimals, signs and absurdly long numbers', () {
      for (final bad in ['abc', '17,5', '170.5', '-170', '+170', '1e2']) {
        expect(
          errorsOf(ProfileInput(heightText: bad))[ProfileFields.heightCm],
          contains('ganzen Zentimetern'),
          reason: bad,
        );
      }
      expect(errorsOf(ProfileInput(heightText: '9' * 30)).keys, [
        ProfileFields.heightCm,
      ]);
    });
  });

  group('age', () {
    test('accepts 18 to 120 years and rejects both sides of the limits', () {
      for (final ok in ['18', '30', '120']) {
        expect(parsed(ProfileInput(ageText: ok)).ageYears, int.parse(ok));
      }
      for (final bad in ['17', '121', '0']) {
        expect(errorsOf(ProfileInput(ageText: bad)).keys, [
          ProfileFields.ageYears,
        ], reason: bad);
      }
      expect(
        errorsOf(
          const ProfileInput(ageText: 'dreißig'),
        )[ProfileFields.ageYears],
        contains('ganzen Jahren'),
      );
    });
  });

  group('weights', () {
    test('accept comma or period with one decimal from 20,0 to 350,0 kg', () {
      expect(
        parsed(const ProfileInput(startWeightText: '71,5')).startWeightGrams,
        71500,
      );
      expect(
        parsed(const ProfileInput(startWeightText: '71.5')).startWeightGrams,
        71500,
      );
      expect(
        parsed(const ProfileInput(startWeightText: '20,0')).startWeightGrams,
        20000,
        reason: 'lower limit',
      );
      expect(
        parsed(const ProfileInput(targetWeightText: '350,0')).targetWeightGrams,
        350000,
        reason: 'upper limit',
      );
    });

    test('reject 19,9 and 350,1, a second decimal and non numbers', () {
      for (final bad in [
        '19,9',
        '350,1',
        '71,55',
        'NaN',
        'abc',
        '1e2',
        '-70',
      ]) {
        expect(errorsOf(ProfileInput(startWeightText: bad)).keys, [
          ProfileFields.startWeight,
        ], reason: bad);
        expect(errorsOf(ProfileInput(targetWeightText: bad)).keys, [
          ProfileFields.targetWeight,
        ], reason: bad);
      }
    });

    test('the second decimal gets its own hint (no silent rounding)', () {
      expect(
        errorsOf(
          const ProfileInput(targetWeightText: '71,55'),
        )[ProfileFields.targetWeight],
        contains('Nachkommastelle'),
      );
    });

    test('target weight may equal, undercut or exceed the start weight', () {
      for (final target in ['74,0', '68,0', '80,0']) {
        final values = parsed(
          ProfileInput(startWeightText: '74,0', targetWeightText: target),
        );
        expect(values.startWeightGrams, 74000);
        expect(values.targetWeightGrams, isNotNull);
      }
    });
  });

  test('all invalid fields are reported together, none is dropped', () {
    final errors = errorsOf(
      ProfileInput(
        name: 'x' * 41,
        heightText: '99',
        ageText: '17',
        startWeightText: '19,9',
        targetWeightText: '350,1',
      ),
    );
    expect(errors.keys.toSet(), {
      ProfileFields.displayName,
      ProfileFields.heightCm,
      ProfileFields.ageYears,
      ProfileFields.startWeight,
      ProfileFields.targetWeight,
    });
  });

  group('ProfileInput', () {
    test(
      'shows stored values and never puts the default name in the field',
      () {
        final input = ProfileInput.fromProfile(
          UserProfile(
            startedOn: LocalDate(2026, 10, 1),
            onboardingCompleted: true,
            rowVersion: 1,
            heightCm: 180,
            ageYears: 22,
            startWeightGrams: 74000,
            targetWeightGrams: 68000,
          ),
        );
        expect(input.name, isEmpty);
        expect(input.heightText, '180');
        expect(input.ageText, '22');
        expect(input.startWeightText, '74,0');
        expect(input.targetWeightText, '68,0');
      },
    );

    test('surrounding blanks are no change', () {
      expect(
        const ProfileInput(name: 'Mia'),
        const ProfileInput(name: ' Mia '),
      );
      expect(
        const ProfileInput(name: 'Mia'),
        isNot(const ProfileInput(name: 'Mia B')),
      );
    });
  });

  group('start weight proposal', () {
    StartWeightProposal? propose({
      String target = '68,0',
      int? storedTarget,
      String start = '',
      int? storedStart,
      int? latest = 71500,
    }) => proposeStartWeight(
      targetText: target,
      storedTargetGrams: storedTarget,
      startText: start,
      storedStartGrams: storedStart,
      latestMeasurementGrams: latest,
    );

    test('offers the latest measurement while a target is being set', () {
      expect(propose()!.grams, 71500);
      expect(propose(storedTarget: 70000)!.grams, 71500, reason: 'changed');
    });

    test('offers nothing without a measurement', () {
      expect(propose(latest: null), isNull);
    });

    test('offers nothing when a start weight exists or is being typed', () {
      expect(propose(start: '74,0'), isNull);
      expect(propose(storedStart: 74000, start: ''), isNull);
    });

    test('offers nothing for an unchanged, empty or invalid target', () {
      expect(propose(storedTarget: 68000), isNull);
      expect(propose(target: ''), isNull);
      expect(propose(target: '19,9'), isNull);
      expect(propose(target: 'abc'), isNull);
    });
  });

  group('formatting', () {
    test('initials follow the stored rule', () {
      expect(initialsForName('Max Mustermann'), 'MM');
      expect(initialsForName('  mia  '), 'M');
      expect(initialsForName('anna lena marie'), 'AL', reason: 'two parts');
      expect(initialsForName(''), isNull);
      expect(initialsForName('   '), isNull);
      expect(initialsForName(null), isNull);
    });

    test('member since and weights use German month names and commas', () {
      expect(
        formatMemberSince(LocalDate(2026, 10, 3)),
        'Dabei seit Oktober 2026',
      );
      expect(formatMemberSince(LocalDate(2027, 3, 1)), 'Dabei seit März 2027');
      expect(formatWeightKg(71500), '71,5 kg');
      expect(formatSignedWeightKg(-2500), '−2,5 kg');
      expect(formatSignedWeightKg(500), '+0,5 kg');
      expect(formatSignedWeightKg(0), '0,0 kg');
    });
  });
}
