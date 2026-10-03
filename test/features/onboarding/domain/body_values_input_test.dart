import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/profile/profile_validation.dart';
import 'package:self_improvement/features/onboarding/domain/body_values_input.dart';

BodyValuesInput parse({
  String name = '',
  String height = '',
  String age = '',
  String weight = '',
}) => parseBodyValues(
  nameText: name,
  heightText: height,
  ageText: age,
  weightText: weight,
);

void main() {
  group('voluntary values', () {
    test('blank fields are valid and mean "not given", never a default', () {
      final input = parse();
      expect(input.isValid, isTrue);
      expect(input.displayName, isNull);
      expect(input.heightCm, isNull);
      expect(input.ageYears, isNull);
      expect(input.startWeightGrams, isNull);
      // Whitespace only is blank as well.
      final blank = parse(name: '   ', height: ' ', age: '  ', weight: ' ');
      expect(blank.isValid, isTrue);
      expect(blank.displayName, isNull);
      expect(blank.heightCm, isNull);
    });

    test('valid values are parsed; the name is trimmed', () {
      final input = parse(
        name: '  Testperson ',
        height: '170',
        age: '30',
        weight: '71,5',
      );
      expect(input.isValid, isTrue);
      expect(input.displayName, 'Testperson');
      expect(input.heightCm, 170);
      expect(input.ageYears, 30);
      expect(input.startWeightGrams, 71500);
    });

    test('the weight accepts comma and period', () {
      expect(parse(weight: '71,5').startWeightGrams, 71500);
      expect(parse(weight: '71.5').startWeightGrams, 71500);
      expect(parse(weight: '72').startWeightGrams, 72000);
    });

    test('each field can be given alone', () {
      expect(parse(age: '45').ageYears, 45);
      expect(parse(age: '45').heightCm, isNull);
      expect(parse(height: '180').heightCm, 180);
      expect(parse(height: '180').ageYears, isNull);
      expect(parse(weight: '80').startWeightGrams, 80000);
      expect(parse(name: 'Ana').displayName, 'Ana');
    });
  });

  group('limits (both sides)', () {
    test('height 100 to 250 cm', () {
      expect(parse(height: '99').errors, contains(ProfileFields.heightCm));
      expect(parse(height: '100').isValid, isTrue);
      expect(parse(height: '250').isValid, isTrue);
      expect(parse(height: '251').errors, contains(ProfileFields.heightCm));
      expect(parse(height: '0').errors, contains(ProfileFields.heightCm));
    });

    test('age 18 to 120 years', () {
      expect(parse(age: '17').errors, contains(ProfileFields.ageYears));
      expect(parse(age: '18').isValid, isTrue);
      expect(parse(age: '120').isValid, isTrue);
      expect(parse(age: '121').errors, contains(ProfileFields.ageYears));
    });

    test('weight 20,0 to 350,0 kg in steps of 0,1', () {
      expect(parse(weight: '19,9').errors, contains(ProfileFields.startWeight));
      expect(parse(weight: '20,0').startWeightGrams, 20000);
      expect(parse(weight: '350,0').startWeightGrams, 350000);
      expect(
        parse(weight: '350,1').errors,
        contains(ProfileFields.startWeight),
      );
      expect(
        parse(weight: '71,55').errors,
        contains(ProfileFields.startWeight),
      );
    });

    test('name up to 40 characters after trimming', () {
      final forty = 'a' * 40;
      expect(parse(name: forty).displayName, forty);
      expect(parse(name: '  $forty  ').displayName, forty);
      expect(
        parse(name: '${forty}b').errors,
        contains(ProfileFields.displayName),
      );
    });
  });

  group('invalid input', () {
    test('non numeric texts are rejected with a hint per field', () {
      final input = parse(height: '17a', age: '-5', weight: 'abc');
      expect(input.isValid, isFalse);
      expect(
        input.errors.keys,
        containsAll(<String>[
          ProfileFields.heightCm,
          ProfileFields.ageYears,
          ProfileFields.startWeight,
        ]),
      );
      for (final message in input.errors.values) {
        expect(message, isNotEmpty);
      }
    });

    test('a huge number is an out-of-range error, not an overflow', () {
      expect(
        parse(height: '99999999999999999999').errors,
        contains(ProfileFields.heightCm),
      );
      expect(parse(age: '0000170').errors, contains(ProfileFields.ageYears));
    });

    test('an invalid field does not hide the valid ones', () {
      final input = parse(name: 'Ana', height: '999', age: '30', weight: '70');
      expect(input.errors.keys, <String>[ProfileFields.heightCm]);
      expect(input.heightCm, isNull);
      expect(input.displayName, 'Ana');
      expect(input.ageYears, 30);
      expect(input.startWeightGrams, 70000);
    });
  });
}
