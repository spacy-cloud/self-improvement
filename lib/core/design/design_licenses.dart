import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset path of the Inter licence text (SIL Open Font License 1.1).
const String interLicenseAsset = 'assets/fonts/OFL.txt';

bool _designLicensesRegistered = false;

/// Registers the licences of the bundled design assets (the font Inter) in
/// Flutter's [LicenseRegistry] so that they show up on the app's licence page.
///
/// Idempotent: the app bootstrap calls it once, every further call is a no-op.
void registerDesignLicenses() {
  if (_designLicensesRegistered) {
    return;
  }
  _designLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString(interLicenseAsset);
    yield LicenseEntryWithLineBreaks(const <String>['Inter'], text);
  });
}
