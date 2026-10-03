import 'package:flutter_test/flutter_test.dart';
import 'package:self_improvement/core/profile/user_profile.dart';
import 'package:self_improvement/shared/local_date.dart';

UserProfile profile({String? name}) => UserProfile(
  startedOn: LocalDate(2026, 10, 3),
  onboardingCompleted: true,
  rowVersion: 1,
  displayName: name,
);

void main() {
  test(
    'without a name the default name is shown and there are no initials',
    () {
      expect(profile().effectiveName, 'Mein Profil');
      expect(profile().initials, isNull);
    },
  );

  test('initials use at most two name parts', () {
    expect(profile(name: 'Mia Muster').initials, 'MM');
    expect(profile(name: 'mia').initials, 'M');
    expect(profile(name: 'Anna Maria Schmidt').initials, 'AM');
    expect(profile(name: '  Ömer   Yilmaz ').initials, 'ÖY');
    expect(profile(name: 'Mia Muster').effectiveName, 'Mia Muster');
  });
}
